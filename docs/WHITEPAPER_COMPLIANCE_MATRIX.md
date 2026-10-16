# Whitepaper v1.1 → implementation compliance matrix

Status: **implementation build for testnet integration, not mainnet-ready and not audited**. Proposed values are not binding until approved by the project owner.

| Requirement | Current artifact | Status |
|---|---|---|
| CATA cap 1,000,000,000; initial mint 100,000,000 | `CATAToken.sol` | Implemented in code; tests required beyond included unit tests |
| Post-deployment mint only by staking | `CATAToken.sol` | Implemented after one-time staking configuration |
| Immutable 90/9/1 fee allocation | `CATAToken.sol`, `CatalystStaking.sol` | Token routing implemented; all paths require integration/conservation tests |
| Custodial term/permanent staking | `CatalystStaking.sol` | Implemented baseline; needs adversarial tests |
| Rolling 365-day reward cap | `CatalystStaking.sol` | Rolling UTC-day sum implemented; gas and boundary tests required |
| Blue-Chip non-custodial enrollment/harvest | — | **Missing** |
| Collection registration/tiering/escrow | `CollectionRegistry.sol` | Partial; registration fee/escrow settlement policy must be completed |
| Historical BWCG voting snapshots | `CatalystGovernance.sol` | **Not compliant**: caller-supplied weights/supply are not trustworthy |
| Governance quorum/majority/delay/execution | `CatalystGovernance.sol` | Basic lifecycle implemented; security and snapshot integration incomplete |
| Treasury payout safeguards | `CatalystTreasury.sol` | Basic cap implemented; proposal binding and cumulative budget rules need review |
| 5/7, 6/7 veto opportunity, 7/7 lock/standby | `BatchGuardianCouncil.sol` | Partial; warning/veto timing and operational recovery flows need adversarial review |
| Guardian reseed/lock clearing and standby acceptance | — | **Missing/incomplete** |
| Upgrade-safe proxy initialization | `CatalystUUPS.sol` and proxies | Baseline pattern included; production authority architecture incomplete |
| Complete user-facing dApp | `dapp/` | **Not compliant**: currently wallet connection/read balance shell |
| Complete staged deployment | `scripts/deploy.js` | Local/Amoy deployment and wiring; deliberately blocks Mainnet |
| Independent audit and release manifest | `docs/SECURITY_AND_DEPLOYMENT.md` | **Outstanding** |

No full compliance claim should be made until each gap is implemented, independently tested, and backed by evidence.
