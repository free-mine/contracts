// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import './DepositStore.sol';

/**
 * @notice Entry point for users to interact with the Fund.
 *
 * Withdrawal process:
 *
 * 1. A user creates a withdrawal request. The requested amount of Fund tokens
 * is taken from the user.
 *
 * 2. The Fund manager sets the withdrawal price and provides enough dollars
 * for all requests.
 *
 * 3. The Fund manager starts the next stage. Dollars are assigned to requests
 * from the previous stage at a fixed price.
 *
 * 4. The user decides whether to complete the withdrawal. If the price is
 * acceptable, the user takes the dollars. Otherwise, the user cancels the
 * request and gets the Fund tokens back.
 *
 * Canceling a withdrawal request costs one Fund token. This fee discourages
 * users from creating requests they do not need. With fewer unnecessary
 * requests, fewer dollars need to be set aside. Creating a request is free.
 * There is also no fee when withdrawing dollars.
 *
 * The withdrawal price cannot be lower than 90% of the current purchase price
 * or higher than the current purchase price. This protects against mistakes
 * and malicious actions.
 */
contract Gate is DepositStore {
  using SafeERC20 for IDollar;

  struct Request {
    address author;
    uint256 tokenAmount;
  }

  struct Stage {
    uint256 price;
    IDollar dollar;
    uint256 dollarScale;
    uint256 tokenAmount;
    uint256 currentRequestId;
    mapping(uint256 => Request) requests;
  }

  error SenderIsNotAuthor();
  error StageIsNotComplete();
  error PriceIsHigherThanEntry();
  error PriceIsTooLow(uint256 minPrice);
  error InsufficientQuantity(uint256 amount);
  error RequestNotFound(uint256 stageId, uint256 requestId);

  event StageCompleted(uint256 id);
  event Sacrificed(address indexed author, uint256 tokenAmount);

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

  uint256 public currentStageId;
  mapping(uint256 => Stage) public stages;

  constructor(
    uint256 initialPrice,
    address initialDollar,
    address nativeToken
  )
    DepositStore(initialPrice, initialDollar, nativeToken)
    Ownable(_msgSender())
  {
    currentStageId = 1;
  }

  function _getRequestDataToClose(uint256 stageId, uint256 requestId)
    private
    view
    returns (address, uint256, Stage storage)
  {
    address sender = _msgSender();
    Stage storage stage = stages[stageId];
    Request storage request = stage.requests[requestId];

    if (request.tokenAmount == 0) {
      revert RequestNotFound(stageId, requestId);
    }

    if (request.author != sender) {
      revert SenderIsNotAuthor();
    }

    return (sender, request.tokenAmount, stage);
  }

  function requestWithdrawal(uint256 amount) external {
    address sender = _msgSender();

    if (amount < ONE_FUND_TOKEN) {
      revert InsufficientQuantity(amount);
    }

    fundToken.take(sender, amount);

    Stage storage stage = stages[currentStageId];

    stage.currentRequestId++;
    stage.tokenAmount += amount;

    stage.requests[stage.currentRequestId] = Request({
      author: sender,
      tokenAmount: amount
    });

    emit RequestOpened(sender, currentStageId, stage.currentRequestId);
  }

  function cancelWithdrawalRequest(
    uint256 stageId,
    uint256 requestId
  ) external {
    (address sender, uint256 tokenAmount, Stage storage stage)
      = _getRequestDataToClose(stageId, requestId);

    delete stage.requests[requestId];

    stage.tokenAmount -= tokenAmount;

    fundToken.burn(address(this), ONE_FUND_TOKEN);
    fundToken.transfer(sender, tokenAmount - ONE_FUND_TOKEN);

    if (stageId != currentStageId) {
      stage.dollar.safeTransfer(
        owner(),
        _tokensToDollars(tokenAmount, stage.price, stage.dollarScale)
      );
    }

    emit RequestClosed(sender, stageId, requestId);
  }

  function withdraw(uint256 stageId, uint256 requestId) external {
    if (stageId == currentStageId) {
      revert StageIsNotComplete();
    }

    (address sender, uint256 tokenAmount, Stage storage stage)
      = _getRequestDataToClose(stageId, requestId);

    delete stage.requests[requestId];

    fundToken.burn(address(this), tokenAmount);

    stage.dollar.safeTransfer(
      sender,
      _tokensToDollars(tokenAmount, stage.price, stage.dollarScale)
    );

    emit RequestClosed(sender, stageId, requestId);
  }

  function sacrifice(uint256 tokenAmount) external {
    address sender = _msgSender();

    fundToken.burn(sender, tokenAmount);

    emit Sacrificed(sender, tokenAmount);
  }

  function completeStage (uint256 price) external onlyOwner {
    Stage storage stage = stages[currentStageId];
    uint256 minPrice = Math.mulDiv(entryPrice, 90, 100);

    if (price < minPrice) {
      revert PriceIsTooLow(minPrice);
    }

    if (price > entryPrice) {
      revert PriceIsHigherThanEntry();
    }

    currentStageId++;
    stage.price = price;
    stage.dollar = dollar;
    stage.dollarScale = _dollarScale;

    dollar.safeTransferFrom(
      _msgSender(),
      address(this),
      _tokensToDollars(stage.tokenAmount, price, _dollarScale)
    );

    emit StageCompleted(currentStageId - 1);
  }
}
