// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './HardhatTest.sol';
import '../mocks/MockDollar.sol';
import '../../contracts/Gate.sol';
import '../mocks/StandardDollar.sol';
import '../../contracts/FundToken.sol';
import '../../contracts/PersonalFund.sol';

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

  event SuccessorScheduled(
    address indexed successor,
    uint256 previousClaimableAt,
    uint256 claimableAt,
    address indexed scheduledBy
  );

  event SuccessorRemoved(
    address indexed successor,
    uint256 claimableAt,
    address indexed removedBy
  );

  event AdminActivated(address indexed admin, uint256 claimableAt);
  event AdminRemoved(address indexed admin);
  event DollarChanged(IDollar indexed newDollar, uint256 indexed decimals);

  event OwnershipTransferStarted(
    address indexed previousOwner,
    address indexed newOwner
  );

  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

  Gate internal gate;
  Fund internal fund;
  address internal bob;
  Token internal token;
  address internal owner;
  address internal alice;
  address internal stranger;
  address internal newOwner;
  MockDollar internal dollar;
  address internal successor;
  address internal secondSuccessor;

  function setUp() public virtual {
    bob = makeAddr('bob');
    owner = makeAddr('owner');
    alice = makeAddr('alice');
    newOwner = makeAddr('newOwner');
    stranger = makeAddr('stranger');
    successor = makeAddr('successor');
    secondSuccessor = makeAddr('secondSuccessor');

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

  function _buyWithDollar(
    StandardDollar selectedDollar,
    address buyer,
    uint256 dollarAmount
  ) internal returns (uint256 tokenAmount) {
    uint256 scale = _dollarScale(selectedDollar.decimals());

    tokenAmount = _dollarsToTokens(dollarAmount, gate.entryPrice(), scale);
    selectedDollar.mint(buyer, dollarAmount);
    vm.startPrank(buyer);
    selectedDollar.approve(address(gate), dollarAmount);
    gate.buy(dollarAmount);
    vm.stopPrank();
  }

  function _approveReserve(
    IERC20 selectedDollar,
    address staff,
    uint256 amount
  ) internal {
    bytes memory data = abi.encodeCall(IERC20.approve, (address(gate), amount));

    vm.prank(staff);
    fund.execute(address(selectedDollar), 0, data);
  }

  function _transferFundDollar(
    IERC20 selectedDollar,
    address staff,
    address receiver,
    uint256 amount
  ) internal {
    bytes memory data = abi.encodeCall(IERC20.transfer, (receiver, amount));

    vm.prank(staff);
    fund.execute(address(selectedDollar), 0, data);
  }

  function _completeStage(uint256 price) internal {
    vm.prank(owner);
    fund.completeStage(price);
  }

  function _completeStage(address staff, uint256 price) internal {
    vm.prank(staff);
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

  function _dollarsToTokens(
    uint256 dollarAmount,
    uint256 price,
    uint256 scale
  ) internal pure returns (uint256) {
    return Math.mulDiv(dollarAmount, ONE_TOKEN * scale, price);
  }

  function _tokensToDollars(
    uint256 tokenAmount,
    uint256 price
  ) internal pure returns (uint256) {
    return Math.mulDiv(tokenAmount, price, ONE_TOKEN * DOLLAR_SCALE);
  }

  function _tokensToDollars(
    uint256 tokenAmount,
    uint256 price,
    uint256 scale
  ) internal pure returns (uint256) {
    return Math.mulDiv(tokenAmount, price, ONE_TOKEN * scale);
  }

  function _dollarScale(uint8 dollarDecimals)
    internal
    pure
    returns (uint256)
  {
    return 10 ** (18 - dollarDecimals);
  }

  function _reserveAmount(
    uint256 tokenAmount,
    uint256 price
  ) internal pure returns (uint256) {
    return _tokensToDollars(tokenAmount, price);
  }

  function _reserveAmount(
    uint256 tokenAmount,
    uint256 price,
    uint256 scale
  ) internal pure returns (uint256) {
    return _tokensToDollars(tokenAmount, price, scale);
  }
}
