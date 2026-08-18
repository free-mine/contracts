// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../contracts/Gate.sol';
import './mocks/StandardDollar.sol';
import '../contracts/WithStaff.sol';
import './helpers/SystemFixture.sol';
import '../contracts/DepositStore.sol';

contract EmergencyOwnershipTest is SystemFixture {
  uint256 private constant PURCHASE_AMOUNT = 100e6;
  uint256 private constant REQUEST_AMOUNT = 40 * ONE_TOKEN;
  string private constant NEW_OWNER_URI = 'ipfs://new-owner';
  string private constant INTERIM_URI = 'ipfs://pending-transfer';

  function testTwoStepTransferChangesAccessOnlyAfterAcceptance() public {
    _startOwnershipTransfer(owner, successor);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), successor);
    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(successor), 0);
    _setContractUri(owner, INTERIM_URI);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(successor);
    fund.setContractURI(NEW_OWNER_URI);

    assertEq(fund.contractURI(), INTERIM_URI);
    _expectUnauthorized(stranger);

    vm.prank(stranger);
    fund.acceptOwnership();

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), successor);
    assertEq(fund.contractURI(), INTERIM_URI);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, successor);

    vm.prank(successor);
    fund.acceptOwnership();

    assertEq(fund.owner(), successor);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(successor), 0);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(owner);
    fund.setContractURI('ipfs://former-owner');

    assertEq(fund.contractURI(), INTERIM_URI);
    _setContractUri(successor, NEW_OWNER_URI);
    assertEq(fund.contractURI(), NEW_OWNER_URI);
  }

  function testTransferPreservesTopologyAndOpenRequestAndNewOwnerCanSettle()
    public
  {
    uint256 initialPriceChangeTime = gate.priceChangeTime();

    _buyWithEvent(alice, PURCHASE_AMOUNT);
    _requestWithEvent(alice, REQUEST_AMOUNT);
    _assertOpenRequestState(initialPriceChangeTime);
    _startOwnershipTransfer(owner, newOwner);
    _assertOpenRequestState(initialPriceChangeTime);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, newOwner);

    vm.prank(newOwner);
    fund.acceptOwnership();

    assertEq(fund.owner(), newOwner);
    assertEq(fund.pendingOwner(), address(0));
    _assertOpenRequestState(initialPriceChangeTime);
    _expectUnauthorized(newOwner);

    vm.prank(newOwner);
    gate.changeDollar(IDollar(address(dollar)));

    assertEq(address(gate.dollar()), address(dollar));
    _assertOpenRequestState(initialPriceChangeTime);

    uint256 reserve = _reserveAmount(REQUEST_AMOUNT, SETTLEMENT_PRICE);

    _approveReserveWithEvent(IERC20(address(dollar)), newOwner, reserve);
    _completeStageWithEvent(newOwner, 1, SETTLEMENT_PRICE);
    _assertCompletedRequestState(initialPriceChangeTime, newOwner);

    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestClosed(alice, 1, 1);

    vm.prank(alice);
    gate.withdraw(1, 1);

    _assertSettledRequestState(initialPriceChangeTime, newOwner);

    vm.expectRevert(
      abi.encodeWithSelector(Gate.RequestNotFound.selector, 1, 1)
    );

    vm.prank(alice);
    gate.withdraw(1, 1);

    _assertSettledRequestState(initialPriceChangeTime, newOwner);
  }

  function testScheduledPendingOwnerAcceptsBeforeTimerAndClearsOnlyOwnSchedule()
    public
  {
    uint256 activationTime = block.timestamp + 1;

    _scheduleSuccessor(owner, secondSuccessor, activationTime);

    vm.warp(activationTime);

    _claimPrivileges(secondSuccessor, activationTime);

    uint256 claimableAt = block.timestamp + 30 days;
    uint256 otherClaimableAt = block.timestamp + 60 days;

    _scheduleSuccessor(owner, successor, claimableAt);
    _scheduleSuccessor(owner, newOwner, otherClaimableAt);
    _startOwnershipTransfer(owner, successor);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(successor), claimableAt);
    assertEq(fund.successors(newOwner), otherClaimableAt);

    vm.expectEmit(true, true, false, true, address(fund));

    emit SuccessorRemoved(successor, claimableAt, successor);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, successor);

    vm.prank(successor);
    fund.acceptOwnership();

    assertEq(fund.owner(), successor);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(successor), 0);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.successors(secondSuccessor), 0);
    assertEq(fund.admins(newOwner), false);
    assertEq(fund.successors(newOwner), otherClaimableAt);
  }

  function testActiveAdminAcceptsOwnershipAndClearsOnlyOwnAdminRole() public {
    uint256 activationTime = block.timestamp + 1;

    _scheduleSuccessor(owner, successor, activationTime);
    _scheduleSuccessor(owner, secondSuccessor, activationTime);

    vm.warp(activationTime);

    _claimPrivileges(successor, activationTime);
    _claimPrivileges(secondSuccessor, activationTime);

    uint256 otherClaimableAt = block.timestamp + 30 days;

    _scheduleSuccessor(owner, newOwner, otherClaimableAt);
    _startOwnershipTransfer(owner, successor);
    assertEq(fund.admins(successor), true);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.successors(newOwner), otherClaimableAt);

    vm.expectEmit(true, false, false, false, address(fund));

    emit AdminRemoved(successor);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, successor);

    vm.prank(successor);
    fund.acceptOwnership();

    assertEq(fund.owner(), successor);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(successor), 0);
    assertEq(fund.admins(secondSuccessor), true);
    assertEq(fund.successors(secondSuccessor), 0);
    assertEq(fund.admins(newOwner), false);
    assertEq(fund.successors(newOwner), otherClaimableAt);
    _setContractUri(successor, NEW_OWNER_URI);
    assertEq(fund.contractURI(), NEW_OWNER_URI);
  }

  function testWrongScheduledCallerAcceptRollsBackCleanup()
    public
  {
    uint256 claimableAt = block.timestamp + 30 days;

    _scheduleSuccessor(owner, successor, claimableAt);
    _startOwnershipTransfer(owner, newOwner);
    _expectUnauthorized(successor);

    vm.prank(successor);
    fund.acceptOwnership();

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);
    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(successor), claimableAt);
    assertEq(fund.contractURI(), CONTRACT_URI);

    vm.warp(claimableAt);

    _claimPrivileges(successor, claimableAt);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);
    assertEq(fund.admins(successor), true);
    assertEq(fund.successors(successor), 0);
  }

  function testWrongAdminCallerAcceptRollsBackCleanup() public {
    uint256 claimableAt = block.timestamp + 1;

    _scheduleSuccessor(owner, successor, claimableAt);

    vm.warp(claimableAt);

    _claimPrivileges(successor, claimableAt);
    _startOwnershipTransfer(owner, newOwner);
    _expectUnauthorized(successor);

    vm.prank(successor);
    fund.acceptOwnership();

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);
    assertEq(fund.admins(successor), true);
    assertEq(fund.successors(successor), 0);
    _setContractUri(successor, INTERIM_URI);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, newOwner);

    vm.prank(newOwner);
    fund.acceptOwnership();

    assertEq(fund.owner(), newOwner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(newOwner), false);
    assertEq(fund.admins(successor), true);
    _setContractUri(successor, NEW_OWNER_URI);
    assertEq(fund.contractURI(), NEW_OWNER_URI);
  }

  function testEmergencyAdminKeepsOperationsButCannotRecoverOwnership()
    public
  {
    _buyWithEvent(alice, PURCHASE_AMOUNT);
    _requestWithEvent(alice, REQUEST_AMOUNT);

    uint256 claimableAt = block.timestamp + 30 days;

    _scheduleSuccessor(owner, successor, claimableAt);

    vm.warp(claimableAt);

    _claimPrivileges(successor, claimableAt);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);
    _expectUnauthorized(successor);

    vm.prank(successor);
    fund.transferOwnership(successor);

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);

    uint256 reserve = _reserveAmount(REQUEST_AMOUNT, SETTLEMENT_PRICE);

    _approveReserveWithEvent(IERC20(address(dollar)), successor, reserve);
    _completeStageWithEvent(successor, 1, SETTLEMENT_PRICE);

    StandardDollar replacement =
      new StandardDollar('Recovery Dollar', 'RUSD', 8);

    vm.expectEmit(true, true, false, false, address(gate));

    emit DollarChanged(IDollar(address(replacement)), 8);

    vm.prank(successor);
    fund.changeDollar(address(replacement));

    assertEq(address(gate.dollar()), address(replacement));
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);

    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestClosed(alice, 1, 1);

    vm.prank(alice);
    gate.withdraw(1, 1);

    _assertEmergencyAdminSettlement(replacement);
  }

  function testPendingTransferCanBeReplacedAndCancelled() public {
    _startOwnershipTransfer(owner, successor);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), successor);
    _startOwnershipTransfer(owner, newOwner);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);
    _expectUnauthorized(successor);

    vm.prank(successor);
    fund.acceptOwnership();

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), newOwner);
    assertEq(fund.admins(successor), false);
    assertEq(fund.successors(successor), 0);
    _startOwnershipTransfer(owner, address(0));
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    _expectUnauthorized(newOwner);

    vm.prank(newOwner);
    fund.acceptOwnership();

    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(newOwner), false);
    assertEq(fund.successors(newOwner), 0);
    _setContractUri(owner, NEW_OWNER_URI);
    assertEq(fund.contractURI(), NEW_OWNER_URI);
  }

  function _startOwnershipTransfer(
    address currentOwner,
    address candidate
  ) private {
    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferStarted(currentOwner, candidate);

    vm.prank(currentOwner);
    fund.transferOwnership(candidate);
  }

  function _scheduleSuccessor(
    address scheduler,
    address candidate,
    uint256 claimableAt
  ) private {
    uint256 previousClaimableAt = fund.successors(candidate);

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

  function _claimPrivileges(address candidate, uint256 claimableAt) private {
    vm.expectEmit(true, false, false, true, address(fund));

    emit AdminActivated(candidate, claimableAt);

    vm.prank(candidate);
    fund.claimPrivileges();
  }

  function _setContractUri(address staff, string memory newUri) private {
    vm.expectEmit(false, false, false, false, address(fund));

    emit ContractURIUpdated();

    vm.prank(staff);
    fund.setContractURI(newUri);
  }

  function _expectUnauthorized(address caller) private {
    vm.expectRevert(
      abi.encodeWithSelector(
        Ownable.OwnableUnauthorizedAccount.selector,
        caller
      )
    );
  }

  function _buyWithEvent(
    address buyer,
    uint256 dollarAmount
  ) private returns (uint256 tokenAmount) {
    tokenAmount = _dollarsToTokens(dollarAmount, gate.entryPrice());

    vm.prank(buyer);
    dollar.approve(address(gate), dollarAmount);

    vm.expectEmit(true, false, false, true, address(gate));

    emit Bought(buyer, dollarAmount, tokenAmount);

    vm.prank(buyer);
    gate.buy(dollarAmount);
  }

  function _requestWithEvent(
    address author,
    uint256 tokenAmount
  ) private returns (uint256 stageId, uint256 requestId) {
    stageId = gate.currentStageId();

    (, , , , uint256 currentRequestId) = gate.stages(stageId);

    requestId = currentRequestId + 1;

    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestOpened(author, stageId, requestId);

    vm.prank(author);
    gate.requestWithdrawal(tokenAmount);
  }

  function _approveReserveWithEvent(
    IERC20 selectedDollar,
    address staff,
    uint256 amount
  ) private {
    vm.expectEmit(true, false, false, false, address(fund));

    emit Executed(address(selectedDollar));

    _approveReserve(selectedDollar, staff, amount);
  }

  function _completeStageWithEvent(
    address staff,
    uint256 stageId,
    uint256 price
  ) private {
    vm.expectEmit(false, false, false, true, address(gate));

    emit StageCompleted(stageId);

    vm.prank(staff);
    fund.completeStage(price);
  }

  function _assertTopology(address expectedOwner) private view {
    assertEq(fund.owner(), expectedOwner);
    assertEq(address(fund.gate()), address(gate));
    assertEq(gate.owner(), address(fund));
    assertEq(token.owner(), address(gate));
    assertEq(address(gate.fundToken()), address(token));
  }

  function _assertOpenRequestState(uint256 initialPriceChangeTime)
    private
    view
  {
    assertEq(address(gate.dollar()), address(dollar));
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.priceChangeTime(), initialPriceChangeTime);
    assertEq(gate.currentStageId(), 1);
    assertEq(fund.contractURI(), CONTRACT_URI);
    assertEq(dollar.balanceOf(alice), ALICE_DOLLARS - PURCHASE_AMOUNT);
    assertEq(dollar.balanceOf(bob), BOB_DOLLARS);
    assertEq(dollar.balanceOf(address(fund)), PURCHASE_AMOUNT);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(dollar.allowance(alice, address(gate)), 0);
    assertEq(dollar.allowance(address(fund), address(gate)), 0);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), REQUEST_AMOUNT);
    assertEq(token.totalSupply(), 100 * ONE_TOKEN);
    assertEq(token.allowance(alice, address(gate)), 0);
    _assertOpenStage();
    assertEq(address(fund.gate()), address(gate));
    assertEq(gate.owner(), address(fund));
    assertEq(token.owner(), address(gate));
    assertEq(address(gate.fundToken()), address(token));
  }

  function _assertOpenStage() private view {
    (
      uint256 price,
      IDollar stageDollar,
      uint256 scale,
      uint256 tokenAmount,
      uint256 requestId
    ) = gate.stages(1);

    assertEq(price, 0);
    assertEq(address(stageDollar), address(0));
    assertEq(scale, 0);
    assertEq(tokenAmount, REQUEST_AMOUNT);
    assertEq(requestId, 1);
  }

  function _assertCompletedRequestState(
    uint256 initialPriceChangeTime,
    address expectedOwner
  ) private view {
    _assertTopology(expectedOwner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(address(gate.dollar()), address(dollar));
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.priceChangeTime(), initialPriceChangeTime);
    assertEq(gate.currentStageId(), 2);
    assertEq(fund.contractURI(), CONTRACT_URI);
    assertEq(dollar.balanceOf(alice), ALICE_DOLLARS - PURCHASE_AMOUNT);
    assertEq(dollar.balanceOf(bob), BOB_DOLLARS);
    assertEq(dollar.balanceOf(address(fund)), 62e6);
    assertEq(dollar.balanceOf(address(gate)), 38e6);
    assertEq(dollar.allowance(address(fund), address(gate)), 0);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), REQUEST_AMOUNT);
    assertEq(token.totalSupply(), 100 * ONE_TOKEN);
    _assertCompletedStage(REQUEST_AMOUNT);
  }

  function _assertSettledRequestState(
    uint256 initialPriceChangeTime,
    address expectedOwner
  ) private view {
    _assertTopology(expectedOwner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(address(gate.dollar()), address(dollar));
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.priceChangeTime(), initialPriceChangeTime);
    assertEq(gate.currentStageId(), 2);
    assertEq(fund.contractURI(), CONTRACT_URI);
    assertEq(dollar.balanceOf(alice), 938e6);
    assertEq(dollar.balanceOf(bob), BOB_DOLLARS);
    assertEq(dollar.balanceOf(address(fund)), 62e6);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(dollar.allowance(address(fund), address(gate)), 0);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), 60 * ONE_TOKEN);
    _assertCompletedStage(0);
  }

  function _assertCompletedStage(uint256 expectedTokenAmount) private view {
    (
      uint256 price,
      IDollar stageDollar,
      uint256 scale,
      uint256 tokenAmount,
      uint256 requestId
    ) = gate.stages(1);

    assertEq(price, SETTLEMENT_PRICE);
    assertEq(address(stageDollar), address(dollar));
    assertEq(scale, DOLLAR_SCALE);
    assertEq(tokenAmount, expectedTokenAmount);
    assertEq(requestId, 1);
  }

  function _assertEmergencyAdminSettlement(StandardDollar replacement)
    private
    view
  {
    _assertTopology(owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);
    assertEq(address(gate.dollar()), address(replacement));
    assertEq(gate.currentStageId(), 2);
    assertEq(dollar.balanceOf(alice), 938e6);
    assertEq(dollar.balanceOf(address(fund)), 62e6);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(dollar.allowance(address(fund), address(gate)), 0);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), 60 * ONE_TOKEN);
    assertEq(replacement.balanceOf(alice), 0);
    assertEq(replacement.balanceOf(address(fund)), 0);
    assertEq(replacement.balanceOf(address(gate)), 0);
    assertEq(replacement.allowance(address(fund), address(gate)), 0);
    _assertCompletedStage(0);
  }
}
