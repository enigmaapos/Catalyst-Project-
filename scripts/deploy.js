const { ethers, upgrades } = require("hardhat");
require("dotenv").config();

const required = (name) => {
  const value = process.env[name];
  if (!value || value.trim() === "") throw new Error(`Missing ${name} in .env`);
  if (!ethers.isAddress(value)) throw new Error(`${name} must be an EVM address`);
  return value;
};

async function deployProxy(name, args) {
  const Factory = await ethers.getContractFactory(name);
  const instance = await upgrades.deployProxy(Factory, args, { kind: "uups", initializer: "initialize" });
  await instance.waitForDeployment();
  console.log(`${name}: ${await instance.getAddress()}`);
  return instance;
}

async function main() {
  const network = await ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  if (![31337, 80002].includes(chainId)) {
    if (chainId !== 137 || process.env.ALLOW_MAINNET_DEPLOYMENT !== "I_HAVE_REVIEWED_THE_RELEASE_GATES") {
      throw new Error("Deployment blocked. Use local/Amoy first. Mainnet requires ALLOW_MAINNET_DEPLOYMENT=I_HAVE_REVIEWED_THE_RELEASE_GATES after approved tests, reviewed parameters, and independent audit.");
    }
    throw new Error("Mainnet deployment intentionally remains blocked by release policy until an audited, governance-controlled upgrade architecture is configured. Do not bypass this guard.");
  }

  const [deployer] = await ethers.getSigners();
  const allocation = process.env.INITIAL_ALLOCATION_ADDRESS || deployer.address;
  const feeTreasury = required("TREASURY_ADDRESS");
  const maintainer = process.env.MAINTAINER_ADDRESS || deployer.address;
  const lastHonestGuardian = required("LAST_HONEST_GUARDIAN");
  const active = (process.env.ACTIVE_GUARDIANS || "").split(",").map(x => x.trim()).filter(Boolean);
  const standby = (process.env.STANDBY_GUARDIANS || "").split(",").map(x => x.trim()).filter(Boolean);
  if (active.length !== 7 || standby.length !== 7) throw new Error("ACTIVE_GUARDIANS and STANDBY_GUARDIANS must each contain exactly seven comma-separated addresses.");
  for (const [name, list] of [["ACTIVE_GUARDIANS", active], ["STANDBY_GUARDIANS", standby]]) {
    if (list.some(a => !ethers.isAddress(a)) || new Set(list.map(a => a.toLowerCase())).size !== 7) throw new Error(`${name} contains invalid or duplicate addresses.`);
  }
  if (new Set([...active, ...standby].map(a => a.toLowerCase())).size !== 14) throw new Error("Active and standby guardian addresses must be all distinct.");
  if (!active.some(a => a.toLowerCase() === lastHonestGuardian.toLowerCase())) throw new Error("LAST_HONEST_GUARDIAN must be one of the active guardians.");

  console.log(`Chain ID: ${chainId}; deployer: ${deployer.address}`);
  console.log("NOTE: This script is for local/Amoy integration testing. Upgrade authority is the deployer and must not be used as a production governance architecture.");

  // Staged deployment resolves circular references using one-time setters.
  const token = await deployProxy("CATAToken", [allocation, feeTreasury, maintainer, deployer.address]);
  const governance = await deployProxy("CatalystGovernance", [ethers.ZeroAddress, deployer.address]);
  const registry = await deployProxy("CollectionRegistry", [await token.getAddress(), deployer.address, ethers.ZeroAddress]);
  const staking = await deployProxy("CatalystStaking", [
    await token.getAddress(), await registry.getAddress(), await governance.getAddress(),
    deployer.address, BigInt(process.env.REWARD_RATE_PER_NFT_PER_DAY || "1000000000000000000")
  ]);
  const treasury = await deployProxy("CatalystTreasury", [await token.getAddress(), await governance.getAddress(), deployer.address]);
  const council = await deployProxy("BatchGuardianCouncil", [deployer.address, lastHonestGuardian]);

  // Wire the contracts using one-time setters. Each receipt is awaited.
  await (await token.setStakingContract(await staking.getAddress())).wait();
  await (await registry.setStaking(await staking.getAddress())).wait();
  await (await registry.setGovernance(await governance.getAddress())).wait();
  await (await governance.setStaking(await staking.getAddress())).wait();
  await (await council.seedBatches(active, standby)).wait();

  const addresses = {
    chainId, deployer: deployer.address,
    cata: await token.getAddress(), governance: await governance.getAddress(),
    registry: await registry.getAddress(), staking: await staking.getAddress(),
    treasury: await treasury.getAddress(), council: await council.getAddress(),
    feeTreasury, maintainer, upgradeAuthority: deployer.address,
    deploymentStatus: "TESTNET_ONLY_NOT_AUDITED"
  };
  const fs = require("fs");
  fs.mkdirSync("deployments", { recursive: true });
  fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(addresses, null, 2));
  console.log("\nDeployment addresses saved to deployments/" + chainId + ".json");
  console.log("Do not use these contracts with real funds. Run integration tests and review every whitepaper compliance gate.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
