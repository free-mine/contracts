// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './mocks/StandardDollar.sol';
import './helpers/SystemFixture.sol';

contract RoundingTest is SystemFixture {
  uint256 private constant ROUNDING_PRICE_6 = 950_000_500_000_000_000;
  uint256 private constant THREE_REQUEST_PRICE = 950_000_900_000_000_000;
  uint256 private constant ROUNDING_PRICE_8 = 950_000_006_000_000_000;
  uint256 private constant SECOND_STAGE_PRICE = 900_000_900_000_000_000;
  uint256 private constant CLOSURE_PRICE = 950_000_250_000_000_000;

  struct StageOutcome {
    uint256 reserve;
    uint256 totalPayout;
    uint256 dust;
  }

  struct TwoRequestCase {
    uint256 requestAmount;
    uint256 price;
    uint256 scale;
    uint256 reserve;
    uint256 payout;
    uint256 dust;
  }

  address internal charlie;

  function setUp() public override {
    super.setUp();

    charlie = makeAddr('charlie');
    dollar.mint(charlie, 1_000e6);
  }

  function testMultipleWithdrawalsCanLeaveRoundingDust() public {
    _buy(alice, 1e6);
    _buy(bob, 1e6);

    _assertTwoRequestRounding(
      IERC20(address(dollar)),
      TwoRequestCase({
        requestAmount: ONE_TOKEN,
        price: ROUNDING_PRICE_6,
        scale: DOLLAR_SCALE,
        reserve: 1_900_001,
        payout: 950_000,
        dust: 1
      })
    );
  }

  function testRoundingDustWithThreeRequests() public {
    uint256[3] memory amounts = _threeAmounts(
      ONE_TOKEN,
      ONE_TOKEN,
      ONE_TOKEN
    );

    uint256[3] memory payouts = _threeAmounts(
      950_000,
      950_000,
      950_000
    );

    uint8[3] memory order = _order(0, 1, 2);

    _buyDefaultTokens(ONE_TOKEN, ONE_TOKEN, ONE_TOKEN);

    StageOutcome memory outcome = _runThreeWithdrawalStage(
      amounts,
      payouts,
      THREE_REQUEST_PRICE,
      2_850_002,
      order
    );

    assertEq(outcome.reserve, 2_850_002);
    assertEq(outcome.totalPayout, 2_850_000);
    assertEq(outcome.dust, 2);
  }

  function testRoundingDustWithDifferentRequestAmounts() public {
    uint256[3] memory amounts = _threeAmounts(
      ONE_TOKEN,
      3 * ONE_TOKEN,
      7 * ONE_TOKEN
    );

    uint256[3] memory payouts = _threeAmounts(950_000, 2_850_001, 6_650_003);
    uint8[3] memory order = _order(0, 1, 2);

    _buyDefaultTokens(amounts[0], amounts[1], amounts[2]);

    StageOutcome memory outcome = _runThreeWithdrawalStage(
      amounts,
      payouts,
      ROUNDING_PRICE_6,
      10_450_005,
      order
    );

    assertEq(outcome.reserve, 10_450_005);
    assertEq(outcome.totalPayout, 10_450_004);
    assertEq(outcome.dust, 1);
  }

  function testRoundingResultDoesNotDependOnWithdrawalOrder() public {
    uint256[3] memory amounts = _threeAmounts(
      ONE_TOKEN,
      3 * ONE_TOKEN,
      7 * ONE_TOKEN
    );

    uint256[3] memory payouts = _threeAmounts(950_000, 2_850_001, 6_650_003);

    _buyDefaultTokens(3 * amounts[0], 3 * amounts[1], 3 * amounts[2]);

    StageOutcome memory abc = _runThreeWithdrawalStage(
      amounts,
      payouts,
      ROUNDING_PRICE_6,
      10_450_005,
      _order(0, 1, 2)
    );

    StageOutcome memory cab = _runThreeWithdrawalStage(
      amounts,
      payouts,
      ROUNDING_PRICE_6,
      10_450_005,
      _order(2, 0, 1)
    );

    StageOutcome memory bca = _runThreeWithdrawalStage(
      amounts,
      payouts,
      ROUNDING_PRICE_6,
      10_450_005,
      _order(1, 2, 0)
    );

    assertEq(abc.totalPayout, 10_450_004);
    assertEq(cab.totalPayout, abc.totalPayout);
    assertEq(bca.totalPayout, abc.totalPayout);
    assertEq(abc.dust, 1);
    assertEq(cab.dust, abc.dust);
    assertEq(bca.dust, abc.dust);
    assertEq(dollar.balanceOf(address(gate)), 3);
  }

  function testRoundingWithWithdrawAndCancel() public {
    uint256 requestAmount = 2 * ONE_TOKEN;

    _buy(alice, 8e6);
    _buy(bob, 8e6);

    uint256 firstDust = _runClosureStage(true, true, requestAmount);
    uint256 secondDust = _runClosureStage(false, false, requestAmount);
    uint256 thirdDust = _runClosureStage(true, false, requestAmount);
    uint256 fourthDust = _runClosureStage(false, true, requestAmount);

    assertEq(firstDust, 1);
    assertEq(secondDust, firstDust);
    assertEq(thirdDust, firstDust);
    assertEq(fourthDust, firstDust);
    assertEq(dollar.balanceOf(address(gate)), 4);
  }

  function testRoundingDustAccumulatesAcrossStages() public {
    uint256[3] memory firstAmounts = _threeAmounts(
      ONE_TOKEN,
      3 * ONE_TOKEN,
      7 * ONE_TOKEN
    );

    uint256[3] memory firstPayouts = _threeAmounts(
      950_000,
      2_850_001,
      6_650_003
    );

    uint256[3] memory secondAmounts = _threeAmounts(
      ONE_TOKEN,
      2 * ONE_TOKEN,
      4 * ONE_TOKEN
    );

    uint256[3] memory secondPayouts = _threeAmounts(
      900_000,
      1_800_001,
      3_600_003
    );

    _buyDefaultTokens(
      firstAmounts[0] + secondAmounts[0],
      firstAmounts[1] + secondAmounts[1],
      firstAmounts[2] + secondAmounts[2]
    );

    StageOutcome memory first = _runThreeWithdrawalStage(
      firstAmounts,
      firstPayouts,
      ROUNDING_PRICE_6,
      10_450_005,
      _order(0, 1, 2)
    );

    StageOutcome memory second = _runThreeWithdrawalStage(
      secondAmounts,
      secondPayouts,
      SECOND_STAGE_PRICE,
      6_300_006,
      _order(2, 1, 0)
    );

    assertEq(first.totalPayout, 10_450_004);
    assertEq(first.dust, 1);
    assertEq(second.totalPayout, 6_300_004);
    assertEq(second.dust, 2);
    assertEq(dollar.balanceOf(address(gate)), first.dust + second.dust);
  }

  function testRoundingWithSixDecimalDollar() public {
    _buy(alice, 2e6);
    _buy(bob, 2e6);

    _assertTwoRequestRounding(
      IERC20(address(dollar)),
      TwoRequestCase({
        requestAmount: 2 * ONE_TOKEN,
        price: CLOSURE_PRICE,
        scale: 1e12,
        reserve: 3_800_001,
        payout: 1_900_000,
        dust: 1
      })
    );
  }

  function testRoundingWithEightDecimalDollar() public {
    StandardDollar dollar8 = new StandardDollar(
      'Eight Decimal Dollar',
      'USD8',
      8
    );

    uint256 requestAmount = ONE_TOKEN + 1e10;

    _changeDollar(dollar8);
    _buyWithDollar(dollar8, alice, 100_000_001);
    _buyWithDollar(dollar8, bob, 100_000_001);

    _assertTwoRequestRounding(
      IERC20(address(dollar8)),
      TwoRequestCase({
        requestAmount: requestAmount,
        price: ROUNDING_PRICE_8,
        scale: 1e10,
        reserve: 190_000_003,
        payout: 95_000_001,
        dust: 1
      })
    );
  }

  function testRoundingWithEighteenDecimalDollar() public {
    StandardDollar dollar18 = new StandardDollar(
      'Eighteen Decimal Dollar',
      'USD18',
      18
    );

    uint256 requestAmount = ONE_TOKEN + 1;

    _changeDollar(dollar18);
    _buyWithDollar(dollar18, alice, requestAmount);
    _buyWithDollar(dollar18, bob, requestAmount);

    _assertTwoRequestRounding(
      IERC20(address(dollar18)),
      TwoRequestCase({
        requestAmount: requestAmount,
        price: SETTLEMENT_PRICE + 1,
        scale: 1,
        reserve: 1_900_000_000_000_000_003,
        payout: 950_000_000_000_000_001,
        dust: 1
      })
    );
  }

  function testRoundingBoundaryWithoutDust() public {
    _buy(alice, 1e6);
    _buy(bob, 1e6);

    _assertTwoRequestRounding(
      IERC20(address(dollar)),
      TwoRequestCase({
        requestAmount: ONE_TOKEN,
        price: ROUNDING_PRICE_6 - 1,
        scale: DOLLAR_SCALE,
        reserve: 1_900_000,
        payout: 950_000,
        dust: 0
      })
    );
  }

  function testRoundingBoundaryWithDust() public {
    _buy(alice, 1e6);
    _buy(bob, 1e6);

    _assertTwoRequestRounding(
      IERC20(address(dollar)),
      TwoRequestCase({
        requestAmount: ONE_TOKEN,
        price: ROUNDING_PRICE_6,
        scale: DOLLAR_SCALE,
        reserve: 1_900_001,
        payout: 950_000,
        dust: 1
      })
    );
  }

  function testFuzz_RoundingReserveIsNotLessThanTotalPayout(
    uint96[8] memory rawAmounts,
    uint64 rawPrice,
    uint8 rawCount
  ) public {
    uint256 requestCount = _bound(rawCount, 2, 8);
    uint256 settlementPrice = _bound(rawPrice, 9e17, INITIAL_PRICE);
    uint256[8] memory requestAmounts;
    uint256 totalRequested;
    uint256 expectedPayout;

    for (uint256 i = 0; i < requestCount; i++) {
      uint256 requestAmount = _bound(rawAmounts[i], ONE_TOKEN, 100 * ONE_TOKEN);

      requestAmounts[i] = requestAmount;
      totalRequested += requestAmount;

      expectedPayout += _referenceConversion(
        requestAmount,
        settlementPrice,
        DOLLAR_SCALE
      );
    }

    uint256 reserve = _referenceConversion(
      totalRequested,
      settlementPrice,
      DOLLAR_SCALE
    );

    assertEq(expectedPayout <= reserve, true);

    uint256 expectedDust = reserve - expectedPayout;
    uint256 dollarAmount = _ceilDiv(totalRequested, DOLLAR_SCALE);

    _buy(alice, dollarAmount);

    uint256 stageId = gate.currentStageId();
    uint256[8] memory requestIds;

    for (uint256 i = 0; i < requestCount; i++) {
      (, requestIds[i]) = _request(alice, requestAmounts[i]);
    }

    uint256 gateBefore = dollar.balanceOf(address(gate));

    _approveReserve(reserve);
    _completeStage(settlementPrice);
    assertEq(dollar.balanceOf(address(gate)) - gateBefore, reserve);

    uint256 aliceBefore = dollar.balanceOf(alice);

    for (uint256 i = 0; i < requestCount; i++) {
      _withdraw(alice, stageId, requestIds[i]);
    }

    uint256 actualPayout = dollar.balanceOf(alice) - aliceBefore;
    uint256 actualDust = dollar.balanceOf(address(gate)) - gateBefore;

    assertEq(actualPayout, expectedPayout);
    assertEq(actualDust, reserve - expectedPayout);
    assertEq(actualDust, expectedDust);
  }

  function _assertTwoRequestRounding(
    IERC20 selectedDollar,
    TwoRequestCase memory testCase
  ) private {
    (uint256 stageId, uint256 aliceRequestId) = _request(
      alice,
      testCase.requestAmount
    );

    (, uint256 bobRequestId) = _request(bob, testCase.requestAmount);
    uint256 gateBefore = selectedDollar.balanceOf(address(gate));

    _approveReserve(selectedDollar, owner, testCase.reserve);
    _completeStage(testCase.price);

    _assertTwoRequestStage(
      stageId,
      bobRequestId,
      selectedDollar,
      testCase
    );

    assertEq(
      selectedDollar.balanceOf(address(gate)) - gateBefore,
      testCase.reserve
    );

    uint256 aliceBefore = selectedDollar.balanceOf(alice);
    uint256 bobBefore = selectedDollar.balanceOf(bob);

    _withdraw(alice, stageId, aliceRequestId);
    _withdraw(bob, stageId, bobRequestId);

    uint256 alicePayout = selectedDollar.balanceOf(alice) - aliceBefore;
    uint256 bobPayout = selectedDollar.balanceOf(bob) - bobBefore;
    uint256 totalPayout = alicePayout + bobPayout;

    uint256 actualDust =
      selectedDollar.balanceOf(address(gate)) - gateBefore;

    assertEq(alicePayout, testCase.payout);
    assertEq(bobPayout, testCase.payout);
    assertEq(totalPayout, 2 * testCase.payout);
    assertEq(2 * testCase.payout <= testCase.reserve, true);
    assertEq(testCase.reserve - totalPayout, testCase.dust);
    assertEq(actualDust, testCase.dust);
  }

  function _assertTwoRequestStage(
    uint256 stageId,
    uint256 lastRequestId,
    IERC20 selectedDollar,
    TwoRequestCase memory testCase
  ) private view {
    (
      uint256 stagePrice,
      IDollar stageDollar,
      uint256 stageScale,
      uint256 stageTokenAmount,
      uint256 requestId
    ) = gate.stages(stageId);

    assertEq(stagePrice, testCase.price);
    assertEq(address(stageDollar), address(selectedDollar));
    assertEq(stageScale, testCase.scale);
    assertEq(stageTokenAmount, 2 * testCase.requestAmount);
    assertEq(requestId, lastRequestId);
  }

  function _runThreeWithdrawalStage(
    uint256[3] memory amounts,
    uint256[3] memory expectedPayouts,
    uint256 price,
    uint256 expectedReserve,
    uint8[3] memory order
  ) private returns (StageOutcome memory outcome) {
    address[3] memory authors;
    authors[0] = alice;
    authors[1] = bob;
    authors[2] = charlie;

    uint256 stageId = gate.currentStageId();
    uint256[3] memory requestIds;

    for (uint256 i = 0; i < authors.length; i++) {
      (, requestIds[i]) = _request(authors[i], amounts[i]);
    }

    uint256 gateBefore = dollar.balanceOf(address(gate));

    _approveReserve(expectedReserve);
    _completeStage(price);

    outcome.reserve = dollar.balanceOf(address(gate)) - gateBefore;

    uint256[3] memory balancesBefore;

    for (uint256 i = 0; i < authors.length; i++) {
      balancesBefore[i] = dollar.balanceOf(authors[i]);
    }

    for (uint256 i = 0; i < order.length; i++) {
      uint256 requestIndex = order[i];

      _withdraw(
        authors[requestIndex],
        stageId,
        requestIds[requestIndex]
      );
    }

    for (uint256 i = 0; i < authors.length; i++) {
      uint256 actualPayout =
        dollar.balanceOf(authors[i]) - balancesBefore[i];

      assertEq(actualPayout, expectedPayouts[i]);

      outcome.totalPayout += actualPayout;
    }

    outcome.dust = dollar.balanceOf(address(gate)) - gateBefore;

    assertEq(outcome.reserve, expectedReserve);
    assertEq(outcome.totalPayout <= outcome.reserve, true);
    assertEq(outcome.reserve - outcome.totalPayout, outcome.dust);
  }

  function _runClosureStage(
    bool withdrawFirst,
    bool withdrawSecond,
    uint256 requestAmount
  ) private returns (uint256 dust) {
    (uint256 stageId, uint256 aliceRequestId) = _request(
      alice,
      requestAmount
    );

    (, uint256 bobRequestId) = _request(bob, requestAmount);

    uint256 gateBefore = dollar.balanceOf(address(gate));

    _approveReserve(3_800_001);
    _completeStage(CLOSURE_PRICE);
    assertEq(dollar.balanceOf(address(gate)) - gateBefore, 3_800_001);

    _closeAndAssertTransfer(
      alice,
      stageId,
      aliceRequestId,
      withdrawFirst,
      1_900_000
    );

    _closeAndAssertTransfer(
      bob,
      stageId,
      bobRequestId,
      withdrawSecond,
      1_900_000
    );

    dust = dollar.balanceOf(address(gate)) - gateBefore;

    assertEq(dust, 1);
  }

  function _closeAndAssertTransfer(
    address author,
    uint256 stageId,
    uint256 requestId,
    bool useWithdraw,
    uint256 expectedAmount
  ) private {
    address receiver = useWithdraw ? author : address(fund);
    uint256 receiverBefore = dollar.balanceOf(receiver);
    uint256 gateBefore = dollar.balanceOf(address(gate));

    if (useWithdraw) {
      _withdraw(author, stageId, requestId);
    } else {
      _cancel(author, stageId, requestId);
    }

    assertEq(
      dollar.balanceOf(receiver) - receiverBefore,
      expectedAmount
    );

    assertEq(
      gateBefore - dollar.balanceOf(address(gate)),
      expectedAmount
    );
  }

  function _buyDefaultTokens(
    uint256 aliceTokens,
    uint256 bobTokens,
    uint256 charlieTokens
  ) private {
    _buy(alice, aliceTokens / DOLLAR_SCALE);
    _buy(bob, bobTokens / DOLLAR_SCALE);
    _buy(charlie, charlieTokens / DOLLAR_SCALE);
  }

  function _changeDollar(StandardDollar selectedDollar) private {
    vm.prank(owner);
    fund.changeDollar(address(selectedDollar));
  }

  function _withdraw(
    address author,
    uint256 stageId,
    uint256 requestId
  ) private {
    vm.prank(author);
    gate.withdraw(stageId, requestId);
  }

  function _cancel(
    address author,
    uint256 stageId,
    uint256 requestId
  ) private {
    vm.prank(author);
    gate.cancelWithdrawalRequest(stageId, requestId);
  }

  function _threeAmounts(
    uint256 first,
    uint256 second,
    uint256 third
  ) private pure returns (uint256[3] memory values) {
    values[0] = first;
    values[1] = second;
    values[2] = third;
  }

  function _order(
    uint8 first,
    uint8 second,
    uint8 third
  ) private pure returns (uint8[3] memory values) {
    values[0] = first;
    values[1] = second;
    values[2] = third;
  }

  function _referenceConversion(
    uint256 tokenAmount,
    uint256 price,
    uint256 scale
  ) private pure returns (uint256) {
    return tokenAmount * price / (ONE_TOKEN * scale);
  }

  function _bound(
    uint256 value,
    uint256 minValue,
    uint256 maxValue
  ) private pure returns (uint256) {
    return minValue + value % (maxValue - minValue + 1);
  }

  function _ceilDiv(
    uint256 value,
    uint256 divisor
  ) private pure returns (uint256) {
    return (value + divisor - 1) / divisor;
  }
}
