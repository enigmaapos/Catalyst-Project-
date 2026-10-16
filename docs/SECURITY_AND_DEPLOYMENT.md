# Security and deployment release gates

## Current status
Implementation build for local/Polygon Amoy integration testing only. Not audited. Polygon Mainnet deployment is intentionally blocked by `scripts/deploy.js`.

## Before any public mainnet release
- Approve every v1.1 proposed default through a versioned decision.
- Replace caller-supplied governance weights/snapshots with verified historical, on-chain BWCG snapshots.
- Implement and test the Blue-Chip non-custodial path.
- Complete all guardian reseeding, veto, lock clearing, standby acceptance, expiry and replay-protection flows.
- Ensure all fee/escrow flows conserve funds and cannot be redirected by unauthorized callers.
- Move upgrade authorization to the approved governance/recovery architecture with a reviewed delay and code-hash/implementation publication.
- Complete unit, integration, fuzz, invariant, adversarial and gas tests.
- Review proxy storage layout and pinned dependency/compiler settings.
- Commission an independent smart-contract audit and remediate all findings.
- Publish verified source, release manifest, deployment transactions, role/authority map, monitoring and incident-response procedures.

## Deployment safety
The included deployment script uses the deployer as upgrade authority for testnet only. Do not use this authority arrangement on mainnet. The token's 9% fee recipient is the `TREASURY_ADDRESS` wallet configured at initialization; it is distinct from the `CatalystTreasury` proxy unless the approved architecture deliberately makes them the same.

Never paste a seed phrase into a website, IDE, terminal, repository, or chat. Keep `.env` out of Git. Use a dedicated test wallet on Amoy.
