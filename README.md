# Catalyst DApp

Static browser DApp for the uploaded Catalyst contracts:
- CatalystToken
- CatalystRegistry
- CatalystStaking
- CatalystGovernance
- CatalystTreasury
- CatalystGuardian

## Target network
Polygon Amoy testnet, chain ID 80002.

## Start
This is a static DApp. Because browser module imports may be blocked by `file://`, serve the folder with any static HTTP server.

Example:
`python3 -m http.server 8080`

Then open:
`http://localhost:8080`

## Configure
Open **Deployment** and paste the actual deployed contract addresses.

The DApp checks:
- configured chain ID
- contract bytecode at configured addresses
- wallet connection
- transaction lifecycle

It does not contain private keys or seed phrases.

## Important
The uploaded Solidity files are treated as the contract source for the ABI fragments used here. Before production/mainnet, regenerate exact release ABIs from the final compiled artifacts and update the DApp release manifest.

No contract address is invented in this package.
