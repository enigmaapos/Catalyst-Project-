const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("CATAToken", function () {
  async function deploy() {
    const [owner, allocation, treasury, maintainer] = await ethers.getSigners();
    const F = await ethers.getContractFactory("CATAToken");
    const token = await upgrades.deployProxy(F, [allocation.address, treasury.address, maintainer.address, owner.address], { kind: "uups" });
    await token.waitForDeployment();
    return { token, owner, allocation, treasury, maintainer };
  }

  it("mints exactly 100m CATA to initial allocation", async function () {
    const { token, allocation } = await deploy();
    expect(await token.balanceOf(allocation.address)).to.equal(ethers.parseEther("100000000"));
    expect(await token.totalSupply()).to.equal(ethers.parseEther("100000000"));
  });

  it("distributes fee with exact conservation and 90/9/1 target", async function () {
    const { token, allocation, treasury, maintainer } = await deploy();
    const fee = ethers.parseEther("100");
    await token.connect(allocation).approve(await token.getAddress(), fee);
    await token.connect(allocation).payFee(fee);
    expect(await token.balanceOf(treasury.address)).to.equal(ethers.parseEther("9"));
    expect(await token.balanceOf(maintainer.address)).to.equal(ethers.parseEther("1"));
    expect(await token.totalSupply()).to.equal(ethers.parseEther("99999900"));
  });

  it("rejects generic role management", async function () {
    const { token, owner } = await deploy();
    await expect(token.connect(owner).grantRole(ethers.ZeroHash, owner.address)).to.be.reverted;
  });
});
