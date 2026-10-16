const { ethers, upgrades } = require("hardhat");

const contracts = [
  ["CollectionRegistry", "contracts/registry/CollectionRegistry.sol:CollectionRegistry"],
  ["CatalystGovernance", "contracts/governance/CatalystGovernance.sol:CatalystGovernance"],
  ["BatchGuardianCouncil", "contracts/recovery/BatchGuardianCouncil.sol:BatchGuardianCouncil"],
];

async function main() {
  let failed = false;

  for (const [name, fullyQualifiedName] of contracts) {
    console.log(`\nChecking ${name}...`);

    try {
      const Factory = await ethers.getContractFactory(fullyQualifiedName);

      await upgrades.validateImplementation(Factory, {
        kind: "uups",
      });

      console.log(`PASS: ${name} implementation validation`);
    } catch (error) {
      failed = true;
      console.error(`FAIL: ${name}`);
      console.error(error.message.split("\n").slice(0, 8).join("\n"));
    }
  }

  if (failed) {
    process.exitCode = 1;
  } else {
    console.log("\nAll three implementations passed validation.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
