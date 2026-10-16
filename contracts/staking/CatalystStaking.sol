// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CatalystUUPS} from "../common/CatalystUUPS.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

interface ICATAMint { function mintReward(address to, uint256 amount) external; }
interface ICollectionRegistry {
    enum Tier { NONE, UNVERIFIED, VERIFIED, BLUE_CHIP }
    function getCollection(address) external view returns (
        Tier tier, uint64 registeredAt, uint64 escrowDeadline, uint32 stakedCount, uint256 escrowAmount, bool incidentFlag
    );
    function noteStake(address, int256) external;
}

contract CatalystStaking is CatalystUUPS, IERC721Receiver, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant GLOBAL_CAP = 500_000_000;
    uint256 public constant TERM_CAP = 375_000_000;
    uint256 public constant PERMANENT_CAP = 125_000_000;
    uint256 public constant MAX_HARVEST_BATCH = 50;
    uint256 public constant ANNUAL_REWARD_CAP = 20_000_000 ether; // Proposed v1.1 default.
    uint256 public constant YEAR = 365 days;
    uint256 public constant HARVEST_FEE_BPS = 200; // Proposed default: 2%.
    uint256 public constant UNSTAKE_FEE_BPS = 100; // Proposed default: 1%.
    uint256 public constant BPS = 10_000;

    enum StakeType { TERM, PERMANENT }
    struct Position {
        address owner;
        address collection;
        uint256 tokenId;
        uint64 startedAt;
        uint64 lastHarvestAt;
        uint64 termEndsAt;
        StakeType stakeType;
        bool active;
    }

    ICATAMint public cata;
    IERC20 public cataTransfer;
    ICollectionRegistry public registry;
    address public governance;
    uint256 public termCount;
    uint256 public permanentCount;
    uint256 public rewardRatePerNFTPerDay; // Set at deployment; wei CATA per NFT per day.
    uint256 public annualWindowStart;
    uint256 public mintedInWindow;
    uint256 public totalStaked;
    uint256 public nextPositionId;
    mapping(uint256 => Position) public positions;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public positionOf;
    mapping(address => uint256) public userActiveCount;
    mapping(uint256 => uint256) public dailyMinted; // UTC-day bucket used for true rolling 365-day accounting.

    error InvalidPosition();
    error CapExceeded();
    error NotOwner();
    error WrongTier();
    error TermNotEnded();
    error InvalidBatch();

    event Staked(uint256 indexed positionId, address indexed owner, address indexed collection, uint256 tokenId, StakeType stakeType, uint256 termEndsAt);
    event Harvested(uint256 indexed positionId, address indexed owner, uint256 gross, uint256 fee, uint256 net);
    event Unstaked(uint256 indexed positionId, address indexed owner, uint256 grossAccrued, uint256 fee);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    constructor() { _disableInitializers(); }

    function initialize(address cata_, address registry_, address governance_, address upgradeAuthority_, uint256 rewardRate_) external initializer {
        require(cata_ != address(0) && registry_ != address(0) && governance_ != address(0), "zero address");
        __ReentrancyGuard_init();
        __CatalystUUPS_init(upgradeAuthority_);
        cata = ICATAMint(cata_);
        cataTransfer = IERC20(cata_);
        registry = ICollectionRegistry(registry_);
        governance = governance_;
        rewardRatePerNFTPerDay = rewardRate_;
        annualWindowStart = block.timestamp;
        nextPositionId = 1;
    }

    function setGovernance(address governance_) external onlyUpgradeAuthority {
        require(governance == address(0) && governance_ != address(0), "governance configured");
        governance = governance_;
    }

    function setRewardRate(uint256 newRate) external {
        require(msg.sender == governance, "only governance");
        emit RewardRateUpdated(rewardRatePerNFTPerDay, newRate);
        rewardRatePerNFTPerDay = newRate;
    }

    function stake(address collection, uint256 tokenId, StakeType stakeType, uint64 termDuration) external nonReentrant {
        (ICollectionRegistry.Tier tier,,,,,) = registry.getCollection(collection);
        if (tier != ICollectionRegistry.Tier.VERIFIED && tier != ICollectionRegistry.Tier.UNVERIFIED) revert WrongTier();
        if (totalStaked >= GLOBAL_CAP) revert CapExceeded();
        if (stakeType == StakeType.TERM) {
            if (termCount >= TERM_CAP || termDuration < 1 days) revert CapExceeded();
            termCount++;
        } else {
            if (permanentCount >= PERMANENT_CAP) revert CapExceeded();
            permanentCount++;
        }
        require(positionOf[collection][msg.sender][tokenId] == 0, "already staked");
        IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);
        uint256 id = nextPositionId++;
        uint64 ends = stakeType == StakeType.TERM ? uint64(block.timestamp + termDuration) : 0;
        positions[id] = Position(msg.sender, collection, tokenId, uint64(block.timestamp), uint64(block.timestamp), ends, stakeType, true);
        positionOf[collection][msg.sender][tokenId] = id;
        userActiveCount[msg.sender]++;
        totalStaked++;
        registry.noteStake(collection, 1);
        emit Staked(id, msg.sender, collection, tokenId, stakeType, ends);
    }

    function pendingReward(uint256 id) public view returns (uint256) {
        Position memory p = positions[id];
        if (!p.active) return 0;
        uint256 elapsed = block.timestamp - p.lastHarvestAt;
        uint256 reward = elapsed * rewardRatePerNFTPerDay / 1 days;
        uint256 headroom = cata.totalSupply() >= 1_000_000_000 ether ? 0 : 1_000_000_000 ether - cata.totalSupply();
        if (reward > headroom) reward = headroom;
        uint256 rolling = rollingMintedLast365Days();
        uint256 remaining = rolling >= ANNUAL_REWARD_CAP ? 0 : ANNUAL_REWARD_CAP - rolling;
        if (reward > remaining) reward = remaining;
        return reward;
    }

    function harvest(uint256[] calldata ids) external nonReentrant {
        if (ids.length == 0 || ids.length > MAX_HARVEST_BATCH) revert InvalidBatch();
        for (uint256 i; i < ids.length; ++i) {
            Position storage p = positions[ids[i]];
            if (!p.active) revert InvalidPosition();
            if (p.owner != msg.sender) revert NotOwner();
            uint256 gross = pendingReward(ids[i]);
            p.lastHarvestAt = uint64(block.timestamp);
            if (gross == 0) continue;
            uint256 fee = gross * HARVEST_FEE_BPS / BPS;
            uint256 net = gross - fee;
            _accountEmission(gross);
            if (net > 0) cata.mintReward(msg.sender, net);
            // Harvest fee is routed using the immutable 90/9/1 fee rule.
            if (fee > 0) {
                cata.mintReward(address(this), fee);
                _routeMintedFee(fee);
            }
            emit Harvested(ids[i], msg.sender, gross, fee, net);
        }
    }

    function unstake(uint256 id) external nonReentrant {
        Position storage p = positions[id];
        if (!p.active) revert InvalidPosition();
        if (p.owner != msg.sender) revert NotOwner();
        if (p.stakeType == StakeType.TERM && block.timestamp < p.termEndsAt) revert TermNotEnded();
        uint256 gross = pendingReward(id);
        p.active = false;
        p.lastHarvestAt = uint64(block.timestamp);
        _accountEmission(gross);
        uint256 fee = gross * UNSTAKE_FEE_BPS / BPS;
        if (gross > fee) cata.mintReward(msg.sender, gross - fee);
        if (fee > 0) {
            cata.mintReward(address(this), fee);
            _routeMintedFee(fee);
        }
        if (p.stakeType == StakeType.TERM) termCount--; else permanentCount--;
        totalStaked--;
        userActiveCount[msg.sender]--;
        delete positionOf[p.collection][msg.sender][p.tokenId];
        registry.noteStake(p.collection, -1);
        IERC721(p.collection).safeTransferFrom(address(this), msg.sender, p.tokenId);
        emit Unstaked(id, msg.sender, gross, fee);
    }

    /// @notice Sum emissions from the current UTC day and preceding 364 UTC days.
    /// The 365-slot loop is bounded and is used by harvest/unstake validation.
    function rollingMintedLast365Days() public view returns (uint256 total) {
        uint256 today = block.timestamp / 1 days;
        for (uint256 i; i < 365; ++i) {
            if (today < i) break;
            total += dailyMinted[today - i];
        }
    }

    function _accountEmission(uint256 amount) internal {
        uint256 rolling = rollingMintedLast365Days();
        require(amount <= ANNUAL_REWARD_CAP - (rolling > ANNUAL_REWARD_CAP ? ANNUAL_REWARD_CAP : rolling), "rolling annual cap");
        dailyMinted[block.timestamp / 1 days] += amount;
        mintedInWindow = rolling + amount; // legacy observable field; now represents rolling total
        annualWindowStart = block.timestamp;
    }

    function _routeMintedFee(uint256 fee) internal {
        uint256 burned = fee * 9000 / BPS;
        uint256 treasuryAmount = fee * 900 / BPS;
        uint256 maintainerAmount = fee - burned - treasuryAmount;
        // The fee was minted to this contract; token contract applies the immutable split.
        ICATMint(address(cata)).routeStakingFee(fee);
        emit FeeReserveAccrued(fee, burned, treasuryAmount, maintainerAmount);
    }

    event FeeReserveAccrued(uint256 fee, uint256 burned, uint256 treasuryAmount, uint256 maintainerAmount);

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    uint256[40] private __gap;
}
