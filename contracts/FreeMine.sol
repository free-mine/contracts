// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import './OreExchange.sol';

/**
 * @notice Main contract for miners to buy Magic Ore and exchange it for
 * dollars.
 *
 * Miners open claims by locking Magic Ore in the current shift. The owner
 * closes the shift and funds it with dollars at a price from 90% to 99% of
 * the current entry price. Both limits are rounded down. A miner can then
 * redeem a claim for dollars.
 *
 * A miner may cancel a claim before or after funding. Cancellation burns one
 * Magic Ore and returns the rest. If the shift is already funded, the dollars
 * reserved for the claim return to the owner. Two weeks after funding, the
 * owner may expire an unredeemed claim in the same way.
 */
contract FreeMine is OreExchange {
  using SafeERC20 for IDollar;

  struct Claim {
    address miner;
    uint256 oreAmount;
  }

  struct Shift {
    bool funded;
    uint256 price;
    IDollar dollar;
    uint256 fundedAt;
    uint256 oreAmount;
    uint256 dollarScale;
    uint256 currentClaimId;
    mapping(uint256 => Claim) claims;
  }

  error SenderIsNotMiner();
  error ShiftIsNotClosed();
  error ShiftClosingIsBlocked();
  error PriceIsTooLow(uint256 minPrice);
  error PriceIsTooHigh(uint256 maxPrice);
  error ShiftIsNotFunded(uint256 shiftId);
  error InsufficientQuantity(uint256 amount);
  error ExpirationTooEarly(uint256 cancelableAt);
  error ClaimNotFound(uint256 shiftId, uint256 claimId);

  event ShiftClosed(uint256 indexed id);
  event ShiftFunded(uint256 indexed id);
  event Sacrificed(address indexed miner, uint256 oreAmount);

  event ClaimOpened(
    uint256 oreAmount,
    address indexed miner,
    uint256 indexed shiftId,
    uint256 indexed claimId
  );

  event ClaimClosed(
    bool cancelled,
    address indexed miner,
    uint256 indexed shiftId,
    uint256 indexed claimId
  );

  uint256 public currentShiftId;
  mapping(uint256 => Shift) public shifts;

  constructor(uint256 initialPrice, address initialDollar, address ore)
    OreExchange(initialPrice, initialDollar, ore)
    Ownable(_msgSender())
  {
    currentShiftId = 1;
  }

  /**
   * @dev Returns a storage reference to a shift and a memory copy of one of
   * its claims. The copy remains usable after the claim is deleted. The
   * storage reference lets the caller update the shift. A claim cannot have
   * zero Magic Ore, so a zero amount means that the claim does not exist.
   */
  function _getShiftAndClaim(uint256 shiftId, uint256 claimId)
    private
    view
    returns (Shift storage, Claim memory)
  {
    Shift storage shift = shifts[shiftId];
    Claim memory claim = shift.claims[claimId];

    if (claim.oreAmount == 0) {
      revert ClaimNotFound(shiftId, claimId);
    }

    return (shift, claim);
  }

  /**
   * @dev Reverts unless the caller is the miner recorded in the claim.
   */
  function _verifySenderIsMiner(Claim memory claim) private view {
    if (claim.miner != _msgSender()) {
      revert SenderIsNotMiner();
    }
  }

  /**
   * @dev Removes a claim, burns one Magic Ore, and returns the rest to the
   * miner. If the shift was funded, the dollars reserved for the claim return
   * to the owner. Used when a miner cancels a claim and when the owner expires
   * one.
   */
  function _cancelClaim(
    uint256 shiftId,
    uint256 claimId,
    Shift storage shift,
    Claim memory claim
  ) private {
    delete shift.claims[claimId];

    shift.oreAmount -= claim.oreAmount;

    magicOre.burn(address(this), ONE_MAGIC_ORE);
    magicOre.transfer(claim.miner, claim.oreAmount - ONE_MAGIC_ORE);

    if (shift.funded) {
      shift.dollar.safeTransfer(
        owner(),
        _oreToDollars(claim.oreAmount, shift.price, shift.dollarScale)
      );
    }

    emit ClaimClosed(true, claim.miner, shiftId, claimId);
  }

  /**
   * @notice Returns an open claim.
   * @dev Reverts if the claim does not exist or has already been closed.
   */
  function getClaim(uint256 shiftId, uint256 claimId)
    external view returns (Claim memory)
  {
    (, Claim memory claim) = _getShiftAndClaim(shiftId, claimId);

    return claim;
  }

  function openClaim(uint256 amount) external {
    address sender = _msgSender();

    if (amount <= ONE_MAGIC_ORE) {
      revert InsufficientQuantity(amount);
    }

    magicOre.lock(sender, amount);

    Shift storage shift = shifts[currentShiftId];

    shift.currentClaimId++;
    shift.oreAmount += amount;

    shift.claims[shift.currentClaimId] = Claim({
      miner: sender,
      oreAmount: amount
    });

    emit ClaimOpened(amount, sender, currentShiftId, shift.currentClaimId);
  }

  function cancelClaim(uint256 shiftId, uint256 claimId) external {
    (Shift storage shift, Claim memory claim)
      = _getShiftAndClaim(shiftId, claimId);

    _verifySenderIsMiner(claim);
    _cancelClaim(shiftId, claimId, shift, claim);
  }

  function redeemClaim(uint256 shiftId, uint256 claimId) external {
    (Shift storage shift, Claim memory claim)
      = _getShiftAndClaim(shiftId, claimId);

    _verifySenderIsMiner(claim);

    if (!shift.funded) {
      revert ShiftIsNotFunded(shiftId);
    }

    delete shift.claims[claimId];

    shift.oreAmount -= claim.oreAmount;

    magicOre.burn(address(this), claim.oreAmount);

    shift.dollar.safeTransfer(
      claim.miner,
      _oreToDollars(claim.oreAmount, shift.price, shift.dollarScale)
    );

    emit ClaimClosed(false, claim.miner, shiftId, claimId);
  }

  function sacrifice(uint256 oreAmount) external {
    address sender = _msgSender();

    magicOre.burn(sender, oreAmount);

    emit Sacrificed(sender, oreAmount);
  }

  function closeShift() external onlyOwner {
    uint256 lastShiftId = currentShiftId - 1;
    Shift storage lastShift = shifts[lastShiftId];

    /**
     * @dev The last closed shift must be funded before the current shift can
     * close. An empty last shift does not block closing because it has no
     * claims to fund.
     */
    if (!lastShift.funded && lastShift.oreAmount > 0) {
      revert ShiftClosingIsBlocked();
    }

    currentShiftId++;

    emit ShiftClosed(currentShiftId - 1);
  }

  /**
   * @notice Funds the shift immediately before the current shift. In normal
   * use, this is the most recently closed shift.
   * @dev Calling this function before shift 1 is closed would fund the unused
   * shift 0.
   */
  function fundShift(uint256 price) external onlyOwner {
    uint256 shiftId = currentShiftId - 1;
    Shift storage shift = shifts[shiftId];

    /**
     * @dev A funded target means that no newer shift has been closed yet. In
     * that case, `ShiftIsNotClosed` refers to the current shift.
     */
    if (shift.funded) {
      revert ShiftIsNotClosed();
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
      _oreToDollars(shift.oreAmount, price, _dollarScale);

    dollar.safeTransferFrom(_msgSender(), address(this), dollarAmount);

    shift.funded = true;
    shift.price = price;
    shift.dollar = dollar;
    shift.dollarScale = _dollarScale;
    shift.fundedAt = block.timestamp;

    emit ShiftFunded(shiftId);
  }

  function expireClaim(uint256 shiftId, uint256 claimId) external onlyOwner {
    (Shift storage shift, Claim memory claim)
      = _getShiftAndClaim(shiftId, claimId);

    if (!shift.funded) {
      revert ShiftIsNotFunded(shiftId);
    }

    uint256 cancelableAt = shift.fundedAt + 2 weeks;

    if (block.timestamp < cancelableAt) {
      revert ExpirationTooEarly(cancelableAt);
    }

    _cancelClaim(shiftId, claimId, shift, claim);
  }
}
