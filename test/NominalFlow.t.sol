// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '../contracts/Gate.sol';
import './helpers/SystemFixture.sol';
import './mocks/ExecutionTarget.sol';
import '../contracts/DepositStore.sol';
import '../contracts/ManuallyOperated.sol';

contract NominalFlowTest is SystemFixture {
  function testBuyMovesDollarsAndMintsExactTokens() public {
    uint256 dollarAmount = 100e6;
    uint256 tokenAmount = 100e18;
    uint256 aliceDollarBefore = dollar.balanceOf(alice);
    uint256 bought = _buyWithEvent(alice, dollarAmount);

    assertEq(bought, tokenAmount);
    assertEq(dollar.balanceOf(alice), aliceDollarBefore - dollarAmount);
    assertEq(dollar.balanceOf(address(fund)), dollarAmount);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(dollar.balanceOf(bob), BOB_DOLLARS);
    assertEq(token.balanceOf(alice), tokenAmount);
    assertEq(token.balanceOf(bob), 0);
    assertEq(token.totalSupply(), tokenAmount);
    assertEq(gate.currentStageId(), 1);

    (, , , uint256 requested, uint256 requestId) = gate.stages(1);

    assertEq(requested, 0);
    assertEq(requestId, 0);
  }

  function testBuyWithInsufficientAllowanceIsAtomic() public {
    uint256 dollarAmount = 100e6;
    uint256 aliceDollarBefore = dollar.balanceOf(alice);

    vm.expectRevert();
    vm.prank(alice);
    gate.buy(dollarAmount);

    assertEq(dollar.balanceOf(alice), aliceDollarBefore);
    assertEq(dollar.balanceOf(address(fund)), 0);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(token.balanceOf(alice), 0);
    assertEq(token.totalSupply(), 0);
    assertEq(gate.currentStageId(), 1);
  }

  function testBuyWithInsufficientBalanceIsAtomic() public {
    uint256 dollarAmount = ALICE_DOLLARS + 1;

    vm.prank(alice);
    dollar.approve(address(gate), dollarAmount);
    vm.expectRevert();
    vm.prank(alice);
    gate.buy(dollarAmount);

    assertEq(dollar.balanceOf(alice), ALICE_DOLLARS);
    assertEq(dollar.balanceOf(address(fund)), 0);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(token.balanceOf(alice), 0);
    assertEq(token.totalSupply(), 0);
    assertEq(gate.currentStageId(), 1);
  }

  function testMinimumWithdrawalRequestUsesTakeWithoutApproval() public {
    _buy(alice, 1e6);

    uint256 dollarBefore = dollar.balanceOf(alice);
    uint256 bobDollarBefore = dollar.balanceOf(bob);
    uint256 fundDollarBefore = dollar.balanceOf(address(fund));
    uint256 gateDollarBefore = dollar.balanceOf(address(gate));
    uint256 supplyBefore = token.totalSupply();

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      ONE_TOKEN
    );

    assertEq(stageId, 1);
    assertEq(requestId, 1);
    assertEq(token.allowance(alice, address(gate)), 0);
    assertEq(token.balanceOf(alice), 0);
    assertEq(token.balanceOf(address(gate)), ONE_TOKEN);
    assertEq(token.totalSupply(), supplyBefore);
    assertEq(dollar.balanceOf(alice), dollarBefore);
    assertEq(dollar.balanceOf(bob), bobDollarBefore);
    assertEq(dollar.balanceOf(address(fund)), fundDollarBefore);
    assertEq(dollar.balanceOf(address(gate)), gateDollarBefore);

    (, , , uint256 requested, uint256 currentRequestId)
      = gate.stages(stageId);

    assertEq(requested, ONE_TOKEN);
    assertEq(currentRequestId, requestId);
  }

  function testTooSmallWithdrawalRequestIsAtomic() public {
    _buy(alice, 1e6);

    uint256 amount = ONE_TOKEN - 1;
    uint256 aliceTokenBefore = token.balanceOf(alice);
    uint256 supplyBefore = token.totalSupply();
    uint256 fundDollarBefore = dollar.balanceOf(address(fund));

    vm.expectRevert(
      abi.encodeWithSelector(Gate.InsufficientQuantity.selector, amount)
    );

    vm.prank(alice);
    gate.requestWithdrawal(amount);

    assertEq(token.balanceOf(alice), aliceTokenBefore);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), supplyBefore);
    assertEq(dollar.balanceOf(address(fund)), fundDollarBefore);

    (, , , uint256 requested, uint256 requestId) = gate.stages(1);

    assertEq(requested, 0);
    assertEq(requestId, 0);
  }

  function testCurrentRequestCancellationBurnsOneToken() public {
    uint256 requestedAmount = 10 * ONE_TOKEN;

    _buy(alice, 10e6);

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      requestedAmount
    );

    uint256 supplyBefore = token.totalSupply();
    uint256 aliceDollarBefore = dollar.balanceOf(alice);
    uint256 fundDollarBefore = dollar.balanceOf(address(fund));

    vm.expectRevert(Gate.SenderIsNotAuthor.selector);
    vm.prank(bob);
    gate.cancelWithdrawalRequest(stageId, requestId);

    (, , , uint256 openAmount, uint256 openRequestId)
      = gate.stages(stageId);

    assertEq(openAmount, requestedAmount);
    assertEq(openRequestId, requestId);
    assertEq(token.balanceOf(alice), 0);
    assertEq(token.balanceOf(bob), 0);
    assertEq(token.balanceOf(address(gate)), requestedAmount);
    assertEq(token.totalSupply(), supplyBefore);
    assertEq(dollar.balanceOf(alice), aliceDollarBefore);
    assertEq(dollar.balanceOf(address(fund)), fundDollarBefore);
    assertEq(dollar.balanceOf(address(gate)), 0);

    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestClosed(alice, stageId, requestId);

    vm.prank(alice);
    gate.cancelWithdrawalRequest(stageId, requestId);

    assertEq(token.balanceOf(alice), requestedAmount - ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), supplyBefore - ONE_TOKEN);
    assertEq(dollar.balanceOf(alice), aliceDollarBefore);
    assertEq(dollar.balanceOf(address(fund)), fundDollarBefore);
    assertEq(dollar.balanceOf(address(gate)), 0);

    (, , , uint256 requested, uint256 currentRequestId) =
      gate.stages(stageId);

    assertEq(requested, 0);
    assertEq(currentRequestId, requestId);

    vm.expectRevert(
      abi.encodeWithSelector(
        Gate.RequestNotFound.selector,
        stageId,
        requestId
      )
    );

    vm.prank(alice);
    gate.cancelWithdrawalRequest(stageId, requestId);
  }

  function testTwoUserCycleCoversWithdrawAndCompletedCancellation() public {
    uint256 aliceRequest = 40 * ONE_TOKEN;
    uint256 bobRequest = 60 * ONE_TOKEN;
    uint256 totalRequested = aliceRequest + bobRequest;

    _buyWithEvent(alice, 100e6);
    _buyWithEvent(bob, 100e6);

    (uint256 stageId, uint256 aliceRequestId)
      = _requestWithEvent(alice, aliceRequest);

    (, uint256 bobRequestId) = _requestWithEvent(bob, bobRequest);

    assertEq(stageId, 1);
    assertEq(aliceRequestId, 1);
    assertEq(bobRequestId, 2);
    assertEq(token.balanceOf(address(gate)), totalRequested);
    assertEq(token.totalSupply(), 200 * ONE_TOKEN);

    uint256 reserve = _reserveAmount(totalRequested, SETTLEMENT_PRICE);

    _approveReserveWithEvent(reserve);

    vm.expectEmit(false, false, false, true, address(gate));

    emit StageCompleted(stageId);

    _completeStage(SETTLEMENT_PRICE);
    _assertCompletedStage(totalRequested, reserve);
    _withdrawAlice(stageId, aliceRequestId, aliceRequest);
    _cancelBob(stageId, bobRequestId, bobRequest);
    _assertFinalCycleState(aliceRequest, bobRequest);
    _assertRequestsAreClosed(stageId, aliceRequestId, bobRequestId);
  }

  function testExecuteReturnsDataAndUsesFundAsCaller() public {
    ExecutionTarget target = new ExecutionTarget();
    bytes memory data = abi.encodeCall(target.succeed, (42));

    vm.expectEmit(true, false, false, false, address(fund));

    emit Executed(address(target));

    vm.prank(owner);

    bytes memory result = fund.execute(address(target), 0, data);

    assertEq(target.caller(), address(fund));
    assertEq(target.callValue(), 0);
    assertEq(target.number(), 42);
    assertEq(abi.decode(result, (bytes32)), target.RETURN_VALUE());
  }

  function testExecuteWrapsRevertAndRollsBackTarget() public {
    ExecutionTarget target = new ExecutionTarget();
    uint256 newNumber = 42;

    bytes memory reason = abi.encodeWithSelector(
      ExecutionTarget.ExecutionFailed.selector,
      newNumber
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        ManuallyOperated.CallFailed.selector,
        reason
      )
    );

    vm.prank(owner);

    fund.execute(
      address(target),
      0,
      abi.encodeCall(target.fail, (newNumber))
    );

    assertEq(target.number(), 0);
  }

  function testSacrificeBurnsCallersTokens() public {
    uint256 amount = 4 * ONE_TOKEN;

    _buy(alice, 20e6);

    uint256 balanceBefore = token.balanceOf(alice);
    uint256 supplyBefore = token.totalSupply();

    vm.expectEmit(true, false, false, true, address(gate));

    emit Sacrificed(alice, amount);

    vm.prank(alice);
    gate.sacrifice(amount);

    assertEq(token.balanceOf(alice), balanceBefore - amount);
    assertEq(token.totalSupply(), supplyBefore - amount);
  }

  function testOwnerUpdatesContractUri() public {
    string memory newUri = 'ipfs://updated-fund';

    vm.expectEmit(false, false, false, false, address(fund));

    emit ContractURIUpdated();

    vm.prank(owner);
    fund.setContractURI(newUri);

    assertEq(fund.contractURI(), newUri);
  }

  function testStagesKeepIndependentRequestsAndSettlementData() public {
    uint256 oldRequest = 10 * ONE_TOKEN;
    uint256 newRequest = 4 * ONE_TOKEN;

    _buy(alice, 20e6);

    (uint256 oldStageId, uint256 oldRequestId) = _request(
      alice,
      oldRequest
    );

    _approveAndComplete(oldRequest, SETTLEMENT_PRICE);

    vm.warp(gate.priceChangeTime() + 7 days);
    vm.prank(owner);
    fund.changeEntryPrice(104e16);

    _buy(bob, 104e5);

    (uint256 newStageId, uint256 newRequestId) = _requestWithEvent(
      bob,
      newRequest
    );

    assertEq(oldStageId, 1);
    assertEq(oldRequestId, 1);
    assertEq(newStageId, 2);
    assertEq(newRequestId, 1);
    _assertOldStageUnchanged(oldRequest);

    (, , , uint256 newTotal, uint256 newCurrentRequestId)
      = gate.stages(newStageId);

    assertEq(newTotal, newRequest);
    assertEq(newCurrentRequestId, newRequestId);

    uint256 aliceDollarBefore = dollar.balanceOf(alice);
    uint256 oldPayout = _tokensToDollars(oldRequest, SETTLEMENT_PRICE);

    vm.prank(alice);
    gate.withdraw(oldStageId, oldRequestId);

    assertEq(dollar.balanceOf(alice), aliceDollarBefore + oldPayout);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(token.balanceOf(address(gate)), newRequest);
  }

  function testRequestIdsStayMonotonicAfterCancellation() public {
    _buy(alice, 20e6);

    (, uint256 firstId) = _request(alice, 4 * ONE_TOKEN);
    (, uint256 secondId) = _request(alice, 5 * ONE_TOKEN);

    vm.prank(alice);
    gate.cancelWithdrawalRequest(1, firstId);

    (, uint256 thirdId) = _request(alice, 3 * ONE_TOKEN);

    assertEq(firstId, 1);
    assertEq(secondId, 2);
    assertEq(thirdId, 3);

    (, , , uint256 requested, uint256 currentRequestId) = gate.stages(1);

    assertEq(requested, 8 * ONE_TOKEN);
    assertEq(currentRequestId, thirdId);

    vm.prank(alice);
    gate.cancelWithdrawalRequest(1, secondId);
    vm.prank(alice);
    gate.cancelWithdrawalRequest(1, thirdId);

    (, , , requested, currentRequestId) = gate.stages(1);

    assertEq(requested, 0);
    assertEq(currentRequestId, thirdId);
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

    (uint256 openedStageId, uint256 openedRequestId) = _request(
      author,
      tokenAmount
    );

    assertEq(openedStageId, stageId);
    assertEq(openedRequestId, requestId);
  }

  function _approveReserveWithEvent(uint256 reserve) private {
    vm.expectEmit(true, false, false, false, address(fund));

    emit Executed(address(dollar));

    _approveReserve(reserve);
  }

  function _assertCompletedStage(
    uint256 totalRequested,
    uint256 reserve
  ) private view {
    (
      uint256 price,
      IDollar stageDollar,
      uint256 scale,
      uint256 requested,
      uint256 requestId
    ) = gate.stages(1);

    assertEq(gate.currentStageId(), 2);
    assertEq(price, SETTLEMENT_PRICE);
    assertEq(address(stageDollar), address(dollar));
    assertEq(scale, DOLLAR_SCALE);
    assertEq(requested, totalRequested);
    assertEq(requestId, 2);
    assertEq(dollar.balanceOf(address(fund)), 200e6 - reserve);
    assertEq(dollar.balanceOf(address(gate)), reserve);
    assertEq(dollar.balanceOf(alice), ALICE_DOLLARS - 100e6);
    assertEq(dollar.balanceOf(bob), BOB_DOLLARS - 100e6);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(bob), 40 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), totalRequested);
    assertEq(token.totalSupply(), 200 * ONE_TOKEN);
  }

  function _withdrawAlice(
    uint256 stageId,
    uint256 requestId,
    uint256 tokenAmount
  ) private {
    uint256 payout = _tokensToDollars(tokenAmount, SETTLEMENT_PRICE);
    uint256 dollarBefore = dollar.balanceOf(alice);
    uint256 bobDollarBefore = dollar.balanceOf(bob);
    uint256 fundDollarBefore = dollar.balanceOf(address(fund));
    uint256 gateDollarBefore = dollar.balanceOf(address(gate));
    uint256 gateTokenBefore = token.balanceOf(address(gate));
    uint256 supplyBefore = token.totalSupply();

    vm.expectEmit(true, false, false, true, address(gate));
    emit RequestClosed(alice, stageId, requestId);

    vm.prank(alice);
    gate.withdraw(stageId, requestId);

    assertEq(dollar.balanceOf(alice), dollarBefore + payout);
    assertEq(dollar.balanceOf(bob), bobDollarBefore);
    assertEq(dollar.balanceOf(address(fund)), fundDollarBefore);
    assertEq(dollar.balanceOf(address(gate)), gateDollarBefore - payout);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), gateTokenBefore - tokenAmount);
    assertEq(token.totalSupply(), supplyBefore - tokenAmount);
  }

  function _cancelBob(
    uint256 stageId,
    uint256 requestId,
    uint256 tokenAmount
  ) private {
    uint256 reserve = _tokensToDollars(tokenAmount, SETTLEMENT_PRICE);
    uint256 aliceDollarBefore = dollar.balanceOf(alice);
    uint256 bobDollarBefore = dollar.balanceOf(bob);
    uint256 fundDollarBefore = dollar.balanceOf(address(fund));
    uint256 gateDollarBefore = dollar.balanceOf(address(gate));
    uint256 supplyBefore = token.totalSupply();

    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestClosed(bob, stageId, requestId);

    vm.prank(bob);
    gate.cancelWithdrawalRequest(stageId, requestId);

    assertEq(token.balanceOf(bob), 99 * ONE_TOKEN);
    assertEq(token.totalSupply(), supplyBefore - ONE_TOKEN);
    assertEq(dollar.balanceOf(alice), aliceDollarBefore);
    assertEq(dollar.balanceOf(bob), bobDollarBefore);
    assertEq(dollar.balanceOf(address(fund)), fundDollarBefore + reserve);
    assertEq(dollar.balanceOf(address(gate)), gateDollarBefore - reserve);
  }

  function _assertFinalCycleState(
    uint256 aliceRequest,
    uint256 bobRequest
  ) private view {
    assertEq(token.balanceOf(alice), 100 * ONE_TOKEN - aliceRequest);
    assertEq(token.balanceOf(bob), 100 * ONE_TOKEN - ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), 159 * ONE_TOKEN);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(dollar.balanceOf(address(fund)), 162e6);
    assertEq(dollar.balanceOf(alice), 938e6);
    assertEq(dollar.balanceOf(bob), BOB_DOLLARS - 100e6);

    (, , , uint256 requested, uint256 requestId) = gate.stages(1);

    assertEq(requested, aliceRequest);
    assertEq(requestId, 2);
    assertEq(aliceRequest + bobRequest, 100 * ONE_TOKEN);
  }

  function _assertRequestsAreClosed(
    uint256 stageId,
    uint256 aliceRequestId,
    uint256 bobRequestId
  ) private {
    vm.expectRevert(
      abi.encodeWithSelector(
        Gate.RequestNotFound.selector,
        stageId,
        aliceRequestId
      )
    );

    vm.prank(alice);
    gate.withdraw(stageId, aliceRequestId);

    vm.expectRevert(
      abi.encodeWithSelector(
        Gate.RequestNotFound.selector,
        stageId,
        bobRequestId
      )
    );

    vm.prank(bob);
    gate.cancelWithdrawalRequest(stageId, bobRequestId);
  }

  function _assertOldStageUnchanged(uint256 oldRequest) private view {
    (
      uint256 price,
      IDollar stageDollar,
      uint256 scale,
      uint256 requested,
      uint256 requestId
    ) = gate.stages(1);

    assertEq(price, SETTLEMENT_PRICE);
    assertEq(address(stageDollar), address(dollar));
    assertEq(scale, DOLLAR_SCALE);
    assertEq(requested, oldRequest);
    assertEq(requestId, 1);
  }
}
