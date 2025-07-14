const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("CollateralX", function () {
  let collateralX, stablecoin;  
  let deployer, user;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();
    
    const stablecoinFactory = await ethers.getContractFactory("MockCoin");
    stablecoin = await stablecoinFactory.deploy();

    const collateralXFactory = await ethers.getContractFactory("CollateralX");
    collateralX = await collateralXFactory.deploy(stablecoin.getAddress());

    await stablecoin.faucet(collateralX.getAddress(), ethers.parseEther("1000"));
  });

  it("should allow a user to deposit collateral", async function () {
    const depositAmount = ethers.parseEther("1");
    await collateralX.connect(user).depositCollateral({value: depositAmount});
    const loanAccount = await collateralX.loanAccounts(user.getAddress());
    expect(loanAccount.collateral).to.equal(depositAmount);
  });

  it("should allow a user to borrow stablecoin if sufficient collateral is present", async function () {
    const depositAmount = ethers.parseEther("1");
    await collateralX.connect(user).depositCollateral({value: depositAmount});

    const borrowAmount = ethers.parseEther("100");
    await collateralX.connect(user).borrow(borrowAmount);
    const loanAccount = await collateralX.loanAccounts(user.getAddress());
    expect(loanAccount.totalLoanAmount).to.equal(borrowAmount);
    expect(await stablecoin.balanceOf(user.getAddress())).to.equal(borrowAmount);
  });

  it("should not allow a user to borrow stablecoin if sufficient collateral is not present", async function () {
    const depositAmount = ethers.parseEther("1");
    await collateralX.connect(user).depositCollateral({value: depositAmount});

    const borrowAmount = ethers.parseEther("10000");
    await expect(collateralX.connect(user).borrow(borrowAmount)).to.be.revertedWith("Collateral is not enough.");
  });

  it("should allow a user to repay a loan with interest after 1 year", async function () {
    const depositAmount = ethers.parseEther("1");
    await collateralX.connect(user).depositCollateral({value: depositAmount});

    const borrowAmount = ethers.parseEther("100");
    await collateralX.connect(user).borrow(borrowAmount);
    await stablecoin.faucet(user.getAddress(), ethers.parseEther("20"));

    await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine");

    const repayAmount = await collateralX.calculateRepaymentAmount(user.getAddress(), [0]);
    const delta = ethers.parseEther("1");
    await stablecoin.connect(user).approve(collateralX.getAddress(), repayAmount + delta);

    await collateralX.connect(user).repay([0]);

    const loanAccount = await collateralX.loanAccounts(user.getAddress());
    expect(loanAccount.totalLoanAmount).to.equal(0);
    expect(await stablecoin.balanceOf(user.getAddress())).to.lessThanOrEqual(ethers.parseEther("10"));
  });

  it("should allow a user to withdraw collateral", async function () {
    const depositAmount = ethers.parseEther("1");
    await collateralX.connect(user).depositCollateral({value: depositAmount});

    const withdrawAmount = ethers.parseEther("0.5");
    await collateralX.connect(user).withdrawCollateral(withdrawAmount);

    const loanAccount = await collateralX.loanAccounts(user.getAddress());
    expect(loanAccount.collateral).to.equal(depositAmount - withdrawAmount);
  });
});