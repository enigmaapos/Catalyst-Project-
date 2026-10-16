// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CatalystUUPS} from "../common/CatalystUUPS.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @notice Guardian recovery coordinator. Only allowlisted targets/selectors may be executed.
/// Deployment must pre-seed both 7-member batches and set the last-honest guardian deterministically.
contract BatchGuardianCouncil is CatalystUUPS, ReentrancyGuardUpgradeable {
    uint256 public constant GUARDIANS = 7;
    uint256 public constant THRESHOLD = 5;
    uint256 public constant RECOVERY_DELAY = 4 hours;
    uint256 public constant VETO_WINDOW = 48 hours;
    uint256 public constant PROPOSAL_LIFETIME = 7 days;
    uint256 public constant RESEED_DELAY = 48 hours;

    address[7] public active;
    address[7] public standby;
    mapping(address => bool) public isActive;
    mapping(address => bool) public isStandby;
    mapping(address => bool) public approvedTarget;
    mapping(address => mapping(bytes4 => bool)) public approvedSelector;
    address public lastHonestGuardian;
    bool public locked;
    bool public warning;
    bool public standbyActivated;
    uint256 public nextRecoveryId;

    struct Recovery {
        address proposer;
        address target;
        bytes32 calldataHash;
        uint256 chainId;
        uint256 nonce;
        uint64 createdAt;
        uint64 executeAfter;
        uint64 expiresAt;
        uint8 approvals;
        bool vetoed;
        bool executed;
        mapping(address => bool) approved;
    }
    mapping(uint256 => Recovery) private recoveries;

    error NotGuardian();
    error InvalidRecovery();
    error NotReady();
    error TargetNotAllowed();
    error AlreadyApproved();
    error CouncilLocked();

    event RecoveryProposed(uint256 indexed id, address indexed proposer, address indexed target, bytes32 calldataHash, uint64 executeAfter, uint64 expiresAt);
    event RecoveryApproved(uint256 indexed id, address indexed guardian, uint8 approvals);
    event WarningActivated(uint256 indexed id, uint64 vetoEndsAt);
    event RecoveryVetoed(uint256 indexed id, address indexed guardian);
    event RecoveryExecuted(uint256 indexed id, address indexed executor);
    event CouncilLockedAndStandbyActivated();
    event GuardianBatchSeeded(bool indexed standbyBatch);
    event TargetAllowlisted(address indexed target, bytes4 indexed selector, bool allowed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address upgradeAuthority_, address lastHonestGuardian_) external initializer {
        require(lastHonestGuardian_ != address(0), "zero guardian");
        __CatalystUUPS_init(upgradeAuthority_);
        __ReentrancyGuard_init();
        lastHonestGuardian = lastHonestGuardian_;
        nextRecoveryId = 1;
    }

    function seedBatches(address[7] calldata active_, address[7] calldata standby_) external onlyUpgradeAuthority {
        require(!standbyActivated, "already activated");
        for (uint256 i; i < 7; ++i) {
            require(active_[i] != address(0) && standby_[i] != address(0), "zero guardian");
            for (uint256 j; j < i; ++j) {
                require(active_[i] != active_[j] && standby_[i] != standby_[j], "duplicate guardian");
            }
            require(active_[i] != standby_[i], "overlap");
            active[i] = active_[i]; standby[i] = standby_[i];
            isActive[active_[i]] = true; isStandby[standby_[i]] = true;
        }
        emit GuardianBatchSeeded(false);
        emit GuardianBatchSeeded(true);
    }

    function setAllowedSelector(address target, bytes4 selector, bool allowed) external onlyUpgradeAuthority {
        require(target != address(0), "zero target");
        approvedTarget[target] = allowed;
        approvedSelector[target][selector] = allowed;
        emit TargetAllowlisted(target, selector, allowed);
    }

    function proposeRecovery(address target, bytes calldata data, uint256 nonce) external returns (uint256 id) {
        if (locked) revert CouncilLocked();
        if (!isActive[msg.sender]) revert NotGuardian();
        if (!approvedTarget[target] || !approvedSelector[target][_selector(data)]) revert TargetNotAllowed();
        id = nextRecoveryId++;
        Recovery storage r = recoveries[id];
        r.proposer = msg.sender;
        r.target = target;
        r.calldataHash = keccak256(data);
        r.chainId = block.chainid;
        r.nonce = nonce;
        r.createdAt = uint64(block.timestamp);
        r.executeAfter = 0;
        r.expiresAt = uint64(block.timestamp + PROPOSAL_LIFETIME);
        r.approvals = 1;
        r.approved[msg.sender] = true;
        emit RecoveryProposed(id, msg.sender, target, r.calldataHash, 0, r.expiresAt);
        emit RecoveryApproved(id, msg.sender, 1);
    }

    function approveRecovery(uint256 id) external {
        if (locked) revert CouncilLocked();
        if (!isActive[msg.sender]) revert NotGuardian();
        Recovery storage r = recoveries[id];
        if (r.proposer == address(0) || r.vetoed || r.executed || block.timestamp > r.expiresAt) revert InvalidRecovery();
        if (r.approved[msg.sender]) revert AlreadyApproved();
        r.approved[msg.sender] = true;
        r.approvals++;
        emit RecoveryApproved(id, msg.sender, r.approvals);
        if (r.approvals == 5 && r.executeAfter == 0) {
            r.executeAfter = uint64(block.timestamp + RECOVERY_DELAY);
            r.expiresAt = uint64(uint256(r.executeAfter) + PROPOSAL_LIFETIME);
            emit RecoveryProposed(id, r.proposer, r.target, r.calldataHash, r.executeAfter, r.expiresAt);
        }
        if (r.approvals == 6 && !warning) {
            warning = true;
            emit WarningActivated(id, uint64(block.timestamp + VETO_WINDOW));
        }
        if (r.approvals == 7) {
            locked = true;
            standbyActivated = true;
            for (uint256 i; i < 7; ++i) isActive[active[i]] = false;
            for (uint256 i; i < 7; ++i) isActive[standby[i]] = true;
            emit CouncilLockedAndStandbyActivated();
        }
    }

    function vetoRecovery(uint256 id) external {
        if (msg.sender != lastHonestGuardian) revert NotGuardian();
        Recovery storage r = recoveries[id];
        if (r.proposer == address(0) || r.vetoed || r.executed || r.approvals < 6 || block.timestamp > uint256(r.createdAt) + VETO_WINDOW) revert InvalidRecovery();
        r.vetoed = true;
        emit RecoveryVetoed(id, msg.sender);
    }

    function executeRecovery(uint256 id, bytes calldata data) external nonReentrant {
        Recovery storage r = recoveries[id];
        if (r.proposer == address(0) || r.vetoed || r.executed || r.approvals < 5) revert InvalidRecovery();
        if (block.timestamp < r.executeAfter || block.timestamp > r.expiresAt) revert NotReady();
        if (r.chainId != block.chainid || keccak256(data) != r.calldataHash) revert InvalidRecovery();
        if (!approvedTarget[r.target] || !approvedSelector[r.target][_selector(data)]) revert TargetNotAllowed();
        r.executed = true;
        (bool ok, bytes memory result) = r.target.call(data);
        if (!ok) {
            r.executed = false;
            assembly { revert(add(result, 32), mload(result)) }
        }
        warning = false;
        emit RecoveryExecuted(id, msg.sender);
    }

    function _selector(bytes calldata data) internal pure returns (bytes4 sel) {
        if (data.length < 4) return bytes4(0);
        assembly { sel := calldataload(data.offset) }
    }

    uint256[40] private __gap;
}
