// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CatalystUUPS} from "../common/CatalystUUPS.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ICATAPayments {
    function payFee(uint256 fee) external;
}

contract CollectionRegistry is CatalystUUPS {
    using SafeERC20 for IERC20;

    enum Tier { NONE, UNVERIFIED, VERIFIED, BLUE_CHIP }
    uint256 public constant BASE_REGISTRATION_FEE = 100 ether;
    uint256 public constant UNVERIFIED_ESCROW = 500 ether;
    uint256 public constant ESCROW_WINDOW = 180 days;
    uint256 public constant MAX_COLLECTION_NFTS = 20_000;

    struct Collection {
        Tier tier;
        uint64 registeredAt;
        uint64 escrowDeadline;
        uint32 stakedCount;
        uint256 escrowAmount;
        bool incidentFlag;
    }

    IERC20 public cata;
    address public staking;
    address public governance;
    mapping(address => Collection) private collections;
    address[] private collectionList;

    error InvalidCollection();
    error AlreadyRegistered();
    error NotAuthorized();
    error InvalidTier();
    error EscrowUnavailable();

    event CollectionRegistered(address indexed collection, Tier tier, address indexed registrar, uint256 fee, uint256 escrow);
    event TierChanged(address indexed collection, Tier oldTier, Tier newTier, bytes32 indexed proposalId);
    event IncidentFlagChanged(address indexed collection, bool flagged);
    event EscrowSettled(address indexed collection, address indexed recipient, uint256 amount, bool refunded);

    constructor() { _disableInitializers(); }

    function initialize(address cata_, address upgradeAuthority_, address governance_) external initializer {
        require(cata_ != address(0) && upgradeAuthority_ != address(0), "zero address");
        cata = IERC20(cata_);
        governance = governance_;
        __CatalystUUPS_init(upgradeAuthority_);
    }

    function setGovernance(address governance_) external onlyUpgradeAuthority {
        require(governance == address(0) && governance_ != address(0), "governance configured");
        governance = governance_;
    }

    function setStaking(address staking_) external onlyUpgradeAuthority {
        require(staking == address(0) && staking_ != address(0), "staking configured");
        staking = staking_;
    }

    function registerCollection(address collection, bool requestVerified) external {
        if (collection == address(0) || collection.code.length == 0) revert InvalidCollection();
        if (collections[collection].tier != Tier.NONE) revert AlreadyRegistered();
        uint256 fee = BASE_REGISTRATION_FEE;
        uint256 escrow = requestVerified ? 0 : UNVERIFIED_ESCROW;
        uint256 total = fee + escrow;
        cata.safeTransferFrom(msg.sender, address(this), total);
        // The registration fee is routed via token's fee distributor only if approved by the user.
        // This registry holds fee funds; settlement must be explicit and audited in deployment.
        collections[collection] = Collection({
            tier: requestVerified ? Tier.VERIFIED : Tier.UNVERIFIED,
            registeredAt: uint64(block.timestamp),
            escrowDeadline: uint64(block.timestamp + ESCROW_WINDOW),
            stakedCount: 0,
            escrowAmount: escrow,
            incidentFlag: false
        });
        collectionList.push(collection);
        emit CollectionRegistered(collection, collections[collection].tier, msg.sender, fee, escrow);
    }

    function setTier(address collection, Tier newTier, bytes32 proposalId) external {
        if (msg.sender != governance && msg.sender != upgradeAuthority) revert NotAuthorized();
        Collection storage c = collections[collection];
        if (c.tier == Tier.NONE || newTier == Tier.NONE) revert InvalidTier();
        Tier old = c.tier;
        c.tier = newTier;
        emit TierChanged(collection, old, newTier, proposalId);
    }

    function setIncidentFlag(address collection, bool flagged) external {
        if (msg.sender != governance && msg.sender != upgradeAuthority) revert NotAuthorized();
        if (collections[collection].tier == Tier.NONE) revert InvalidCollection();
        collections[collection].incidentFlag = flagged;
        emit IncidentFlagChanged(collection, flagged);
    }

    function settleEscrow(address collection, address recipient, bool refund) external {
        if (msg.sender != governance && msg.sender != upgradeAuthority) revert NotAuthorized();
        Collection storage c = collections[collection];
        if (c.tier == Tier.NONE || c.escrowAmount == 0) revert EscrowUnavailable();
        if (refund && (block.timestamp > c.escrowDeadline || c.tier != Tier.VERIFIED || c.incidentFlag)) revert EscrowUnavailable();
        uint256 amount = c.escrowAmount;
        c.escrowAmount = 0;
        cata.safeTransfer(recipient, amount);
        emit EscrowSettled(collection, recipient, amount, refund);
    }

    function getCollection(address collection) external view returns (Collection memory) { return collections[collection]; }
    function collectionCount() external view returns (uint256) { return collectionList.length; }
    function collectionAt(uint256 i) external view returns (address) { return collectionList[i]; }

    function noteStake(address collection, int256 delta) external {
        require(msg.sender == staking, "only staking");
        Collection storage c = collections[collection];
        require(c.tier != Tier.NONE, "not registered");
        if (delta > 0) {
            uint256 next = uint256(c.stakedCount) + uint256(delta);
            require(next <= MAX_COLLECTION_NFTS, "collection cap");
            c.stakedCount = uint32(next);
        } else {
            uint256 amount = uint256(-delta);
            require(amount <= c.stakedCount, "counter underflow");
            c.stakedCount -= uint32(amount);
        }
    }

    uint256[40] private __gap;
}
