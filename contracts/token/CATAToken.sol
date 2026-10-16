// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {CatalystUUPS} from "../common/CatalystUUPS.sol";

/// @title Catalyst (CATA)
/// @notice 1bn hard cap; initial 100m allocation; after initialization only staking may mint.
/// Applicable fees are conserved using immutable 90/9/1 routing.
contract CATAToken is ERC20Upgradeable, ERC20BurnableUpgradeable, CatalystUUPS {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant INITIAL_MINT = 100_000_000 ether;
    uint256 public constant BP_DENOMINATOR = 10_000;
    uint256 public constant BURN_BPS = 9_000;
    uint256 public constant TREASURY_BPS = 900;

    address public stakingContract;
    address public treasury;
    address public maintainer;
    address public configurationAuthority;
    bool public stakingConfigured;

    error SupplyCapExceeded();
    error OnlyStaking();
    error AlreadyConfigured();
    error InvalidAddress();
    error GenericRoleManagementDisabled();

    event InitialAllocationMinted(address indexed recipient, uint256 amount);
    event StakingContractConfigured(address indexed staking);
    event FeeDistributed(address indexed payer, uint256 fee, uint256 burned, uint256 treasuryAmount, uint256 maintainerAmount);
    event VoluntaryBurn(address indexed account, uint256 amount);

    constructor() { _disableInitializers(); }

    function initialize(
        address initialAllocation,
        address treasury_,
        address maintainer_,
        address upgradeAuthority_
    ) external initializer {
        if (initialAllocation == address(0) || treasury_ == address(0) ||
            maintainer_ == address(0) || upgradeAuthority_ == address(0)) revert InvalidAddress();
        __ERC20_init("Catalyst", "CATA");
        __ERC20Burnable_init();
        __CatalystUUPS_init(upgradeAuthority_);
        treasury = treasury_;
        maintainer = maintainer_;
        configurationAuthority = upgradeAuthority_;
        _mint(initialAllocation, INITIAL_MINT);
        emit InitialAllocationMinted(initialAllocation, INITIAL_MINT);
    }

    function setStakingContract(address staking_) external {
        if (msg.sender != configurationAuthority) revert Unauthorized();
        if (stakingConfigured) revert AlreadyConfigured();
        if (staking_ == address(0)) revert InvalidAddress();
        stakingContract = staking_;
        stakingConfigured = true;
        emit StakingContractConfigured(staking_);
    }

    function mintReward(address to, uint256 amount) external {
        if (msg.sender != stakingContract || !stakingConfigured) revert OnlyStaking();
        if (totalSupply() + amount > MAX_SUPPLY) revert SupplyCapExceeded();
        _mint(to, amount);
    }

    /// @notice Caller approves this contract for fee amount, then this function routes it.
    /// The caller must show these exact values in the DApp before wallet confirmation.
    function payFee(uint256 fee) external {
        if (fee == 0) revert InvalidAddress();
        _transfer(msg.sender, address(this), fee);
        uint256 burned = fee * BURN_BPS / BP_DENOMINATOR;
        uint256 treasuryAmount = fee * TREASURY_BPS / BP_DENOMINATOR;
        uint256 maintainerAmount = fee - burned - treasuryAmount;
        _burn(address(this), burned);
        _transfer(address(this), treasury, treasuryAmount);
        _transfer(address(this), maintainer, maintainerAmount);
        emit FeeDistributed(msg.sender, fee, burned, treasuryAmount, maintainerAmount);
    }

    /// @notice Routes fees already minted to the staking contract using the immutable 90/9/1 split.
    /// Only the configured staking contract may call this method.
    function routeStakingFee(uint256 fee) external {
        if (msg.sender != stakingContract || !stakingConfigured) revert OnlyStaking();
        if (fee == 0 || balanceOf(msg.sender) < fee) revert InvalidAddress();
        uint256 burned = fee * BURN_BPS / BP_DENOMINATOR;
        uint256 treasuryAmount = fee * TREASURY_BPS / BP_DENOMINATOR;
        uint256 maintainerAmount = fee - burned - treasuryAmount;
        _burn(msg.sender, burned);
        _transfer(msg.sender, treasury, treasuryAmount);
        _transfer(msg.sender, maintainer, maintainerAmount);
        emit FeeDistributed(msg.sender, fee, burned, treasuryAmount, maintainerAmount);
    }

    function voluntaryBurn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit VoluntaryBurn(msg.sender, amount);
    }

    function changeFeeRecipients(address, address) external pure {
        revert("fee recipients fixed in this release");
    }

    function grantRole(bytes32, address) public pure { revert GenericRoleManagementDisabled(); }
    function revokeRole(bytes32, address) public pure { revert GenericRoleManagementDisabled(); }
    function renounceRole(bytes32, address) public pure { revert GenericRoleManagementDisabled(); }

    uint256[40] private __gap;
}
