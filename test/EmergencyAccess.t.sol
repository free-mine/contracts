// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/access/Ownable.sol';

import '../contracts/DepositStore.sol';
import '../contracts/ManuallyOperated.sol';
import '../contracts/WithStaff.sol';
import './helpers/SystemFixture.sol';
import './mocks/ExecutionTarget.sol';
import './mocks/StandardDollar.sol';

contract EmergencyAccessTest is SystemFixture {
  function testOwnerSchedulesReschedulesAndPostponesClaim() public {
    uint256 firstClaimableAt = block.timestamp + 2 days;

    _scheduleWithEvent(owner, successor, 0, firstClaimableAt);
    assertEq(fund.successors(successor), firstClaimableAt);
    assertEq(fund.admins(successor), false);

    vm.warp(firstClaimableAt - 1);

    uint256 postponedClaimableAt = firstClaimableAt + 2 days;

    _scheduleWithEvent(
      owner,
      successor,
      firstClaimableAt,
      postponedClaimableAt
    );

    assertEq(fund.successors(successor), postponedClaimableAt);

    vm.warp(firstClaimableAt);
    vm.expectRevert(WithStaff.NotYet.selector);
    vm.prank(successor);
    fund.claimPrivileges();

    assertEq(fund.successors(successor), postponedClaimableAt);
    assertEq(fund.admins(successor), false);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
  }

  function testClaimAtExactBoundaryIsAtomicAndPreservesOwnership() public {
    _startOwnershipTransferWithEvent(newOwner);

    uint256 claimableAt = block.timestamp + 1 days;
    uint256 secondClaimableAt = claimableAt + 1 days;

    _scheduleWithEvent(owner, successor, 0, claimableAt);
    _scheduleWithEvent(owner, secondSuccessor, 0, secondClaimableAt);

    vm.warp(claimableAt - 1);
    vm.expectRevert(WithStaff.NotYet.selector);
    vm.prank(successor);
    fund.claimPrivileges();

    assertEq(fund.successors(successor), claimableAt);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);
    assertEq(fund.admins(successor), false);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);

    vm.warp(claimableAt);

    _claimWithEvent(successor, claimableAt);
    assertEq(fund.successors(successor), 0);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);
    assertEq(fund.admins(successor), true);
    assertEq(fund.admins(secondSuccessor), false);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);

    vm.expectRevert(WithStaff.SuccessorNotFound.selector);
    vm.prank(successor);
    fund.claimPrivileges();

    assertEq(fund.successors(successor), 0);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);
    assertEq(fund.admins(successor), true);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);
  }

  function testSuccessorSchedulesAreIndependent() public {
    uint256 firstClaimableAt = block.timestamp + 1 days;
    uint256 secondClaimableAt = firstClaimableAt + 1 days;

    _scheduleWithEvent(owner, successor, 0, firstClaimableAt);
    _scheduleWithEvent(owner, secondSuccessor, 0, secondClaimableAt);

    vm.warp(firstClaimableAt);

    _claimWithEvent(successor, firstClaimableAt);
    assertEq(fund.admins(successor), true);
    assertEq(fund.admins(secondSuccessor), false);
    assertEq(fund.successors(successor), 0);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);

    vm.warp(secondClaimableAt - 1);
    vm.expectRevert(WithStaff.NotYet.selector);
    vm.prank(secondSuccessor);
    fund.claimPrivileges();

    assertEq(fund.admins(successor), true);
    assertEq(fund.admins(secondSuccessor), false);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);

    vm.warp(secondClaimableAt);

    _claimWithEvent(secondSuccessor, secondClaimableAt);
    assertEq(fund.admins(successor), true);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.successors(successor), 0);
    assertEq(fund.successors(secondSuccessor), 0);
  }

  function testOwnerAndAdminCanRemoveSchedules() public {
    _activateAdmin(successor);

    uint256 ownerRemovedAt = block.timestamp + 1 days;

    _scheduleWithEvent(owner, secondSuccessor, 0, ownerRemovedAt);
    _removeScheduleWithEvent(owner, secondSuccessor, ownerRemovedAt);
    assertEq(fund.successors(secondSuccessor), 0);

    vm.expectRevert(WithStaff.SuccessorNotFound.selector);
    vm.prank(secondSuccessor);
    fund.claimPrivileges();

    assertEq(fund.successors(secondSuccessor), 0);
    assertEq(fund.admins(secondSuccessor), false);

    uint256 adminRemovedAt = block.timestamp + 2 days;

    _scheduleWithEvent(owner, newOwner, 0, adminRemovedAt);
    _removeScheduleWithEvent(successor, newOwner, adminRemovedAt);
    assertEq(fund.successors(newOwner), 0);

    vm.expectRevert(WithStaff.SuccessorNotFound.selector);
    vm.prank(newOwner);
    fund.claimPrivileges();

    assertEq(fund.successors(newOwner), 0);
    assertEq(fund.admins(newOwner), false);
    assertEq(fund.admins(successor), true);
    assertEq(fund.owner(), owner);
  }

  function testRemovingMissingScheduleIsAtomic() public {
    uint256 claimableAt = block.timestamp + 1 days;

    _scheduleWithEvent(owner, successor, 0, claimableAt);

    vm.expectRevert(WithStaff.SuccessorNotFound.selector);
    vm.prank(owner);
    fund.removeSuccessor(secondSuccessor);

    assertEq(fund.successors(successor), claimableAt);
    assertEq(fund.successors(secondSuccessor), 0);
    assertEq(fund.admins(successor), false);
    assertEq(fund.admins(secondSuccessor), false);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
  }

  function testStrangerCannotManageSuccessors() public {
    uint256 claimableAt = block.timestamp + 1 days;

    _scheduleWithEvent(owner, successor, 0, claimableAt);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(stranger);
    fund.scheduleSuccessor(successor, claimableAt + 1 days);

    assertEq(fund.successors(successor), claimableAt);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(stranger);
    fund.removeSuccessor(successor);

    assertEq(fund.successors(successor), claimableAt);
    assertEq(fund.admins(stranger), false);
    assertEq(fund.owner(), owner);
  }

  function testScheduleRejectsZeroTimestampAndStaffAddresses() public {
    uint256 claimableAt = block.timestamp + 1 days;

    vm.expectRevert(WithStaff.InvalidTimestamp.selector);
    vm.prank(owner);
    fund.scheduleSuccessor(secondSuccessor, 0);

    assertEq(fund.successors(secondSuccessor), 0);

    vm.expectRevert(WithStaff.AlreadyStaff.selector);
    vm.prank(owner);
    fund.scheduleSuccessor(owner, claimableAt);

    assertEq(fund.successors(owner), 0);
    _activateAdmin(successor);

    vm.expectRevert(WithStaff.AlreadyStaff.selector);
    vm.prank(owner);
    fund.scheduleSuccessor(successor, block.timestamp + 1 days);

    assertEq(fund.successors(successor), 0);
    assertEq(fund.admins(successor), true);
    assertEq(fund.owner(), owner);
  }

  function testAdminCanScheduleImmediateSuccessor() public {
    _activateAdmin(successor);

    uint256 claimableAt = block.timestamp;

    _scheduleWithEvent(successor, secondSuccessor, 0, claimableAt);
    assertEq(fund.successors(secondSuccessor), claimableAt);
    assertEq(fund.admins(secondSuccessor), false);
    _claimWithEvent(secondSuccessor, claimableAt);
    assertEq(fund.successors(secondSuccessor), 0);
    assertEq(fund.admins(successor), true);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.owner(), owner);
  }

  function testActivatedAdminCanUseEveryStaffEntryPoint() public {
    _activateAdmin(successor);
    _assertAdminCanExecute(successor);
    _assertAdminCanSetContractUri(successor);
    _assertAdminCanCompleteStage(successor);
    _assertAdminCanChangeEntryPrice(successor);
    _assertAdminCanChangeDollar(successor);

    assertEq(gate.currentStageId(), 2);
    assertEq(fund.admins(successor), true);
    assertEq(fund.owner(), owner);
  }

  function testOwnerRemovalRevokesAdminAccess() public {
    _activateAdmin(successor);

    vm.expectEmit(true, false, false, false, address(fund));

    emit AdminRemoved(successor);

    vm.prank(owner);
    fund.removeAdmin(successor);

    assertEq(fund.admins(successor), false);

    vm.expectRevert(WithStaff.AdminNotFound.selector);
    vm.prank(owner);
    fund.removeAdmin(successor);

    assertEq(fund.admins(successor), false);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(successor);
    fund.setContractURI('ipfs://removed-admin');

    assertEq(fund.contractURI(), CONTRACT_URI);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
  }

  function testAdminRenouncePreservesCreatedSchedule() public {
    _activateAdmin(successor);

    uint256 secondClaimableAt = block.timestamp + 2 days;

    _scheduleWithEvent(
      successor,
      secondSuccessor,
      0,
      secondClaimableAt
    );

    vm.expectEmit(true, false, false, false, address(fund));

    emit AdminRemoved(successor);

    vm.prank(successor);
    fund.renouncePrivileges();

    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);

    vm.expectRevert(WithStaff.AdminNotFound.selector);
    vm.prank(successor);
    fund.renouncePrivileges();

    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(successor);
    fund.setContractURI('ipfs://renounced-admin');

    assertEq(fund.contractURI(), CONTRACT_URI);

    vm.warp(secondClaimableAt);
    _claimWithEvent(secondSuccessor, secondClaimableAt);

    assertEq(fund.admins(successor), false);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.successors(secondSuccessor), 0);
    assertEq(fund.owner(), owner);
  }

  function testAdminCannotCallOwnerOnlyFunctions() public {
    _activateAdmin(successor);

    bytes memory expectedError = abi.encodeWithSelector(
      Ownable.OwnableUnauthorizedAccount.selector,
      successor
    );

    vm.expectRevert(expectedError);
    vm.prank(successor);
    fund.transferOwnership(successor);

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);

    vm.expectRevert(expectedError);
    vm.prank(successor);
    fund.removeAdmin(successor);

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);
  }

  function testRenounceOwnershipPreservesAdminsAndSchedules() public {
    _activateAdmin(successor);

    uint256 secondClaimableAt = block.timestamp + 2 days;

    _scheduleWithEvent(owner, secondSuccessor, 0, secondClaimableAt);
    _startOwnershipTransferWithEvent(newOwner);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, address(0));

    vm.prank(owner);
    fund.renounceOwnership();

    assertEq(fund.owner(), address(0));
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);
    assertEq(fund.successors(secondSuccessor), secondClaimableAt);

    vm.expectEmit(false, false, false, false, address(fund));

    emit ContractURIUpdated();

    vm.prank(successor);
    fund.setContractURI('ipfs://ownerless-admin');

    assertEq(fund.contractURI(), 'ipfs://ownerless-admin');
    assertEq(fund.owner(), address(0));

    vm.warp(secondClaimableAt);
    _claimWithEvent(secondSuccessor, secondClaimableAt);

    vm.expectEmit(false, false, false, false, address(fund));

    emit ContractURIUpdated();

    vm.prank(secondSuccessor);
    fund.setContractURI('ipfs://ownerless-successor');

    vm.expectRevert(
      abi.encodeWithSelector(
        Ownable.OwnableUnauthorizedAccount.selector,
        secondSuccessor
      )
    );

    vm.prank(secondSuccessor);
    fund.transferOwnership(secondSuccessor);

    assertEq(fund.contractURI(), 'ipfs://ownerless-successor');
    assertEq(fund.admins(successor), true);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.successors(secondSuccessor), 0);
    assertEq(fund.owner(), address(0));
    assertEq(fund.pendingOwner(), address(0));
  }

  function testZeroAddressScheduleBehavior() public {
    _activateAdmin(successor);

    uint256 claimableAt = block.timestamp + 1 days;

    _scheduleWithEvent(owner, address(0), 0, claimableAt);
    assertEq(fund.successors(address(0)), claimableAt);
    _removeScheduleWithEvent(owner, address(0), claimableAt);
    assertEq(fund.successors(address(0)), 0);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, address(0));

    vm.prank(owner);
    fund.renounceOwnership();
    vm.expectRevert(WithStaff.AlreadyStaff.selector);
    vm.prank(successor);
    fund.scheduleSuccessor(address(0), block.timestamp + 1 days);

    assertEq(fund.successors(address(0)), 0);
    assertEq(fund.admins(successor), true);
    assertEq(fund.owner(), address(0));
  }

  function testExecuteCannotEscalateAdminToOwner() public {
    _activateAdmin(successor);

    bytes memory innerReason = abi.encodeWithSelector(
      Ownable.OwnableUnauthorizedAccount.selector,
      address(fund)
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        ManuallyOperated.CallFailed.selector,
        innerReason
      )
    );

    vm.prank(successor);

    fund.execute(
      address(fund),
      0,
      abi.encodeCall(fund.transferOwnership, (successor))
    );

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);
    assertEq(fund.successors(successor), 0);
  }

  function _scheduleWithEvent(
    address scheduler,
    address candidate,
    uint256 previousClaimableAt,
    uint256 claimableAt
  ) private {
    vm.expectEmit(true, true, false, true, address(fund));

    emit SuccessorScheduled(
      candidate,
      previousClaimableAt,
      claimableAt,
      scheduler
    );

    vm.prank(scheduler);
    fund.scheduleSuccessor(candidate, claimableAt);
  }

  function _removeScheduleWithEvent(
    address remover,
    address candidate,
    uint256 claimableAt
  ) private {
    vm.expectEmit(true, true, false, true, address(fund));

    emit SuccessorRemoved(candidate, claimableAt, remover);

    vm.prank(remover);
    fund.removeSuccessor(candidate);
  }

  function _claimWithEvent(
    address candidate,
    uint256 claimableAt
  ) private {
    vm.expectEmit(true, false, false, true, address(fund));

    emit AdminActivated(candidate, claimableAt);

    vm.prank(candidate);
    fund.claimPrivileges();
  }

  function _activateAdmin(
    address candidate
  ) private returns (uint256 claimableAt) {
    claimableAt = block.timestamp + 1;

    _scheduleWithEvent(
      owner,
      candidate,
      fund.successors(candidate),
      claimableAt
    );

    vm.warp(claimableAt);

    _claimWithEvent(candidate, claimableAt);
    assertEq(fund.successors(candidate), 0);
    assertEq(fund.admins(candidate), true);
  }

  function _startOwnershipTransferWithEvent(address candidate) private {
    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferStarted(owner, candidate);

    vm.prank(owner);
    fund.transferOwnership(candidate);
  }

  function _assertAdminCanExecute(address admin) private {
    ExecutionTarget target = new ExecutionTarget();
    bytes memory data = abi.encodeCall(target.succeed, (42));

    vm.expectEmit(true, false, false, false, address(fund));

    emit Executed(address(target));

    vm.prank(admin);
    bytes memory result = fund.execute(address(target), 0, data);

    assertEq(target.caller(), address(fund));
    assertEq(target.callValue(), 0);
    assertEq(target.number(), 42);
    assertEq(abi.decode(result, (bytes32)), target.RETURN_VALUE());
  }

  function _assertAdminCanSetContractUri(address admin) private {
    string memory newUri = 'ipfs://emergency-admin';

    vm.expectEmit(false, false, false, false, address(fund));

    emit ContractURIUpdated();

    vm.prank(admin);
    fund.setContractURI(newUri);

    assertEq(fund.contractURI(), newUri);
  }

  function _assertAdminCanCompleteStage(address admin) private {
    vm.expectEmit(false, false, false, true, address(gate));

    emit StageCompleted(1);

    vm.prank(admin);
    fund.completeStage(SETTLEMENT_PRICE);

    assertEq(gate.currentStageId(), 2);

    (
      uint256 stagePrice,
      IDollar stageDollar,
      uint256 stageDollarScale,
      uint256 stageTokenAmount,
      uint256 stageRequestId
    ) = gate.stages(1);

    assertEq(stagePrice, SETTLEMENT_PRICE);
    assertEq(address(stageDollar), address(dollar));
    assertEq(stageDollarScale, DOLLAR_SCALE);
    assertEq(stageTokenAmount, 0);
    assertEq(stageRequestId, 0);
  }

  function _assertAdminCanChangeEntryPrice(address admin) private {
    uint256 changeTime = gate.priceChangeTime() + 7 days;
    uint256 newPrice = 104e16;

    vm.warp(changeTime);
    vm.expectEmit(false, false, false, true, address(gate));

    emit EntryPriceChanged(INITIAL_PRICE, newPrice);

    vm.prank(admin);
    fund.changeEntryPrice(newPrice);

    assertEq(gate.entryPrice(), newPrice);
    assertEq(gate.priceChangeTime(), changeTime);
  }

  function _assertAdminCanChangeDollar(address admin) private {
    StandardDollar nextDollar = new StandardDollar(
      'Emergency Dollar',
      'EUSD',
      18
    );

    vm.expectEmit(true, true, false, false, address(gate));

    emit DollarChanged(IDollar(address(nextDollar)), 18);

    vm.prank(admin);
    fund.changeDollar(address(nextDollar));

    assertEq(address(gate.dollar()), address(nextDollar));
    assertEq(nextDollar.decimals(), 18);
    assertEq(gate.entryPrice(), 104e16);
  }
}
