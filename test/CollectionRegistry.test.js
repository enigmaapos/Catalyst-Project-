const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("CollectionRegistry", function () {
  async function setup() {
    const [owner, allocation, treasury, maintainer, user, governance, outsider] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("CATAToken");
    const token = await upgrades.deployProxy(Token, [allocation.address, treasury.address, maintainer.address, owner.address], { kind: "uups" });
    await token.waitForDeployment();
    const Registry = await ethers.getContractFactory("CollectionRegistry");
    const registry = await upgrades.deployProxy(Registry, [await token.getAddress(), owner.address, governance.address], { kind: "uups" });
    await registry.waitForDeployment();
    const NFT = await ethers.getContractFactory("MockCollection");
    const nft = await NFT.deploy(); await nft.waitForDeployment();
    await token.connect(allocation).transfer(user.address, ethers.parseEther("1000"));
    await token.connect(user).approve(await registry.getAddress(), ethers.parseEther("1000"));
    return { owner, allocation, user, governance, outsider, token, registry, nft };
  }
  it("registers a collection as unverified and records escrow", async function () {
    const { user, token, registry, nft } = await setup();
    await registry.connect(user).registerCollection(await nft.getAddress(), false);
    const c = await registry.getCollection(await nft.getAddress());
    expect(c.tier).to.equal(1n);
    expect(c.escrowAmount).to.equal(ethers.parseEther("500"));
    expect(await registry.collectionCount()).to.equal(1n);
    expect(await token.balanceOf(await registry.getAddress())).to.equal(ethers.parseEther("600"));
  });
  it("rejects duplicate registration", async function () {
    const { user, registry, nft } = await setup();
    await registry.connect(user).registerCollection(await nft.getAddress(), false);
    await expect(registry.connect(user).registerCollection(await nft.getAddress(), false)).to.be.reverted;
  });
  it("rejects tier changes from unauthorized accounts", async function () {
    const { user, outsider, registry, nft } = await setup();
    await registry.connect(user).registerCollection(await nft.getAddress(), false);
    await expect(registry.connect(outsider).setTier(await nft.getAddress(), 2, ethers.ZeroHash)).to.be.reverted;
  });
  it("allows governance to change a registered collection tier", async function () {
    const { user, governance, registry, nft } = await setup();
    await registry.connect(user).registerCollection(await nft.getAddress(), false);
    await registry.connect(governance).setTier(await nft.getAddress(), 2, ethers.id("test-proposal"));
    expect((await registry.getCollection(await nft.getAddress())).tier).to.equal(2n);
  });
});
