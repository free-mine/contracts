// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';

/**
 * @notice ERC-20 token that represents Magic Ore in the Free Mine.
 * @dev The token owner can mint tokens to any account or burn them from any
 * account. It can also call `lock` to move tokens from any account to itself
 * without an allowance. FreeMine is expected to own this token and uses these
 * powers for purchases, claims, and sacrifices.
 */
contract MagicOre is ERC20Permit, Ownable {
  constructor(string memory name, string memory symbol)
  ERC20(name, symbol) ERC20Permit(name) Ownable(msg.sender) {}

  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external onlyOwner {
    _burn(from, amount);
  }

  function lock(address from, uint256 amount) external onlyOwner {
    _transfer(from, owner(), amount);
  }
}
