// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

contract ExecutionTarget {
  error ExecutionFailed(uint256 newNumber);

  event TargetCalled(
    address indexed caller,
    uint256 callValue,
    uint256 newNumber
  );

  bytes32 public constant RETURN_VALUE = keccak256('execution result');
  address public caller;
  uint256 public callValue;
  uint256 public number;

  function succeed(uint256 newNumber)
    external
    payable
    returns (bytes32)
  {
    caller = msg.sender;
    callValue = msg.value;
    number = newNumber;

    emit TargetCalled(msg.sender, msg.value, newNumber);
    return RETURN_VALUE;
  }

  function fail(uint256 newNumber) external {
    number = newNumber;

    revert ExecutionFailed(newNumber);
  }
}
