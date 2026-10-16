const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("BatchGuardianCouncil", function () {
  async function setup() {
    const signers = await ethers.getSigners();
    const [owner, ...rest] = signers;
    const active = rest.slice(0, 7).map(s => s.address);
    const standby = rest.slice(7, 14).map(s => s.address);
    const Council = await ethers.getContractFactory("BatchGuardianCouncil");
    const council = await upgrades.deployProxy(Council, [owner.address, active[0]], { kind: "uups" });
    await council.waitForDeployment();
    await council.seedBatches(active, standby);
    const Target = await ethers.getContractFactory("MockCollection");
    const target = await Target.deploy(); await target.waitForDeployment();
    const selector = target.interface.getFunction("mint").selector;
    await council.setAllowedSelector(await target.getAddress(), selector, true);
    return { owner, rest, active, standby, council, target, selector };
  }
  it("seeds distinct active and standby guardian batches", async function () {
    const { council, active, standby } = await setup();
    expect(await council.active(0)).to.equal(active[0]);
    expect(await council.standby(0)).to.equal(standby[0]);
  });
  it("requires an active guardian and allowlisted selector to propose recovery", async function () {
    const { rest, active, council, target } = await setup();
    const data = target.interface.encodeFunctionData("mint", [rest[15].address, 1]);
    await expect(council.connect(rest[15]).proposeRecovery(await target.getAddress(), data, 1)).to.be.reverted;
    await expect(council.connect(rest[0]).proposeRecovery(await target.getAddress(), "0x12345678", 1)).to.be.reverted;
    await council.connect(rest[0]).proposeRecovery(await target.getAddress(), data, 1);
    expect(await council.nextRecoveryId()).to.equal(2n);
  });
});
