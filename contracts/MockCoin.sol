// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockCoin is ERC20 {
  constructor() ERC20("Mock Coin", "mCoin") {
    _mint(msg.sender, 1_000_000 * 10**18);
  }

  function faucet(address to, uint amount) external {
    _mint(to, amount);
  }
}