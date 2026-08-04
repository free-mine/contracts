// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import { Gate } from '../contracts/Gate.sol';
import { WithStaff } from '../contracts/WithStaff.sol';
import { SystemFixture } from './helpers/SystemFixture.sol';
import { DepositStore, IDollar } from '../contracts/DepositStore.sol';

contract NominalGuardsTest is SystemFixture {
  uint256 private constant PURCHASE_AMOUNT = 100e6;
  uint256 private constant MIN_ENTRY_PRICE = 96e16;
  uint256 private constant MAX_ENTRY_PRICE = 104e16;
  uint256 private constant MIN_SETTLEMENT_PRICE = 90e16;

  function testCompleteStageAcceptsMinimumPrice() public {
    vm.expectEmit(false, false, false, true, address(gate));

    emit StageCompleted(1);

    _completeStage(MIN_SETTLEMENT_PRICE);
    _assertEmptyCompletedStage(MIN_SETTLEMENT_PRICE);
  }

  function testCompleteStageAcceptsEntryPrice() public {
    vm.expectEmit(false, false, false, true, address(gate));

    emit StageCompleted(1);

    _completeStage(INITIAL_PRICE);
    _assertEmptyCompletedStage(INITIAL_PRICE);
  }

  function testCompleteStageRejectsPriceBelowMinimum() public {
    uint256 price = MIN_SETTLEMENT_PRICE - 1;

    vm.expectRevert(
      abi.encodeWithSelector(
        Gate.PriceIsTooLow.selector,
        MIN_SETTLEMENT_PRICE
      )
    );

    _completeStage(price);
    _assertEmptyCurrentStage();
  }

  function testCompleteStageRejectsPriceAboveEntryPrice() public {
    vm.expectRevert(Gate.PriceIsHigherThanEntry.selector);

    _completeStage(INITIAL_PRICE + 1);
    _assertEmptyCurrentStage();
  }

  function testCannotWithdrawFromCurrentStage() public {
    uint256 tokenAmount = _buy(alice, PURCHASE_AMOUNT);
    (uint256 stageId, uint256 requestId) = _request(alice, tokenAmount);
    uint256 aliceBalance = token.balanceOf(alice);
    uint256 gateBalance = token.balanceOf(address(gate));
    uint256 supply = token.totalSupply();

    vm.expectRevert(Gate.StageIsNotComplete.selector);
    vm.prank(alice);
    gate.withdraw(stageId, requestId);

    assertEq(token.balanceOf(alice), aliceBalance);
    assertEq(token.balanceOf(address(gate)), gateBalance);
    assertEq(token.totalSupply(), supply);
    _assertOpenStage(stageId, tokenAmount, requestId);
  }

  function testStageCompletionIsAtomicWithoutEnoughAllowance() public {
    uint256 tokenAmount = _buy(alice, PURCHASE_AMOUNT);
    (uint256 stageId, uint256 requestId) = _request(alice, tokenAmount);
    uint256 reserve = _reserveAmount(tokenAmount, SETTLEMENT_PRICE);
    uint256 allowance = reserve - 1;

    _approveReserve(allowance);

    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        address(gate),
        allowance,
        reserve
      )
    );

    _completeStage(SETTLEMENT_PRICE);

    _assertFailedCompletion(
      stageId,
      tokenAmount,
      requestId,
      PURCHASE_AMOUNT,
      allowance,
      0
    );

    _cancelPreservedRequest(stageId, requestId, tokenAmount);
  }

  function testStageCompletionIsAtomicWithoutEnoughBalance() public {
    uint256 tokenAmount = _buy(alice, PURCHASE_AMOUNT);
    (uint256 stageId, uint256 requestId) = _request(alice, tokenAmount);
    uint256 reserve = _reserveAmount(tokenAmount, SETTLEMENT_PRICE);
    uint256 fundBalance = reserve - 1;
    uint256 transferAmount = PURCHASE_AMOUNT - fundBalance;

    _approveReserve(reserve);
    _transferFundDollars(stranger, transferAmount);

    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientBalance.selector,
        address(fund),
        fundBalance,
        reserve
      )
    );

    _completeStage(SETTLEMENT_PRICE);

    _assertFailedCompletion(
      stageId,
      tokenAmount,
      requestId,
      fundBalance,
      reserve,
      transferAmount
    );

    _cancelPreservedRequest(stageId, requestId, tokenAmount);
  }

  function testEntryPriceChangeIsTooEarlyBeforeOneWeek() public {
    uint256 initialChangeTime = gate.priceChangeTime();

    vm.warp(initialChangeTime + 7 days - 1);
    vm.expectRevert(DepositStore.EntryPriceChangeTooEarly.selector);

    _changeEntryPrice(INITIAL_PRICE);
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.priceChangeTime(), initialChangeTime);
  }

  function testEntryPriceChangeIsAllowedExactlyAfterOneWeek() public {
    uint256 changeTime = gate.priceChangeTime() + 7 days;

    vm.warp(changeTime);
    vm.expectEmit(false, false, false, true, address(gate));

    emit EntryPriceChanged(INITIAL_PRICE, INITIAL_PRICE);

    _changeEntryPrice(INITIAL_PRICE);
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.priceChangeTime(), changeTime);
  }

  function testEntryPriceAcceptsMinimumBoundary() public {
    _warpToPriceChange();

    vm.expectEmit(false, false, false, true, address(gate));

    emit EntryPriceChanged(INITIAL_PRICE, MIN_ENTRY_PRICE);

    _changeEntryPrice(MIN_ENTRY_PRICE);
    assertEq(gate.entryPrice(), MIN_ENTRY_PRICE);
  }

  function testEntryPriceAcceptsMaximumBoundary() public {
    _warpToPriceChange();

    vm.expectEmit(false, false, false, true, address(gate));

    emit EntryPriceChanged(INITIAL_PRICE, MAX_ENTRY_PRICE);

    _changeEntryPrice(MAX_ENTRY_PRICE);
    assertEq(gate.entryPrice(), MAX_ENTRY_PRICE);
  }

  function testEntryPriceRejectsBelowMinimumBoundary() public {
    _warpToPriceChange();

    vm.expectRevert(DepositStore.EntryPriceChangeOutOfRange.selector);

    _changeEntryPrice(MIN_ENTRY_PRICE - 1);
    assertEq(gate.entryPrice(), INITIAL_PRICE);
  }

  function testEntryPriceRejectsAboveMaximumBoundary() public {
    _warpToPriceChange();

    vm.expectRevert(DepositStore.EntryPriceChangeOutOfRange.selector);

    _changeEntryPrice(MAX_ENTRY_PRICE + 1);
    assertEq(gate.entryPrice(), INITIAL_PRICE);
  }

  function testNextBuyUsesChangedEntryPrice() public {
    uint256 changeTime = gate.priceChangeTime() + 7 days;
    uint256 dollarAmount = 104e6;

    vm.warp(changeTime);
    vm.expectEmit(false, false, false, true, address(gate));

    emit EntryPriceChanged(INITIAL_PRICE, MAX_ENTRY_PRICE);

    _changeEntryPrice(MAX_ENTRY_PRICE);

    uint256 aliceDollarsBefore = dollar.balanceOf(alice);
    uint256 fundDollarsBefore = dollar.balanceOf(address(fund));
    uint256 tokenAmount = _buy(alice, dollarAmount);

    assertEq(tokenAmount, 100e18);
    assertEq(token.balanceOf(alice), 100e18);
    assertEq(token.totalSupply(), 100e18);
    assertEq(dollar.balanceOf(alice), aliceDollarsBefore - dollarAmount);
    assertEq(dollar.balanceOf(address(fund)), fundDollarsBefore + dollarAmount);
    assertEq(dollar.balanceOf(address(gate)), 0);
  }

  function testStrangerCannotUseFundStaffFunctions() public {
    bytes memory emptyData = new bytes(0);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(stranger);
    fund.execute(address(dollar), 0, emptyData);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(stranger);
    fund.completeStage(INITIAL_PRICE);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(stranger);
    fund.changeEntryPrice(INITIAL_PRICE);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(stranger);
    fund.setContractURI('ipfs://stranger');
  }

  function testEoaCannotUseTokenOwnerFunctions() public {
    bytes memory expectedError = abi.encodeWithSelector(
      Ownable.OwnableUnauthorizedAccount.selector,
      owner
    );

    vm.expectRevert(expectedError);
    vm.prank(owner);
    token.mint(alice, ONE_TOKEN);

    vm.expectRevert(expectedError);
    vm.prank(owner);
    token.burn(alice, ONE_TOKEN);

    vm.expectRevert(expectedError);
    vm.prank(owner);
    token.take(alice, ONE_TOKEN);
  }

  function testEoaCannotUseGateOwnerFunctions() public {
    bytes memory expectedError = abi.encodeWithSelector(
      Ownable.OwnableUnauthorizedAccount.selector,
      owner
    );

    vm.expectRevert(expectedError);
    vm.prank(owner);
    gate.completeStage(INITIAL_PRICE);

    vm.expectRevert(expectedError);
    vm.prank(owner);
    gate.changeEntryPrice(INITIAL_PRICE);
  }

  function testGateOwnerCannotBuy() public {
    vm.expectRevert(DepositStore.OwnerCannotBuy.selector);
    vm.prank(address(fund));
    gate.buy(1e6);
  }

  function _changeEntryPrice(uint256 newPrice) private {
    vm.prank(owner);
    fund.changeEntryPrice(newPrice);
  }

  function _warpToPriceChange() private {
    vm.warp(gate.priceChangeTime() + 7 days);
  }

  function _transferFundDollars(
    address receiver,
    uint256 amount
  ) private {
    bytes memory data = abi.encodeCall(IERC20.transfer, (receiver, amount));

    vm.prank(owner);
    fund.execute(address(dollar), 0, data);
  }

  function _cancelPreservedRequest(
    uint256 stageId,
    uint256 requestId,
    uint256 tokenAmount
  ) private {
    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestClosed(alice, stageId, requestId);

    vm.prank(alice);
    gate.cancelWithdrawalRequest(stageId, requestId);

    assertEq(token.balanceOf(alice), tokenAmount - ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), tokenAmount - ONE_TOKEN);
  }

  function _assertEmptyCompletedStage(uint256 price) private view {
    assertEq(gate.currentStageId(), 2);

    (
      uint256 stagePrice,
      IDollar stageDollar,
      uint256 stageDollarScale,
      uint256 stageTokenAmount,
      uint256 requestId
    ) = gate.stages(1);

    assertEq(stagePrice, price);
    assertEq(address(stageDollar), address(dollar));
    assertEq(stageDollarScale, DOLLAR_SCALE);
    assertEq(stageTokenAmount, 0);
    assertEq(requestId, 0);
  }

  function _assertEmptyCurrentStage() private view {
    assertEq(gate.currentStageId(), 1);
    _assertOpenStage(1, 0, 0);
  }

  function _assertOpenStage(
    uint256 stageId,
    uint256 tokenAmount,
    uint256 requestId
  ) private view {
    (
      uint256 stagePrice,
      IDollar stageDollar,
      uint256 stageDollarScale,
      uint256 stageTokenAmount,
      uint256 currentRequestId
    ) = gate.stages(stageId);

    assertEq(stagePrice, 0);
    assertEq(address(stageDollar), address(0));
    assertEq(stageDollarScale, 0);
    assertEq(stageTokenAmount, tokenAmount);
    assertEq(currentRequestId, requestId);
  }

  function _assertFailedCompletion(
    uint256 stageId,
    uint256 tokenAmount,
    uint256 requestId,
    uint256 fundBalance,
    uint256 allowance,
    uint256 strangerBalance
  ) private view {
    assertEq(gate.currentStageId(), stageId);
    _assertOpenStage(stageId, tokenAmount, requestId);
    assertEq(dollar.balanceOf(address(fund)), fundBalance);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(dollar.balanceOf(owner), 0);
    assertEq(dollar.balanceOf(alice), ALICE_DOLLARS - PURCHASE_AMOUNT);
    assertEq(dollar.balanceOf(bob), BOB_DOLLARS);
    assertEq(dollar.balanceOf(stranger), strangerBalance);
    assertEq(dollar.allowance(address(fund), address(gate)), allowance);
    assertEq(token.balanceOf(alice), 0);
    assertEq(token.balanceOf(address(gate)), tokenAmount);
    assertEq(token.totalSupply(), tokenAmount);
  }
}
