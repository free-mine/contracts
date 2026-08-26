// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import './WithStaff.sol';

/**
 * @notice Lets the owner and active admins manage a derived contract's assets
 * by making any external call from that contract. They do not need to move the
 * assets to their own wallets first.
 *
 * This design requires full trust in the owner and every active admin. Each of
 * them has full control over the contract's assets. For example, they can make
 * the contract deposit assets into Aave or create trading pairs on Uniswap.
 * They can also send all assets to a personal address.
 */
abstract contract ManuallyOperated is WithStaff {
  error CallFailed(bytes reason);

  /**
   * @notice Only the target address is stored in the event and indexed. The
   * call value and input data can be found in the transaction that emitted it.
   */
  event Executed(address indexed target);

  /**
   * @dev Гипотетически возможны ситуации, когда DeFi-протокол сможет работать
   * только с чистым коином без обёртки. Лучше быть к этому готовым.
   */
  receive() external payable {}

  function execute(
    address target,
    uint256 value,
    bytes calldata data
  ) external staffOnly returns (bytes memory result) {
    bool success;

    (success, result) = target.call{value: value}(data);

    if (!success) {
      revert CallFailed(result);
    }

    emit Executed(target);

    return result;
  }
}
