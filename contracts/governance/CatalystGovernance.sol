// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CatalystUUPS} from "../common/CatalystUUPS.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @notice Minimal, explicit governance executor. Proposal payloads are committed at creation;
/// production rollout must complete BWCG historical-snapshot integration and parameter simulations.
contract CatalystGovernance is CatalystUUPS, ReentrancyGuardUpgradeable {
    uint64 public constant VOTING_PERIOD = 7 days;
    uint64 public constant EXECUTION_DELAY = 48 hours;
    uint64 public constant EXECUTION_WINDOW = 14 days;
    uint256 public constant QUORUM_BPS = 1000;
    uint256 public constant COLLECTION_VOTE_CAP_BPS = 2000;

    enum Status { NONE, ACTIVE, QUEUED, EXECUTED, CANCELLED, EXPIRED }
    struct Proposal {
        address proposer;
        address target;
        uint64 createdAt;
        uint64 votingEndsAt;
        uint64 executeAfter;
        uint64 expiresAt;
        uint256 snapshotEligibleSupply;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bytes32 callDataHash;
        Status status;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;
    address public staking;
    uint256 public minimumProposalWeight;

    error InvalidProposal();
    error VotingClosed();
    error AlreadyVoted();
    error NotExecutable();
    error NotAuthorized();

    event ProposalCreated(uint256 indexed id, address indexed proposer, address indexed target, bytes32 callDataHash, uint64 votingEndsAt);
    event VoteCast(uint256 indexed id, address indexed voter, uint8 support, uint256 weight);
    event ProposalQueued(uint256 indexed id, uint64 executeAfter, uint64 expiresAt);
    event ProposalExecuted(uint256 indexed id, address indexed executor);

    constructor() { _disableInitializers(); }

    function initialize(address staking_, address upgradeAuthority_) external initializer {
        // Zero is permitted only during staged deployment; setStaking must be called before use.
        __ReentrancyGuard_init();
        __CatalystUUPS_init(upgradeAuthority_);
        staking = staking_;
        minimumProposalWeight = 1000 ether;
    }

    function setStaking(address staking_) external onlyUpgradeAuthority {
        require(staking == address(0) && staking_ != address(0), "staking configured");
        staking = staking_;
    }

    /// @dev proposer supplies the snapshot weight; the production release must replace this with
    /// on-chain BWCG snapshot computation and verify it against staking/burn checkpoints.
    function propose(address target, bytes calldata callData, uint256 proposerSnapshotWeight, uint256 snapshotEligibleSupply) external returns (uint256 id) {
        if (staking == address(0) || target == address(0) || callData.length == 0 || proposerSnapshotWeight < minimumProposalWeight || snapshotEligibleSupply == 0) revert InvalidProposal();
        id = ++proposalCount;
        uint64 end = uint64(block.timestamp + VOTING_PERIOD);
        proposals[id] = Proposal(msg.sender, target, uint64(block.timestamp), end, 0, 0, snapshotEligibleSupply, 0, 0, 0, keccak256(callData), Status.ACTIVE);
        emit ProposalCreated(id, msg.sender, target, keccak256(callData), end);
    }

    function vote(uint256 id, uint8 support, uint256 snapshotWeight) external {
        Proposal storage p = proposals[id];
        if (p.status != Status.ACTIVE || block.timestamp >= p.votingEndsAt) revert VotingClosed();
        if (hasVoted[id][msg.sender] || support > 2 || snapshotWeight == 0) revert AlreadyVoted();
        hasVoted[id][msg.sender] = true;
        if (support == 0) p.againstVotes += snapshotWeight;
        else if (support == 1) p.forVotes += snapshotWeight;
        else p.abstainVotes += snapshotWeight;
        emit VoteCast(id, msg.sender, support, snapshotWeight);
    }

    function queue(uint256 id) external {
        Proposal storage p = proposals[id];
        if (p.status != Status.ACTIVE || block.timestamp < p.votingEndsAt) revert NotExecutable();
        uint256 participation = p.forVotes + p.againstVotes + p.abstainVotes;
        require(participation * 10_000 >= p.snapshotEligibleSupply * QUORUM_BPS, "quorum not met");
        require(p.forVotes > p.againstVotes, "majority not met");
        p.status = Status.QUEUED;
        p.executeAfter = uint64(block.timestamp + EXECUTION_DELAY);
        p.expiresAt = p.executeAfter + EXECUTION_WINDOW;
        emit ProposalQueued(id, p.executeAfter, p.expiresAt);
    }

    function execute(uint256 id, bytes calldata callData) external nonReentrant {
        Proposal storage p = proposals[id];
        if (p.status != Status.QUEUED || block.timestamp < p.executeAfter || block.timestamp > p.expiresAt) revert NotExecutable();
        if (keccak256(callData) != p.callDataHash) revert InvalidProposal();
        p.status = Status.EXECUTED;
        (bool ok, bytes memory result) = p.target.call(callData);
        if (!ok) {
            p.status = Status.QUEUED;
            assembly { revert(add(result, 32), mload(result)) }
        }
        emit ProposalExecuted(id, msg.sender);
    }

    function setMinimumProposalWeight(uint256 value) external {
        if (msg.sender != upgradeAuthority) revert NotAuthorized();
        require(value > 0, "zero weight");
        minimumProposalWeight = value;
    }

    uint256[40] private __gap;
}
