# Catalyst v1.1 — Polygon implementation build

This repository is the working Solidity/Hardhat implementation derived from the **Catalyst Whitepaper Mainnet Readiness Revision v1.1 (Proposed Specification)**. It is not a starter template, but it is also **not certified mainnet-ready**: the whitepaper itself identifies proposed parameters that require owner approval, and several protocol requirements still need implementation/review before production.

## Included
- Upgradeable CATA ERC-20 with 1,000,000,000 CATA hard cap, 100,000,000 initial allocation, staking-only rewards after one-time wiring, and fixed 90/9/1 fee routing.
- Custodial term/permanent NFT staking with bounded batch harvests and a rolling 365-day emission calculation.
- Collection registry with tiering, escrow tracking, stake counters, and governance-controlled changes.
- Proposal/vote/queue/execute governance contract.
- Treasury payout guardrails.
- Two-batch guardian council with 5/7 recovery threshold, 6/7 warning/veto window, 7/7 lock/standby activation, and allowlisted recovery selectors.
- Browser dApp shell and configurable contract addresses.
- Staged local/Amoy deployment script and CATA unit tests.

## Important limitations — read before deployment
This implementation build must not be treated as a finished, audited protocol. In particular:
1. Governance still accepts caller-supplied voting weights and eligible-supply snapshots. This is not secure historical BWCG snapshot voting and must be replaced before public launch.
2. The Blue-Chip non-custodial enrollment/harvest path described by the whitepaper is not implemented in this build.
3. Guardian reseeding/lock-clearing operational flows and deterministic last-honest eligibility require completion and adversarial testing.
4. Collection registration currently records escrow and fees in the registry; the complete fee settlement/refund policy needs implementation and tests.
5. Upgrade authority in the deployment script is the deployer, solely for local/Amoy integration testing. It is not an acceptable production governance/recovery arrangement.
6. The browser dApp is a connected-wallet/read-balance shell, not the complete user-facing application for all protocol functions.
7. Proposed economics must be approved and documented; unit, integration, fuzz, invariant, and adversarial tests plus an independent security audit are required.

The deployment script deliberately refuses Polygon Mainnet. Do not remove that guard to deploy this build with real assets.

## Requirements
- Node.js 20+
- npm
- A Polygon Amoy RPC endpoint
- A dedicated test wallet with test POL
- Fourteen unique test guardian addresses (7 active + 7 standby)

## Local setup
```bash
cp .env.example .env
npm install
npm run compile
npm test
```

## Amoy setup
Fill `.env` with:
- `PRIVATE_KEY` — dedicated test-only deployer key
- `POLYGON_AMOY_RPC_URL`
- `TREASURY_ADDRESS` — address receiving the immutable 9% CATA fee share (must be reviewed; it is not automatically the Treasury contract proxy)
- `MAINTAINER_ADDRESS`
- `LAST_HONEST_GUARDIAN` — one of the active guardian addresses
- `ACTIVE_GUARDIANS` — seven comma-separated unique addresses
- `STANDBY_GUARDIANS` — seven comma-separated unique addresses, all distinct from active addresses
- optional `INITIAL_ALLOCATION_ADDRESS`
- optional `REWARD_RATE_PER_NFT_PER_DAY` (integer in wei; default is 1 CATA per NFT per day)

Then run:
```bash
npm run deploy:amoy
```
The script writes `deployments/80002.json`. Verify all deployed addresses and transactions independently before configuring the dApp.

## Realme Pad 2
Use a browser-based cloud development environment such as GitHub Codespaces, upload this project, open its terminal, and follow the commands above. Do not enter a seed phrase into the development environment. Never commit `.env`.

## Network IDs
- Polygon Amoy: `80002`
- Polygon PoS Mainnet: `137`

**Release policy:** deployment is not the same as readiness. Mainnet stays blocked until every whitepaper requirement has a passing test/evidence entry, proposed values are approved, and an independent security review is completed.
