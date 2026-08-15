// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

interface IHardhatVm {
  function stopPrank() external;
  function expectRevert() external;
  function prank(address msgSender) external;
  function warp(uint256 newTimestamp) external;
  function startPrank(address msgSender) external;
  function expectRevert(bytes4 revertData) external;
  function expectRevert(bytes calldata revertData) external;
  function addr(uint256 privateKey) external pure returns (address);
  function label(address account, string calldata newLabel) external;

  function expectEmit(
    bool checkTopic1,
    bool checkTopic2,
    bool checkTopic3,
    bool checkData,
    address emitter
  ) external;

  function assertEq(uint256 left, uint256 right) external pure;
  function assertEq(bool left, bool right) external pure;
  function assertEq(address left, address right) external pure;
  function assertEq(bytes32 left, bytes32 right) external pure;
  function assertEq(string calldata left, string calldata right ) external pure;
}

abstract contract HardhatTest {
  IHardhatVm internal constant vm = IHardhatVm(
    address(uint160(uint256(keccak256('hevm cheat code'))))
  );

  function makeAddr(
    string memory name
  ) internal returns (address account) {
    account = vm.addr(uint256(keccak256(abi.encodePacked(name))));

    vm.label(account, name);
  }

  function assertEq(uint256 left, uint256 right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(bool left, bool right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(address left, address right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(bytes32 left, bytes32 right) internal pure {
    vm.assertEq(left, right);
  }

  function assertEq(
    string memory left,
    string memory right
  ) internal pure {
    vm.assertEq(left, right);
  }
}
