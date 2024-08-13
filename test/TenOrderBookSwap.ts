import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("TenOrderBookSwap", function () {
  async function deployTenOrderBookSwapFixture() {
    const [owner, user1, user2, user3, user4, user5] =
      await hre.ethers.getSigners();

    const TokenA = await hre.ethers.getContractFactory("CustomERC20");
    const tokenA = await TokenA.deploy("Token A", "TKA");

    const TokenB = await hre.ethers.getContractFactory("CustomERC20");
    const tokenB = await TokenB.deploy("Token B", "TKB");

    const TenOrderBookSwap = await hre.ethers.getContractFactory(
      "TenOrderBookSwap"
    );
    const tenOrderBookSwap = await TenOrderBookSwap.deploy(
      tokenA.target,
      tokenB.target
    );

    // Mint some tokens for testing
    await tokenA.mint(user1.address, hre.ethers.parseEther("1000"));
    await tokenB.mint(user2.address, hre.ethers.parseEther("1000"));
    await tokenA.mint(user3.address, hre.ethers.parseEther("1000"));
    await tokenB.mint(user4.address, hre.ethers.parseEther("1000"));
    await tokenA.mint(user5.address, hre.ethers.parseEther("1000"));

    return {
      tenOrderBookSwap,
      tokenA,
      tokenB,
      owner,
      user1,
      user2,
      user3,
      user4,
      user5,
    };
  }

  describe("Deployment", function () {
    it("Should set the right token addresses", async function () {
      const { tenOrderBookSwap, tokenA, tokenB } = await loadFixture(
        deployTenOrderBookSwapFixture
      );

      expect(await tenOrderBookSwap.tokenA()).to.equal(tokenA.target);
      expect(await tenOrderBookSwap.tokenB()).to.equal(tokenB.target);
    });
  });

  describe("Swap Requests", function () {
    it("Should allow users to submit swap requests", async function () {
      const { tenOrderBookSwap, tokenA, user1 } = await loadFixture(
        deployTenOrderBookSwapFixture
      );

      const amountIn = hre.ethers.parseEther("100");
      const amountOut = hre.ethers.parseEther("90");

      await tokenA.connect(user1).approve(tenOrderBookSwap.target, amountIn);

      await expect(
        tenOrderBookSwap
          .connect(user1)
          .submitSwapRequest(amountIn, amountOut, true)
      ).to.not.be.reverted;

      expect(await tenOrderBookSwap.getPendingOrdersCount(true)).to.equal(1);
    });

    it("Should revert if amount in is zero", async function () {
      const { tenOrderBookSwap, user1 } = await loadFixture(
        deployTenOrderBookSwapFixture
      );

      await expect(
        tenOrderBookSwap
          .connect(user1)
          .submitSwapRequest(0, hre.ethers.parseEther("90"), true)
      ).to.be.revertedWith("Amount in must be greater than 0");
    });

    it("Should revert if amount out is zero", async function () {
      const { tenOrderBookSwap, user1 } = await loadFixture(
        deployTenOrderBookSwapFixture
      );

      await expect(
        tenOrderBookSwap
          .connect(user1)
          .submitSwapRequest(hre.ethers.parseEther("100"), 0, true)
      ).to.be.revertedWith("Amount out must be greater than 0");
    });
  });

  describe("Token Transfers", function () {
    it("Should transfer tokens correctly when orders are matched", async function () {
      const { tenOrderBookSwap, tokenA, tokenB, user1, user2 } =
        await loadFixture(deployTenOrderBookSwapFixture);

      const amountIn1 = hre.ethers.parseEther("100");
      const amountOut1 = hre.ethers.parseEther("90");
      const amountIn2 = hre.ethers.parseEther("90");
      const amountOut2 = hre.ethers.parseEther("100");

      await tokenA.connect(user1).approve(tenOrderBookSwap.target, amountIn1);
      await tokenB.connect(user2).approve(tenOrderBookSwap.target, amountIn2);

      await tenOrderBookSwap
        .connect(user1)
        .submitSwapRequest(amountIn1, amountOut1, true);
      await expect(
        await tenOrderBookSwap
          .connect(user2)
          .submitSwapRequest(amountIn2, amountOut2, false)
      )
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user2.address, amountIn2, amountOut2, false)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user1.address, amountIn1, amountOut1, true);

      // All amounts should be swapped
      expect(await tokenB.balanceOf(user1.address)).to.equal(amountOut1);
      expect(await tokenA.balanceOf(user2.address)).to.equal(amountIn1);

      expect(await tenOrderBookSwap.getPendingOrdersCount(true)).to.equal(0);
      expect(await tenOrderBookSwap.getPendingOrdersCount(false)).to.equal(0);
    });
  });

  describe("Order Matching Scenarios", function () {
    it("Should match orders and emit events", async function () {
      const { tenOrderBookSwap, tokenA, tokenB, user1, user2 } =
        await loadFixture(deployTenOrderBookSwapFixture);

      const amountIn1 = hre.ethers.parseEther("100");
      const amountOut1 = hre.ethers.parseEther("90");
      const amountIn2 = hre.ethers.parseEther("90");
      const amountOut2 = hre.ethers.parseEther("100");

      await tokenA.connect(user1).approve(tenOrderBookSwap.target, amountIn1);
      await tokenB.connect(user2).approve(tenOrderBookSwap.target, amountIn2);

      await tenOrderBookSwap
        .connect(user1)
        .submitSwapRequest(amountIn1, amountOut1, true);

      await expect(
        tenOrderBookSwap
          .connect(user2)
          .submitSwapRequest(amountIn2, amountOut2, false)
      )
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user2.address, amountIn2, amountOut2, false)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user1.address, amountIn1, amountOut1, true);

      expect(await tenOrderBookSwap.getPendingOrdersCount(true)).to.equal(0);
      expect(await tenOrderBookSwap.getPendingOrdersCount(false)).to.equal(0);
    });

    it("Should not interact with existing orders if incoming order cannot match", async function () {
      const { tenOrderBookSwap, tokenA, tokenB, user1, user2 } =
        await loadFixture(deployTenOrderBookSwapFixture);

      const amountIn1 = hre.ethers.parseEther("100");
      const amountOut1 = hre.ethers.parseEther("90");
      const amountIn2 = hre.ethers.parseEther("80"); // Less than amountOut1
      const amountOut2 = hre.ethers.parseEther("100");

      await tokenA.connect(user1).approve(tenOrderBookSwap.target, amountIn1);
      await tokenB.connect(user2).approve(tenOrderBookSwap.target, amountIn2);

      await tenOrderBookSwap
        .connect(user1)
        .submitSwapRequest(amountIn1, amountOut1, true);
      await tenOrderBookSwap
        .connect(user2)
        .submitSwapRequest(amountIn2, amountOut2, false);

      expect(await tenOrderBookSwap.getPendingOrdersCount(true)).to.equal(1);
      expect(await tenOrderBookSwap.getPendingOrdersCount(false)).to.equal(1);

      // Check that token balances haven't changed
      expect(await tokenA.balanceOf(user2.address)).to.equal(0);
      expect(await tokenB.balanceOf(user1.address)).to.equal(0);
    });

    it("Should fulfill multiple existing orders with one incoming order", async function () {
      const {
        tenOrderBookSwap,
        tokenA,
        tokenB,
        user1,
        user2,
        user3,
        user4,
        user5,
      } = await loadFixture(deployTenOrderBookSwapFixture);

      // Setup multiple small orders (A to B)
      const smallOrderAmount = hre.ethers.parseEther("0.1");
      const smallOrderOutAmount = hre.ethers.parseEther("300");

      await tokenA
        .connect(user2)
        .approve(tenOrderBookSwap.target, smallOrderAmount);
      await tokenA
        .connect(user3)
        .approve(tenOrderBookSwap.target, smallOrderAmount);
      await tokenA
        .connect(user4)
        .approve(tenOrderBookSwap.target, smallOrderAmount);

      await tenOrderBookSwap
        .connect(user2)
        .submitSwapRequest(smallOrderAmount, smallOrderOutAmount, true);
      await tenOrderBookSwap
        .connect(user3)
        .submitSwapRequest(smallOrderAmount, smallOrderOutAmount, true);
      await tenOrderBookSwap
        .connect(user4)
        .submitSwapRequest(smallOrderAmount, smallOrderOutAmount, true);

      // Large incoming order (B to A)
      const largeOrderAmount = hre.ethers.parseEther("1000");
      const largeOrderOutAmount = hre.ethers.parseEther("0.3");

      await tokenB
        .connect(user5)
        .approve(tenOrderBookSwap.target, largeOrderAmount);

      // This should match all three existing orders
      await expect(
        tenOrderBookSwap
          .connect(user5)
          .submitSwapRequest(largeOrderAmount, largeOrderOutAmount, false)
      )
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user2.address, smallOrderAmount, smallOrderOutAmount, true)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user5.address, smallOrderOutAmount, smallOrderAmount, false)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user3.address, smallOrderAmount, smallOrderOutAmount, true)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user5.address, smallOrderOutAmount, smallOrderAmount, false)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user4.address, smallOrderAmount, smallOrderOutAmount, true)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user5.address, smallOrderOutAmount, smallOrderAmount, false);

      // Check that all small orders were fulfilled
      expect(await tenOrderBookSwap.getPendingOrdersCount(true)).to.equal(0);

      // Check that the remaining large order is in the queue
      expect(await tenOrderBookSwap.getPendingOrdersCount(false)).to.equal(1);

      // Check token transfers
      expect(await tokenA.balanceOf(user5.address)).to.equal(
        hre.ethers.parseEther("0.3")
      );
      expect(await tokenB.balanceOf(user2.address)).to.equal(
        smallOrderOutAmount
      );
      expect(await tokenB.balanceOf(user3.address)).to.equal(
        smallOrderOutAmount
      );
      expect(await tokenB.balanceOf(user4.address)).to.equal(
        smallOrderOutAmount
      );
    });

    it("Should partially fulfill an incoming order and leave the remainder in the queue", async function () {
      const { tenOrderBookSwap, tokenA, tokenB, user1, user2 } =
        await loadFixture(deployTenOrderBookSwapFixture);

      // Setup a small order (A to B)
      const smallOrderAmount = hre.ethers.parseEther("0.1");
      const smallOrderOutAmount = hre.ethers.parseEther("300");

      await tokenA
        .connect(user1)
        .approve(tenOrderBookSwap.target, smallOrderAmount);
      await tenOrderBookSwap
        .connect(user1)
        .submitSwapRequest(smallOrderAmount, smallOrderOutAmount, true);

      // Large incoming order (B to A)
      const largeOrderAmount = hre.ethers.parseEther("1000");
      const largeOrderOutAmount = hre.ethers.parseEther("0.3");

      await tokenB
        .connect(user2)
        .approve(tenOrderBookSwap.target, largeOrderAmount);

      // This should match the existing small order and leave the remainder in the queue
      await expect(
        tenOrderBookSwap
          .connect(user2)
          .submitSwapRequest(largeOrderAmount, largeOrderOutAmount, false)
      )
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user2.address, smallOrderOutAmount, smallOrderAmount, false)
        .to.emit(tenOrderBookSwap, "OrderFulfilled")
        .withArgs(user1.address, smallOrderAmount, smallOrderOutAmount, true);

      // Check that the remainder is in the queue
      expect(await tenOrderBookSwap.getPendingOrdersCount(false)).to.equal(1);

      // Check token transfers
      expect(await tokenA.balanceOf(user2.address)).to.equal(smallOrderAmount);
      expect(await tokenB.balanceOf(user1.address)).to.equal(
        smallOrderOutAmount
      );
    });
  });
});
