// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import './DepositStore.sol';

/**
 * @notice Entry point for users to interact with the Fund.
 *
 * Вывод средств осуществляется через механику stages и requests.
 * Пользователи оставляют завяки на вывод, блокируя токены Фонда.
 * Управляющий завершает стадию, освобождает доллары из позиций
 * и финансирует ими заявки последней закрытой стадии по справедливой цене.
 * Те, кого цена устраивает, могут забрать доллары. Остальные могут забрать
 * токены Фонда.
 *
 * Отмена заявки на любом этапе влечёт штраф в один токен Фонда.
 */
contract Gate is DepositStore {
  using SafeERC20 for IDollar;

  struct Request {
    address author;
    uint256 tokenAmount;
  }

  struct Stage {
    bool ready;
    uint256 price;
    IDollar dollar;
    uint256 fundedAt;
    uint256 dollarScale;
    uint256 tokenAmount;
    uint256 currentRequestId;
    mapping(uint256 => Request) requests;
  }

  error SenderIsNotAuthor();
  error StageIsNotComplete();
  error CompletionOfStagesIsBlocked();
  error PriceIsTooLow(uint256 minPrice);
  error PriceIsTooHigh(uint256 maxPrice);
  error StageIsNotReady(uint256 stageId);
  error InsufficientQuantity(uint256 amount);
  error CancellationTooEarly(uint256 cancelableAt);
  error RequestNotFound(uint256 stageId, uint256 requestId);

  event StageReady(uint256 indexed id);
  event StageCompleted(uint256 indexed id);
  event Sacrificed(address indexed author, uint256 tokenAmount);

  event RequestOpened(
    uint256 tokenAmount,
    address indexed author,
    uint256 indexed stageId,
    uint256 indexed requestId
  );

  event RequestClosed(
    bool cancelled,
    address indexed author,
    uint256 indexed stageId,
    uint256 indexed requestId
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

  /**
   * @dev Точка получения request по stageId + requestId.
   *
   * Чаще всего сущность stage нужна вместе с request, так что здесь
   * они возвращаются вместе, чтобы не дублировать получение stage.
   *
   * Даже после удаления request должен быть доступен, поэтому
   * он записывается в память. Для обеспечения самой возможности удаления
   * stage держим в storage.
   */
  function _getStageAndRequest(uint256 stageId, uint256 requestId)
    private
    view
    returns (Stage storage, Request memory)
  {
    Stage storage stage = stages[stageId];
    Request memory request = stage.requests[requestId];

    if (request.tokenAmount == 0) {
      revert RequestNotFound(stageId, requestId);
    }

    return (stage, request);
  }

  /**
   * @dev Используем для действий пользователя над своим request.
   */
  function _verifySenderIsAuthor(Request memory request) private view {
    if (request.author != _msgSender()) {
      revert SenderIsNotAuthor();
    }
  }

  /**
   * @dev Отменить request может как пользователь, так и owner.
   * Общую логику удаления держим здесь.
   */
  function _cancelRequest(
    uint256 stageId,
    uint256 requestId,
    Stage storage stage,
    Request memory request
  ) private {
    delete stage.requests[requestId];

    stage.tokenAmount -= request.tokenAmount;

    fundToken.burn(address(this), ONE_FUND_TOKEN);
    fundToken.transfer(request.author, request.tokenAmount - ONE_FUND_TOKEN);

    if (stage.ready) {
      stage.dollar.safeTransfer(
        owner(),
        _tokensToDollars(request.tokenAmount, stage.price, stage.dollarScale)
      );
    }

    emit RequestClosed(true, request.author, stageId, requestId);
  }

  /**
   * @dev Внешния функция для чтения on-chain данных request.
   * Применяется для наблюдения за контрактом.
   */
  function getRequest(
    uint256 stageId,
    uint256 requestId
  ) external view returns (Request memory) {
    (, Request memory request) = _getStageAndRequest(stageId, requestId);

    return request;
  }

  function requestWithdrawal(uint256 amount) external {
    address sender = _msgSender();

    if (amount <= ONE_FUND_TOKEN) {
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

    emit RequestOpened(amount, sender, currentStageId, stage.currentRequestId);
  }

  function cancelRequestByAuthor(
    uint256 stageId,
    uint256 requestId
  ) external {
    (Stage storage stage, Request memory request)
      = _getStageAndRequest(stageId, requestId);

    _verifySenderIsAuthor(request);
    _cancelRequest(stageId, requestId, stage, request);
  }

  function withdraw(uint256 stageId, uint256 requestId) external {
    (Stage storage stage, Request memory request)
      = _getStageAndRequest(stageId, requestId);

    _verifySenderIsAuthor(request);

    if (!stage.ready) {
      revert StageIsNotReady(stageId);
    }

    delete stage.requests[requestId];

    stage.tokenAmount -= request.tokenAmount;

    fundToken.burn(address(this), request.tokenAmount);

    stage.dollar.safeTransfer(
      request.author,
      _tokensToDollars(request.tokenAmount, stage.price, stage.dollarScale)
    );

    emit RequestClosed(false, request.author, stageId, requestId);
  }

  function sacrifice(uint256 tokenAmount) external {
    address sender = _msgSender();

    fundToken.burn(sender, tokenAmount);

    emit Sacrificed(sender, tokenAmount);
  }

  function completeStage() external onlyOwner {
    uint256 stageId = currentStageId - 1;
    Stage storage stage = stages[stageId];

    /**
     * @dev Нельзя звершить стадию, если предыдущая не профинансирована.
     * Однако, если все токены из стадии вывели до финансирования,
     * стадия считается несостоявшейся.
     */
    if (!stage.ready && stage.tokenAmount > 0) {
      revert CompletionOfStagesIsBlocked();
    }

    currentStageId++;

    emit StageCompleted(stageId);
  }

  function provideStageLiquidity(uint256 price) external onlyOwner {
    uint256 stageId = currentStageId - 1;
    Stage storage stage = stages[stageId];

    /**
     * @dev Функция вызывается без указания stageId и имеет семантику
     * "Профинансировать последнюю стадию, которая в этом нуждается".
     * Таким образом, если предыдущая стадия уже была профинансирована,
     * ошибка StageIsNotComplete говорит о том, что текущая ещё не закрыта. 
     */
    if (stage.ready) {
      revert StageIsNotComplete();
    }

    uint256 minPrice = Math.mulDiv(entryPrice, 90, 100);
    uint256 maxPrice = Math.mulDiv(entryPrice, 99, 100);

    if (price < minPrice) {
      revert PriceIsTooLow(minPrice);
    }

    if (price > maxPrice) {
      revert PriceIsTooHigh(maxPrice);
    }

    uint256 dollarAmount =
      _tokensToDollars(stage.tokenAmount, price, _dollarScale);

    dollar.safeTransferFrom(_msgSender(), address(this), dollarAmount);

    stage.ready = true;
    stage.price = price;
    stage.dollar = dollar;
    stage.dollarScale = _dollarScale;
    stage.fundedAt = block.timestamp;

    emit StageReady(stageId);
  }

  function cancelRequestByOwner(
    uint256 stageId,
    uint256 requestId
  ) external onlyOwner {
    (Stage storage stage, Request memory request)
      = _getStageAndRequest(stageId, requestId);

    if (!stage.ready) {
      revert StageIsNotReady(stageId);
    }

    uint256 cancelableAt = stage.fundedAt + 2 weeks;

    if (block.timestamp < cancelableAt) {
      revert CancellationTooEarly(cancelableAt);
    }

    _cancelRequest(stageId, requestId, stage, request);
  }
}
