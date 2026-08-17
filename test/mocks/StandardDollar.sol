// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract StandardDollar is ERC20 {
  uint8 private immutable _tokenDecimals;

  constructor(
    string memory name,
    string memory symbol,
    uint8 tokenDecimals
  ) ERC20(name, symbol) {
    _tokenDecimals = tokenDecimals;
  }

  function decimals() public view override returns (uint8) {
    return _tokenDecimals;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}
