// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';

contract Token is ERC20Permit, Ownable {
  constructor(string memory name, string memory symbol)
  ERC20(name, symbol) ERC20Permit(name) Ownable(msg.sender) {}

  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external onlyOwner {
    _burn(from, amount);
  }

  function take(address from, uint256 amount) external onlyOwner {
    _transfer(from, owner(), amount);
  }
}
