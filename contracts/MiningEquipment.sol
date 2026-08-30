// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/**
 * @notice Provides an internal primitive for making arbitrary external calls
 * from a derived contract.
 *
 * @dev This contract does not implement access control. A derived contract
 * exposing `_execute` through an external function must apply appropriate
 * authorization and target restrictions.
 *
 * Arbitrary calls give the authorized caller full control over assets held by
 * the derived contract.
 */
abstract contract MiningEquipment {
  error CallFailed(bytes reason);

  /**
   * @notice The event stores and indexes only the target address. Read the
   * forwarded value and input data from the `execute` call or its transaction
   * trace.
   */
  event Executed(address indexed target);

  /**
   * @dev Allows the contract to receive native currency. Some DeFi protocols
   * may require native currency instead of its wrapped token.
   */
  receive() external payable {}

  function _execute(
    address target,
    uint256 value,
    bytes calldata data
  ) internal returns (bytes memory result) {
    bool success;

    (success, result) = target.call{value: value}(data);

    if (!success) {
      revert CallFailed(result);
    }

    emit Executed(target);

    return result;
  }
}
