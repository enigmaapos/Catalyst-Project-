const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("CatalystGovernance", function () {
  async function setup() {
    const [owner, proposer, voter, target, outsider] = await ethers.getSigners();
    const Gov = await ethers.getContractFactory("CatalystGovernance");
    const gov = await upgrades.deployProxy(Gov, [ethers.ZeroAddress, owner.address], { kind: "uups" });
    await gov.waitForDeployment();
    await gov.setStaking(target.address);
    return { owner, proposer, voter, target, outsider, gov };
  }
  it("requires configured staking and minimum proposal weight", async function () {
    const [owner, proposer, target] = await ethers.getSigners();
    const Gov = await ethers.getContractFactory("CatalystGovernance");
    const gov = await upgrades.deployProxy(Gov, [ethers.ZeroAddress, owner.address], { kind: "uups" });
    await gov.waitForDeployment();
    await expect(gov.connect(proposer).propose(target.address, "0x12345678", ethers.parseEther("1000"), ethers.parseEther("10000"))).to.be.reverted;
    await gov.setStaking(target.address);
    await expect(gov.connect(proposer).propose(target.address, "0x12345678", ethers.parseEther("999"), ethers.parseEther("10000"))).to.be.reverted;
  });
  it("creates proposals and prevents double voting", async function () {
    const { proposer, voter, target, gov } = await setup();
    await gov.connect(proposer).propose(target.address, "0x12345678", ethers.parseEther("1000"), ethers.parseEther("10000"));
    expect(await gov.proposalCount()).to.equal(1n);
    await gov.connect(voter).vote(1, 1, ethers.parseEther("1000"));
    await expect(gov.connect(voter).vote(1, 1, ethers.parseEther("1000"))).to.be.reverted;
  });
  it("rejects unauthorized changes to proposal threshold", async function () {
    const { outsider, gov } = await setup();
    await expect(gov.connect(outsider).setMinimumProposalWeight(1)).to.be.reverted;
  });
});
