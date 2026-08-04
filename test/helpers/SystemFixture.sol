// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { HardhatTest } from './HardhatTest.sol';
import { Gate } from '../../contracts/Gate.sol';
import { MockDollar } from '../mocks/MockDollar.sol';
import { Token } from '../../contracts/FundToken.sol';
import { Fund, IGate } from '../../contracts/PersonalFund.sol';

abstract contract SystemFixture is HardhatTest {
  uint256 internal constant ONE_TOKEN = 1e18;
  uint256 internal constant DOLLAR_SCALE = 1e12;
  uint256 internal constant INITIAL_PRICE = 1e18;
  uint256 internal constant BOB_DOLLARS = 1_000e6;
  uint256 internal constant ALICE_DOLLARS = 1_000e6;
  uint256 internal constant SETTLEMENT_PRICE = 95e16;
  string internal constant CONTRACT_URI = 'ipfs://fund';

  event Bought(
    address indexed buyer,
    uint256 dollarAmount,
    uint256 tokenAmount
  );

  event RequestOpened(
    address indexed author,
    uint256 stageId,
    uint256 requestId
  );

  event RequestClosed(
    address indexed author,
    uint256 stageId,
    uint256 requestId
  );

  event ContractURIUpdated();
  event StageCompleted(uint256 id);
  event Executed(address indexed target);
  event EntryPriceChanged(uint256 oldPrice, uint256 newPrice);
  event Sacrificed(address indexed author, uint256 tokenAmount);

  Gate internal gate;
  Fund internal fund;
  address internal bob;
  Token internal token;
  address internal owner;
  address internal alice;
  address internal stranger;
  MockDollar internal dollar;

  function setUp() public virtual {
    owner = makeAddr('owner');
    alice = makeAddr('alice');
    bob = makeAddr('bob');
    stranger = makeAddr('stranger');

    vm.startPrank(owner);

    dollar = new MockDollar();
    token = new Token('Fund Token', 'FUND');
    gate = new Gate(INITIAL_PRICE, address(dollar), address(token));
    fund = new Fund(IGate(address(gate)), CONTRACT_URI);

    token.transferOwnership(address(gate));
    gate.transferOwnership(address(fund));
    dollar.mint(alice, ALICE_DOLLARS);
    dollar.mint(bob, BOB_DOLLARS);
    vm.stopPrank();
  }

  function _buy(
    address buyer,
    uint256 dollarAmount
  ) internal returns (uint256 tokenAmount) {
    tokenAmount = _dollarsToTokens(dollarAmount, gate.entryPrice());

    vm.startPrank(buyer);
    dollar.approve(address(gate), dollarAmount);
    gate.buy(dollarAmount);
    vm.stopPrank();
  }

  function _request(
    address author,
    uint256 tokenAmount
  ) internal returns (uint256 stageId, uint256 requestId) {
    stageId = gate.currentStageId();

    vm.prank(author);
    gate.requestWithdrawal(tokenAmount);

    (, , , , requestId) = gate.stages(stageId);
  }

  function _approveReserve(uint256 amount) internal {
    bytes memory data = abi.encodeCall(IERC20.approve, (address(gate), amount));

    vm.prank(owner);
    fund.execute(address(dollar), 0, data);
  }

  function _completeStage(uint256 price) internal {
    vm.prank(owner);
    fund.completeStage(price);
  }

  function _approveAndComplete(
    uint256 tokenAmount,
    uint256 price
  ) internal returns (uint256 reserve) {
    reserve = _reserveAmount(tokenAmount, price);

    _approveReserve(reserve);
    _completeStage(price);
  }

  function _dollarsToTokens(
    uint256 dollarAmount,
    uint256 price
  ) internal pure returns (uint256) {
    return Math.mulDiv(dollarAmount, ONE_TOKEN * DOLLAR_SCALE, price);
  }

  function _tokensToDollars(
    uint256 tokenAmount,
    uint256 price
  ) internal pure returns (uint256) {
    return Math.mulDiv(tokenAmount, price, ONE_TOKEN * DOLLAR_SCALE);
  }

  function _reserveAmount(
    uint256 tokenAmount,
    uint256 price
  ) internal pure returns (uint256) {
    return _tokensToDollars(tokenAmount, price);
  }
}
