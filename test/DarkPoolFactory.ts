import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("DarkPoolFactory", function () {
  it("Should create a DarkPool", async function () {
    const [owner] = await hre.ethers.getSigners();

    const TokenA = await hre.ethers.getContractFactory("CustomERC20");
    const tokenA = await TokenA.deploy("Token A", "TKA");

    const TokenB = await hre.ethers.getContractFactory("CustomERC20");
    const tokenB = await TokenB.deploy("Token B", "TKB");

    const DarkPoolFactory = await hre.ethers.getContractFactory(
      "DarkPoolFactory"
    );
    const darkPoolFactory = await DarkPoolFactory.deploy();

    const createResponse = await darkPoolFactory.createDarkPool(
      tokenA.target,
      tokenB.target
    );
    const userPools = await darkPoolFactory.getPools();

    expect(userPools.length).to.equal(1);
    await expect(createResponse)
      .to.emit(darkPoolFactory, "DarkPoolCreated")
      .withArgs(owner.address, userPools[0], tokenA.target, tokenB.target);
  });
});
