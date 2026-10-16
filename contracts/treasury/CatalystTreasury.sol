// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CatalystUUPS} from "../common/CatalystUUPS.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract CatalystTreasury is CatalystUUPS, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    IERC20 public cata;
    address public governance;
    uint256 public maxSinglePayoutBps;
    mapping(bytes32 => bool) public executed;

    error NotGovernance();
    error AlreadyExecuted();
    event TreasuryPayout(bytes32 indexed proposalId, address indexed recipient, uint256 amount, bytes32 purpose);

    constructor() { _disableInitializers(); }

    function initialize(address cata_, address governance_, address upgradeAuthority_) external initializer {
        require(cata_ != address(0) && governance_ != address(0), "zero address");
        __ReentrancyGuard_init();
        __CatalystUUPS_init(upgradeAuthority_);
        cata = IERC20(cata_);
        governance = governance_;
        maxSinglePayoutBps = 1000; // Proposed safeguard: 10% of proposal snapshot balance.
    }

    function payout(bytes32 proposalId, address recipient, uint256 amount, bytes32 purpose, uint256 snapshotBalance) external nonReentrant {
        if (msg.sender != governance) revert NotGovernance();
        if (executed[proposalId]) revert AlreadyExecuted();
        require(recipient != address(0) && amount > 0, "invalid payout");
        require(amount <= snapshotBalance * maxSinglePayoutBps / 10_000, "single payout limit");
        executed[proposalId] = true;
        cata.safeTransfer(recipient, amount);
        emit TreasuryPayout(proposalId, recipient, amount, purpose);
    }

    uint256[40] private __gap;
}
