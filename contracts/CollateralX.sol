// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CollateralX {
  IERC20 public stablecoinInterface;

  uint public constant COLLATERAL_RATIO = 150;
  uint public constant LIQUIDATION_RATIO = 120;
  uint public constant LIQUIDATION_REWARD_RATE = 5;
  uint public constant INTEREST_RATE = 10;

  struct Loan {
    uint amount; //in stablecoin
    uint timestamp;
  }

  struct LoanAccount {
    uint collateral; //in ETH
    uint totalLoanAmount; //in stablecoin
    Loan[] loans;
  }

  mapping(address => LoanAccount) public loanAccounts;

  constructor(address _stablecoinContractAddress) {
    stablecoinInterface = IERC20(_stablecoinContractAddress);
  }
  
  function depositCollateral() external payable {
    require(msg.value > 0, "Deposit amount should be greater than zero.");
    LoanAccount storage loanAccount = loanAccounts[msg.sender];
    loanAccount.collateral += msg.value;
    
    emit CollateralDeposited(msg.sender, msg.value);
  }
  
  function borrow(uint amount) external {
    require(amount > 0, "Borrow amount should be greater than zero.");

    LoanAccount storage loanAccount = loanAccounts[msg.sender];
    require(loanAccount.collateral > 0, "Need to deposit collateral first.");

    uint collateral = convertEthToStablecoin(loanAccount.collateral);
    uint existingLoanAmount = loanAccount.totalLoanAmount;
    uint interest = calculateInterest(loanAccount.loans);

    require(((existingLoanAmount + interest + amount) * COLLATERAL_RATIO / 100) <= collateral, "Collateral is not enough.");

    loanAccount.totalLoanAmount += amount;
    loanAccount.loans.push(Loan({
      amount: amount,
      timestamp: block.timestamp
    }));
    require(stablecoinInterface.transfer(msg.sender, amount), "Stablecoin transfer failed.");

    emit Borrowed(msg.sender, amount);
  }

  function repay(uint[] memory indexes) external {
    require(indexes.length > 0, "Please specify at least one loan to repay.");

    LoanAccount storage loanAccount = loanAccounts[msg.sender];
    require(loanAccount.totalLoanAmount > 0, "You have no loans to repay.");

    uint repaymentAmount = 0;
    for (uint i = 0; i < indexes.length; i++) {
      Loan storage loan = loanAccount.loans[indexes[i]];
      repaymentAmount += loan.amount + calculateInterestForSingleLoan(loan);
      loanAccount.totalLoanAmount -= loan.amount;
      loan.amount = 0;
    }

    require(stablecoinInterface.transferFrom(msg.sender, address(this), repaymentAmount), "Repayment transfer failed.");

    emit Repaid(msg.sender, repaymentAmount, indexes);
  }

  function withdrawCollateral(uint amount) external {
    require(amount > 0, "Withdrawal amount should be greater than zero.");

    LoanAccount storage loanAccount = loanAccounts[msg.sender];
    require(loanAccount.collateral >= amount, "Withdrawal amount cannot exceed collateral amount.");
    
    uint collateralPostWithdrawal = convertEthToStablecoin(loanAccount.collateral - amount);
    uint interest = calculateInterest(loanAccount.loans);
    require((loanAccount.totalLoanAmount + interest) * COLLATERAL_RATIO / 100 <= collateralPostWithdrawal, "Collateral ratio will drop below minimum.");

    loanAccount.collateral -= amount;
    payable(msg.sender).transfer(amount);

    emit CollateralWithdrawn(msg.sender, amount);
  }
  
  function liquidate(address borrower) external {
    LoanAccount storage loanAccount = loanAccounts[borrower];
    require(loanAccount.collateral > 0, "Borrower has no collateral to liquidate.");

    uint collateral = convertEthToStablecoin(loanAccount.collateral);
    uint[] memory indexes = new uint[](loanAccount.loans.length);
    for (uint i = 0; i < loanAccount.loans.length; i++) {
      indexes[i] = i;
    }
    uint repaymentAmount = calculateRepaymentAmount(borrower, indexes);

    require(collateral < repaymentAmount * LIQUIDATION_RATIO / 100, "Borrower has enough collateral to remain healthy.");
    require(stablecoinInterface.transferFrom(msg.sender, address(this), repaymentAmount), "Liquidation repayment transfer failed.");

    uint settlementEthAmount = convertStablecoinToEth(repaymentAmount * (100 + LIQUIDATION_REWARD_RATE) / 100);
    if (settlementEthAmount > loanAccount.collateral) {
      settlementEthAmount = loanAccount.collateral;
    }
    payable(msg.sender).transfer(settlementEthAmount);

    loanAccount.collateral -= settlementEthAmount;
    loanAccount.totalLoanAmount = 0;
    delete loanAccount.loans;

    emit Liquidated(borrower, settlementEthAmount);
  }

  function convertEthToStablecoin(uint amount) internal pure returns (uint) {
    uint ethPriceInStablecoin = 2000;
    return amount * ethPriceInStablecoin;
  }

  function convertStablecoinToEth(uint amount) internal pure returns (uint) {
    uint ethPriceInStablecoin = 2000;
    return amount / ethPriceInStablecoin;
  }

  function calculateInterest(Loan[] storage loans) internal view returns (uint) {
    uint interest = 0;
    for (uint i = 0; i < loans.length; i++) {
      interest += calculateInterestForSingleLoan(loans[i]);
    }
    return interest;
  }

  function calculateInterestForSingleLoan(Loan storage loan) internal view returns (uint) {
    return loan.amount * INTEREST_RATE / 100 * (block.timestamp - loan.timestamp) / 365 days;
  }

  function calculateRepaymentAmount(address borrower, uint[] memory indexes) public view returns (uint) {
    LoanAccount storage loanAccount = loanAccounts[borrower];

    uint repaymentAmount = 0;
    for (uint i = 0; i < indexes.length; i++) {
      Loan storage loan = loanAccount.loans[indexes[i]];
      repaymentAmount += loan.amount + calculateInterestForSingleLoan(loan);
    }
    return repaymentAmount;
  }

  event CollateralDeposited(address user, uint amount);
  event Borrowed(address user, uint amount);
  event Repaid(address user, uint amount, uint[] indexes);
  event CollateralWithdrawn(address user, uint amount);
  event Liquidated(address borrower, uint reward);

}