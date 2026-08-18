// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';

import '../contracts/WithStaff.sol';
import './mocks/StandardDollar.sol';
import './helpers/SystemFixture.sol';
import '../contracts/DepositStore.sol';

contract EmergencyDollarChangeTest is SystemFixture {
  struct DollarState {
    uint256 totalSupply;
    uint256 aliceBalance;
    uint256 bobBalance;
    uint256 fundBalance;
    uint256 gateBalance;
    uint256 aliceAllowance;
    uint256 bobAllowance;
    uint256 fundAllowance;
  }

  struct FundTokenState {
    uint256 totalSupply;
    uint256 aliceBalance;
    uint256 bobBalance;
    uint256 gateBalance;
    uint256 aliceAllowance;
    uint256 bobAllowance;
  }

  struct StageState {
    uint256 price;
    address stageDollar;
    uint256 dollarScale;
    uint256 tokenAmount;
    uint256 requestId;
  }

  function testOwnerChangesDollarWithoutMigratingState() public {
    StandardDollar newDollar = _newDollar('Dollar 18', 'USD18', 18);

    _buy(alice, 20e6);

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      4 * ONE_TOKEN
    );

    vm.prank(alice);
    dollar.approve(address(gate), 17e6);

    _approveReserveWithEvent(IERC20(address(dollar)), owner, 13e6);

    newDollar.mint(alice, 21e18);
    newDollar.mint(bob, 7e18);
    newDollar.mint(address(fund), 15e18);
    newDollar.mint(address(gate), 3e18);
    vm.prank(alice);
    newDollar.approve(address(gate), 9e18);

    _approveReserveWithEvent(newDollar, owner, 6e18);

    DollarState memory oldDollarBefore
      = _getDollarState(IERC20(address(dollar)));

    DollarState memory newDollarBefore = _getDollarState(newDollar);
    FundTokenState memory fundTokenBefore = _getFundTokenState();
    StageState memory stageBefore = _getStage(stageId);
    uint256 entryPriceBefore = gate.entryPrice();
    uint256 priceChangeTimeBefore = gate.priceChangeTime();
    uint256 currentStageBefore = gate.currentStageId();

    _changeDollar(owner, newDollar);
    assertEq(address(gate.dollar()), address(newDollar));
    assertEq(gate.entryPrice(), entryPriceBefore);
    assertEq(gate.priceChangeTime(), priceChangeTimeBefore);
    assertEq(gate.currentStageId(), currentStageBefore);
    _assertStage(stageId, stageBefore);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);
    _assertDollarState(newDollar, newDollarBefore);
    _assertFundTokenState(fundTokenBefore);
    _cancelWithEvent(alice, stageId, requestId);
  }

  function testDollarChangeAccessAtBothLayers() public {
    StandardDollar dollar18 = _newDollar('Dollar 18', 'USD18', 18);
    StandardDollar dollar8 = _newDollar('Dollar 8', 'USD8', 8);

    vm.expectRevert(WithStaff.SenderIsNotStaff.selector);
    vm.prank(stranger);
    fund.changeDollar(address(dollar18));

    assertEq(address(gate.dollar()), address(dollar));
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.currentStageId(), 1);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), false);

    vm.expectRevert(
      abi.encodeWithSelector(
        Ownable.OwnableUnauthorizedAccount.selector,
        owner
      )
    );

    vm.prank(owner);
    gate.changeDollar(IDollar(address(dollar18)));

    assertEq(address(gate.dollar()), address(dollar));
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.currentStageId(), 1);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), false);

    uint256 claimableAt = block.timestamp + 1;

    _scheduleSuccessor(owner, successor, claimableAt);

    vm.warp(claimableAt);

    _claimPrivileges(successor, claimableAt);
    _changeDollar(successor, dollar18);
    assertEq(address(gate.dollar()), address(dollar18));
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);

    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferStarted(owner, newOwner);

    vm.prank(owner);
    fund.transferOwnership(newOwner);
    vm.expectEmit(true, true, false, false, address(fund));

    emit OwnershipTransferred(owner, newOwner);

    vm.prank(newOwner);
    fund.acceptOwnership();

    _changeDollar(newOwner, dollar8);

    vm.expectRevert(
      abi.encodeWithSelector(
        Ownable.OwnableUnauthorizedAccount.selector,
        newOwner
      )
    );

    vm.prank(newOwner);
    gate.changeDollar(IDollar(address(dollar18)));

    assertEq(fund.owner(), newOwner);
    assertEq(gate.owner(), address(fund));
    assertEq(fund.admins(successor), true);
    assertEq(address(gate.dollar()), address(dollar8));
  }

  function testEighteenDecimalBuyRecalculatesScaleAndRoundsDown() public {
    StandardDollar dollar18 = _newDollar('Dollar 18', 'USD18', 18);
    uint256 newPrice = 104e16;
    uint256 changeTime = gate.priceChangeTime() + 7 days;

    vm.warp(changeTime);
    vm.expectEmit(false, false, false, true, address(gate));

    emit EntryPriceChanged(INITIAL_PRICE, newPrice);

    vm.prank(owner);
    fund.changeEntryPrice(newPrice);

    DollarState memory oldDollarBefore
      = _getDollarState(IERC20(address(dollar)));

    _changeDollar(owner, dollar18);

    uint256 dollarAmount = 101e18 + 1;
    uint256 expectedTokens = 97_115_384_615_384_615_385;

    assertEq(
      Math.mulDiv(dollarAmount, ONE_TOKEN, newPrice),
      expectedTokens
    );

    uint256 boughtTokens = _buyDollarWithEvent(
      dollar18,
      alice,
      dollarAmount
    );

    assertEq(boughtTokens, expectedTokens);
    assertEq(token.balanceOf(alice), expectedTokens);
    assertEq(token.totalSupply(), expectedTokens);
    assertEq(dollar18.balanceOf(alice), 0);
    assertEq(dollar18.balanceOf(address(fund)), dollarAmount);
    assertEq(dollar18.balanceOf(address(gate)), 0);
    assertEq(dollar18.allowance(alice, address(gate)), 0);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);

    uint256 requestAmount = 40 * ONE_TOKEN;
    (uint256 stageId, ) = _requestWithEvent(alice, requestAmount);
    uint256 reserve = _reserveAmount(requestAmount, SETTLEMENT_PRICE, 1);

    _approveReserveWithEvent(dollar18, owner, reserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory completed = _getStage(stageId);

    assertEq(completed.price, SETTLEMENT_PRICE);
    assertEq(completed.stageDollar, address(dollar18));
    assertEq(completed.dollarScale, 1);
    assertEq(completed.tokenAmount, requestAmount);
    assertEq(completed.requestId, 1);
  }

  function testOpenRequestSettlesInDollarSelectedAtCompletion() public {
    StandardDollar dollar18 = _newDollar('Dollar 18', 'USD18', 18);
    uint256 requestAmount = 40 * ONE_TOKEN;

    _buy(alice, 100e6);

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      requestAmount
    );

    DollarState memory oldDollarBefore
      = _getDollarState(IERC20(address(dollar)));

    _changeDollar(owner, dollar18);

    uint256 reserve = _reserveAmount(requestAmount, SETTLEMENT_PRICE, 1);

    dollar18.mint(address(fund), reserve);

    _approveReserveWithEvent(dollar18, owner, reserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory completed = _getStage(stageId);

    assertEq(completed.price, SETTLEMENT_PRICE);
    assertEq(completed.stageDollar, address(dollar18));
    assertEq(completed.dollarScale, 1);
    assertEq(completed.tokenAmount, requestAmount);
    assertEq(completed.requestId, requestId);
    assertEq(dollar18.balanceOf(address(fund)), 0);
    assertEq(dollar18.balanceOf(address(gate)), reserve);
    assertEq(dollar18.allowance(address(fund), address(gate)), 0);
    _withdrawWithEvent(alice, stageId, requestId);
    assertEq(dollar18.balanceOf(alice), reserve);
    assertEq(dollar18.balanceOf(address(fund)), 0);
    assertEq(dollar18.balanceOf(address(gate)), 0);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), 60 * ONE_TOKEN);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);

    completed = _getStage(stageId);

    assertEq(completed.tokenAmount, 0);
  }

  function testCompletedStageKeepsOldDollarAfterChange() public {
    StandardDollar dollar18 = _newDollar('Dollar 18', 'USD18', 18);
    uint256 aliceRequest = 40 * ONE_TOKEN;
    uint256 bobRequest = 60 * ONE_TOKEN;

    _buy(alice, 100e6);
    _buy(bob, 100e6);

    (uint256 stageId, uint256 aliceRequestId) = _requestWithEvent(
      alice,
      aliceRequest
    );

    (, uint256 bobRequestId) = _requestWithEvent(bob, bobRequest);

    uint256 reserve = _reserveAmount(
      aliceRequest + bobRequest,
      SETTLEMENT_PRICE
    );

    _approveReserveWithEvent(IERC20(address(dollar)), owner, reserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory stageBeforeChange = _getStage(stageId);

    dollar18.mint(alice, 3e18);
    dollar18.mint(bob, 5e18);
    dollar18.mint(address(fund), 7e18);
    dollar18.mint(address(gate), 11e18);

    DollarState memory newDollarBefore = _getDollarState(dollar18);

    _changeDollar(owner, dollar18);
    _assertStage(stageId, stageBeforeChange);
    _withdrawWithEvent(alice, stageId, aliceRequestId);
    _cancelWithEvent(bob, stageId, bobRequestId);

    StageState memory stageAfter = _getStage(stageId);

    assertEq(stageAfter.price, SETTLEMENT_PRICE);
    assertEq(stageAfter.stageDollar, address(dollar));
    assertEq(stageAfter.dollarScale, DOLLAR_SCALE);
    assertEq(stageAfter.tokenAmount, 0);
    assertEq(stageAfter.requestId, bobRequestId);
    assertEq(dollar.balanceOf(alice), 938e6);
    assertEq(dollar.balanceOf(bob), 900e6);
    assertEq(dollar.balanceOf(address(fund)), 162e6);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(bob), 99 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), 159 * ONE_TOKEN);
    _assertDollarState(dollar18, newDollarBefore);
  }

  function testStagesWithDifferentDollarsSettleIndependentlyInReverseOrder()
    public
  {
    StandardDollar dollar18 = _newDollar('Dollar 18', 'USD18', 18);
    uint256 requestAmount = 10 * ONE_TOKEN;

    _buy(alice, 20e6);

    (uint256 oldStageId, uint256 oldRequestId) = _requestWithEvent(
      alice,
      requestAmount
    );

    uint256 oldReserve = _reserveAmount(
      requestAmount,
      SETTLEMENT_PRICE,
      DOLLAR_SCALE
    );

    _approveReserveWithEvent(IERC20(address(dollar)), owner, oldReserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);
    _changeDollar(owner, dollar18);
    _buyDollarWithEvent(dollar18, bob, 20e18);

    (uint256 newStageId, uint256 newRequestId) = _requestWithEvent(
      bob,
      requestAmount
    );

    uint256 newReserve = _reserveAmount(
      requestAmount,
      SETTLEMENT_PRICE,
      1
    );

    _approveReserveWithEvent(dollar18, owner, newReserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory oldStage = _getStage(oldStageId);
    StageState memory newStage = _getStage(newStageId);

    assertEq(oldStage.stageDollar, address(dollar));
    assertEq(oldStage.dollarScale, DOLLAR_SCALE);
    assertEq(newStage.stageDollar, address(dollar18));
    assertEq(newStage.dollarScale, 1);
    assertEq(dollar.balanceOf(address(gate)), oldReserve);
    assertEq(dollar18.balanceOf(address(gate)), newReserve);

    DollarState memory oldBeforeNewWithdrawal
      = _getDollarState(IERC20(address(dollar)));

    _withdrawWithEvent(bob, newStageId, newRequestId);
    assertEq(dollar18.balanceOf(bob), newReserve);
    assertEq(dollar18.balanceOf(address(gate)), 0);
    _assertDollarState(IERC20(address(dollar)), oldBeforeNewWithdrawal);

    DollarState memory newBeforeOldWithdrawal = _getDollarState(dollar18);

    _withdrawWithEvent(alice, oldStageId, oldRequestId);
    assertEq(dollar.balanceOf(alice), 989_500_000);
    assertEq(dollar.balanceOf(address(gate)), 0);
    _assertDollarState(dollar18, newBeforeOldWithdrawal);

    oldStage.tokenAmount = 0;
    newStage.tokenAmount = 0;

    _assertStage(oldStageId, oldStage);
    _assertStage(newStageId, newStage);
  }

  function testCompletionUsesNewAllowanceAndIsAtomic() public {
    StandardDollar dollar18 = _newDollar('Dollar 18', 'USD18', 18);
    uint256 requestAmount = 40 * ONE_TOKEN;

    _buy(alice, 100e6);

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      requestAmount
    );

    uint256 oldReserve = _reserveAmount(
      requestAmount,
      SETTLEMENT_PRICE,
      DOLLAR_SCALE
    );

    _approveReserveWithEvent(IERC20(address(dollar)), owner, oldReserve);
    _changeDollar(owner, dollar18);

    uint256 newReserve = _reserveAmount(
      requestAmount,
      SETTLEMENT_PRICE,
      1
    );

    dollar18.mint(address(fund), newReserve);

    StageState memory stageBefore = _getStage(stageId);

    DollarState memory oldDollarBefore
      = _getDollarState(IERC20(address(dollar)));

    DollarState memory newDollarBefore = _getDollarState(dollar18);
    FundTokenState memory fundTokenBefore = _getFundTokenState();

    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        address(gate),
        0,
        newReserve
      )
    );

    _completeStage(owner, SETTLEMENT_PRICE);
    assertEq(gate.currentStageId(), stageId);
    _assertStage(stageId, stageBefore);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);
    _assertDollarState(dollar18, newDollarBefore);
    _assertFundTokenState(fundTokenBefore);
    _approveReserveWithEvent(dollar18, owner, newReserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory completed = _getStage(stageId);

    assertEq(gate.currentStageId(), stageId + 1);
    assertEq(completed.price, SETTLEMENT_PRICE);
    assertEq(completed.stageDollar, address(dollar18));
    assertEq(completed.dollarScale, 1);
    assertEq(completed.tokenAmount, requestAmount);
    assertEq(completed.requestId, requestId);
    assertEq(dollar.allowance(address(fund), address(gate)), oldReserve);
    assertEq(dollar18.allowance(address(fund), address(gate)), 0);
    _withdrawWithEvent(alice, stageId, requestId);
    assertEq(dollar18.balanceOf(alice), newReserve);
    assertEq(dollar18.balanceOf(address(gate)), 0);
  }

  function testSuccessorCanRestoreSettlementWithoutBecomingOwner() public {
    StandardDollar dollar18 = _newDollar('Emergency Dollar', 'EUSD', 18);
    uint256 claimableAt = block.timestamp + 3 days;
    uint256 requestAmount = 40 * ONE_TOKEN;

    _scheduleSuccessor(owner, successor, claimableAt);
    _buy(alice, 100e6);

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      requestAmount
    );

    vm.warp(claimableAt);

    _claimPrivileges(successor, claimableAt);
    _changeDollar(successor, dollar18);

    uint256 reserve = _reserveAmount(requestAmount, SETTLEMENT_PRICE, 1);

    vm.prank(successor);
    dollar18.mint(address(fund), reserve);

    _approveReserveWithEvent(dollar18, successor, reserve);
    _completeStageWithEvent(successor, SETTLEMENT_PRICE);
    _withdrawWithEvent(alice, stageId, requestId);
    assertEq(fund.owner(), owner);
    assertEq(fund.pendingOwner(), address(0));
    assertEq(fund.admins(successor), true);
    assertEq(address(gate.dollar()), address(dollar18));
    assertEq(gate.owner(), address(fund));
    assertEq(dollar18.balanceOf(alice), reserve);
    assertEq(dollar18.balanceOf(address(fund)), 0);
    assertEq(dollar18.balanceOf(address(gate)), 0);
    assertEq(dollar.balanceOf(alice), 900e6);
    assertEq(dollar.balanceOf(address(fund)), 100e6);
    assertEq(dollar.balanceOf(address(gate)), 0);
    assertEq(token.balanceOf(alice), 60 * ONE_TOKEN);
    assertEq(token.balanceOf(address(gate)), 0);
    assertEq(token.totalSupply(), 60 * ONE_TOKEN);
  }

  function testLastOfMultipleDollarChangesWinsForOpenStage() public {
    StandardDollar dollar8 = _newDollar('Dollar B', 'USDB', 8);
    StandardDollar dollar18 = _newDollar('Dollar C', 'USDC', 18);
    uint256 requestAmount = 40 * ONE_TOKEN;

    _buy(alice, 100e6);

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      requestAmount
    );

    dollar8.mint(alice, 3e8);
    dollar8.mint(address(fund), 7e8);
    vm.prank(alice);
    dollar8.approve(address(gate), 2e8);

    _approveReserveWithEvent(dollar8, owner, 5e8);
    _changeDollar(owner, dollar8);
    _changeDollar(owner, dollar18);

    DollarState memory oldDollarBefore
      = _getDollarState(IERC20(address(dollar)));

    DollarState memory middleDollarBefore = _getDollarState(dollar8);
    uint256 reserve = _reserveAmount(requestAmount, SETTLEMENT_PRICE, 1);

    dollar18.mint(address(fund), reserve);

    _approveReserveWithEvent(dollar18, owner, reserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory completed = _getStage(stageId);

    assertEq(completed.stageDollar, address(dollar18));
    assertEq(completed.dollarScale, 1);
    assertEq(dollar18.balanceOf(address(gate)), reserve);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);
    _assertDollarState(dollar8, middleDollarBefore);
    _withdrawWithEvent(alice, stageId, requestId);
    assertEq(dollar18.balanceOf(alice), reserve);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);
    _assertDollarState(dollar8, middleDollarBefore);
  }

  function testSettingCurrentDollarAgainEmitsAndPreservesState() public {
    StandardDollar dollar18 = _newDollar('Dollar 18', 'USD18', 18);

    _changeDollar(owner, dollar18);

    dollar18.mint(alice, 12e18);
    dollar18.mint(address(fund), 8e18);
    vm.prank(alice);
    dollar18.approve(address(gate), 3e18);

    _approveReserveWithEvent(dollar18, owner, 4e18);

    DollarState memory oldDollarBefore
      = _getDollarState(IERC20(address(dollar)));

    DollarState memory currentDollarBefore = _getDollarState(dollar18);
    FundTokenState memory fundTokenBefore = _getFundTokenState();
    StageState memory stageBefore = _getStage(gate.currentStageId());
    uint256 entryPriceBefore = gate.entryPrice();
    uint256 priceChangeTimeBefore = gate.priceChangeTime();
    uint256 currentStageBefore = gate.currentStageId();

    _changeDollar(owner, dollar18);
    assertEq(address(gate.dollar()), address(dollar18));
    assertEq(gate.entryPrice(), entryPriceBefore);
    assertEq(gate.priceChangeTime(), priceChangeTimeBefore);
    assertEq(gate.currentStageId(), currentStageBefore);
    _assertStage(currentStageBefore, stageBefore);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);
    _assertDollarState(dollar18, currentDollarBefore);
    _assertFundTokenState(fundTokenBefore);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory completed = _getStage(currentStageBefore);

    assertEq(completed.price, SETTLEMENT_PRICE);
    assertEq(completed.stageDollar, address(dollar18));
    assertEq(completed.dollarScale, 1);
    assertEq(completed.tokenAmount, 0);
    assertEq(completed.requestId, 0);
  }

  function testEightDecimalDollarUsesScale1e10() public {
    StandardDollar dollar8 = _newDollar('Dollar 8', 'USD8', 8);
    uint256 requestAmount = 10 * ONE_TOKEN;

    DollarState memory oldDollarBefore
      = _getDollarState(IERC20(address(dollar)));

    _changeDollar(owner, dollar8);
    _buyDollarWithEvent(dollar8, alice, 20e8);

    (uint256 stageId, uint256 requestId) = _requestWithEvent(
      alice,
      requestAmount
    );

    uint256 reserve = _reserveAmount(requestAmount, SETTLEMENT_PRICE, 1e10);

    _approveReserveWithEvent(dollar8, owner, reserve);
    _completeStageWithEvent(owner, SETTLEMENT_PRICE);

    StageState memory completed = _getStage(stageId);

    assertEq(completed.price, SETTLEMENT_PRICE);
    assertEq(completed.stageDollar, address(dollar8));
    assertEq(completed.dollarScale, 1e10);
    assertEq(completed.tokenAmount, requestAmount);
    assertEq(completed.requestId, requestId);
    assertEq(dollar8.balanceOf(address(gate)), reserve);
    _withdrawWithEvent(alice, stageId, requestId);
    assertEq(dollar8.balanceOf(alice), reserve);
    assertEq(dollar8.balanceOf(address(gate)), 0);
    _assertDollarState(IERC20(address(dollar)), oldDollarBefore);
  }

  function _newDollar(
    string memory name,
    string memory symbol,
    uint8 decimals
  ) private returns (StandardDollar) {
    return new StandardDollar(name, symbol, decimals);
  }

  function _changeDollar(address staff, StandardDollar newDollar) private {
    vm.expectEmit(true, true, false, false, address(gate));

    emit DollarChanged(
      IDollar(address(newDollar)),
      uint256(newDollar.decimals())
    );

    vm.prank(staff);
    fund.changeDollar(address(newDollar));
  }

  function _scheduleSuccessor(
    address staff,
    address scheduledSuccessor,
    uint256 claimableAt
  ) private {
    uint256 previousClaimableAt = fund.successors(scheduledSuccessor);

    vm.expectEmit(true, true, false, true, address(fund));

    emit SuccessorScheduled(
      scheduledSuccessor,
      previousClaimableAt,
      claimableAt,
      staff
    );

    vm.prank(staff);
    fund.scheduleSuccessor(scheduledSuccessor, claimableAt);
  }

  function _claimPrivileges(address admin, uint256 claimableAt) private {
    vm.expectEmit(true, false, false, true, address(fund));

    emit AdminActivated(admin, claimableAt);

    vm.prank(admin);
    fund.claimPrivileges();
  }

  function _buyDollarWithEvent(
    StandardDollar selectedDollar,
    address buyer,
    uint256 dollarAmount
  ) private returns (uint256 tokenAmount) {
    uint256 scale = _dollarScale(selectedDollar.decimals());

    tokenAmount =
      Math.mulDiv(dollarAmount, ONE_TOKEN * scale, gate.entryPrice());

    selectedDollar.mint(buyer, dollarAmount);
    vm.prank(buyer);
    selectedDollar.approve(address(gate), dollarAmount);
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

    (, , , , uint256 previousRequestId) = gate.stages(stageId);

    requestId = previousRequestId + 1;

    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestOpened(author, stageId, requestId);

    (uint256 openedStageId, uint256 openedRequestId)
      = _request(author,tokenAmount);

    assertEq(openedStageId, stageId);
    assertEq(openedRequestId, requestId);
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

  function _completeStageWithEvent(address staff, uint256 price) private {
    uint256 stageId = gate.currentStageId();

    vm.expectEmit(false, false, false, true, address(gate));

    emit StageCompleted(stageId);

    _completeStage(staff, price);
  }

  function _withdrawWithEvent(
    address author,
    uint256 stageId,
    uint256 requestId
  ) private {
    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestClosed(author, stageId, requestId);

    vm.prank(author);
    gate.withdraw(stageId, requestId);
  }

  function _cancelWithEvent(
    address author,
    uint256 stageId,
    uint256 requestId
  ) private {
    vm.expectEmit(true, false, false, true, address(gate));

    emit RequestClosed(author, stageId, requestId);

    vm.prank(author);
    gate.cancelWithdrawalRequest(stageId, requestId);
  }

  function _getDollarState(
    IERC20 selectedDollar
  ) private view returns (DollarState memory state) {
    state.totalSupply = selectedDollar.totalSupply();
    state.aliceBalance = selectedDollar.balanceOf(alice);
    state.bobBalance = selectedDollar.balanceOf(bob);
    state.fundBalance = selectedDollar.balanceOf(address(fund));
    state.gateBalance = selectedDollar.balanceOf(address(gate));
    state.aliceAllowance = selectedDollar.allowance(alice, address(gate));
    state.bobAllowance = selectedDollar.allowance(bob, address(gate));
    state.fundAllowance = selectedDollar.allowance(address(fund),address(gate));
  }

  function _assertDollarState(
    IERC20 selectedDollar,
    DollarState memory expected
  ) private view {
    DollarState memory actual = _getDollarState(selectedDollar);

    assertEq(actual.totalSupply, expected.totalSupply);
    assertEq(actual.aliceBalance, expected.aliceBalance);
    assertEq(actual.bobBalance, expected.bobBalance);
    assertEq(actual.fundBalance, expected.fundBalance);
    assertEq(actual.gateBalance, expected.gateBalance);
    assertEq(actual.aliceAllowance, expected.aliceAllowance);
    assertEq(actual.bobAllowance, expected.bobAllowance);
    assertEq(actual.fundAllowance, expected.fundAllowance);
  }

  function _getFundTokenState()
    private
    view
    returns (FundTokenState memory state)
  {
    state.totalSupply = token.totalSupply();
    state.aliceBalance = token.balanceOf(alice);
    state.bobBalance = token.balanceOf(bob);
    state.gateBalance = token.balanceOf(address(gate));
    state.aliceAllowance = token.allowance(alice, address(gate));
    state.bobAllowance = token.allowance(bob, address(gate));
  }

  function _assertFundTokenState(
    FundTokenState memory expected
  ) private view {
    FundTokenState memory actual = _getFundTokenState();

    assertEq(actual.totalSupply, expected.totalSupply);
    assertEq(actual.aliceBalance, expected.aliceBalance);
    assertEq(actual.bobBalance, expected.bobBalance);
    assertEq(actual.gateBalance, expected.gateBalance);
    assertEq(actual.aliceAllowance, expected.aliceAllowance);
    assertEq(actual.bobAllowance, expected.bobAllowance);
  }

  function _getStage(
    uint256 stageId
  ) private view returns (StageState memory state) {
    IDollar stageDollar;

    (
      state.price,
      stageDollar,
      state.dollarScale,
      state.tokenAmount,
      state.requestId
    ) = gate.stages(stageId);

    state.stageDollar = address(stageDollar);
  }

  function _assertStage(
    uint256 stageId,
    StageState memory expected
  ) private view {
    StageState memory actual = _getStage(stageId);

    assertEq(actual.price, expected.price);
    assertEq(actual.stageDollar, expected.stageDollar);
    assertEq(actual.dollarScale, expected.dollarScale);
    assertEq(actual.tokenAmount, expected.tokenAmount);
    assertEq(actual.requestId, expected.requestId);
  }
}
