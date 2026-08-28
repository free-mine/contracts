// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

interface IDollar is IERC20 {
  function decimals() external view returns (uint8);
}

/** @dev Magic Ore must use 18 decimals. */
interface IMagicOre is IERC20 {
  function mint(address to, uint256 amount) external;
  function burn(address from, uint256 amount) external;
  function lock(address from, uint256 amount) external;
}

/**
 * @notice Lets miners buy Magic Ore with the active dollar token.
 *
 * The Free Mine must own the Magic Ore contract so it can mint, burn, and lock
 * ore. Each purchase sends the miner's dollar tokens directly to the Free
 * Mine owner.
 *
 * The owner may replace the active dollar token, but it cannot be Magic Ore.
 * The owner may also update the entry price no more than once every seven
 * days. The new price must be between 96% and 104% of the current price. Both
 * limits are rounded down.
 *
 * @dev Dollar tokens may use up to 18 decimals. Magic Ore amounts and entry
 * prices use 18 decimals. `_dollarScale` converts the active dollar token's
 * units to 18-decimal values.
 */
abstract contract OreExchange is Ownable {
  using SafeERC20 for IDollar;

  error OwnerCannotBuy();
  error NewDollarIsMagicOre();
  error EntryPriceUpdateTooEarly();
  error EntryPriceUpdateOutOfRange();
  error TooBigDollarDecimals(uint256 decimals);

  event EntryPriceUpdated(uint256 oldPrice, uint256 newPrice);
  event Bought(address indexed buyer, uint256 dollar, uint256 ore);
  event DollarChanged(IDollar indexed dollar, uint256 indexed decimals);

  uint256 private constant MAGIC_ORE_DECIMALS = 18;

  uint256 internal _dollarScale;
  uint256 internal constant ONE_MAGIC_ORE = 10 ** MAGIC_ORE_DECIMALS;

  IDollar public dollar;
  uint256 public entryPrice;
  uint256 public priceUpdatedAt;
  IMagicOre public immutable magicOre;

  constructor(uint256 initialPrice, address initialDollar, address ore) {
    magicOre = IMagicOre(ore);
    entryPrice = initialPrice;
    priceUpdatedAt = block.timestamp;

    _updateDollar(IDollar(initialDollar));
  }

  function _updateDollar(IDollar newDollar) private {
    if (address(newDollar) == address(magicOre)) {
      revert NewDollarIsMagicOre();
    }

    uint256 dollarDecimals = newDollar.decimals();

    if (dollarDecimals > MAGIC_ORE_DECIMALS) {
      revert TooBigDollarDecimals(dollarDecimals);
    }

    dollar = newDollar;
    _dollarScale = 10 ** (MAGIC_ORE_DECIMALS - dollarDecimals);

    emit DollarChanged(dollar, dollarDecimals);
  }

  function _dollarsToOre(
    uint256 dollarAmount,
    uint256 price
  ) internal view returns (uint256) {
    return Math.mulDiv(
      dollarAmount,
      10 ** MAGIC_ORE_DECIMALS * _dollarScale,
      price
    );
  }

  /**
   * @dev Converts Magic Ore units to dollar-token units. `dollarScale` is
   * passed in because each funded shift keeps its dollar token's scale.
   */
  function _oreToDollars(
    uint256 oreAmount,
    uint256 price,
    uint256 dollarScale
  ) internal pure returns (uint256) {
    return Math.mulDiv(
      oreAmount,
      price,
      10 ** MAGIC_ORE_DECIMALS * dollarScale
    );
  }

  /**
   * @notice Buys Magic Ore with the dollar token that is active when the
   * transaction runs. The miner must approve this contract to spend that
   * token. Dollar token changes are meant to be rare.
   *
   * Integer division may round a very small purchase down to zero Magic Ore.
   * Dollar tokens are still transferred, so miners should avoid such amounts.
   */
  function buy(uint256 dollarAmount) external {
    address sender = _msgSender();
    uint256 oreAmount = _dollarsToOre(dollarAmount, entryPrice);

    if (sender == owner()) {
      revert OwnerCannotBuy();
    }

    dollar.safeTransferFrom(sender, owner(), dollarAmount);
    magicOre.mint(sender, oreAmount);

    emit Bought(sender, dollarAmount, oreAmount);
  }

  function updateEntryPrice(uint256 newPrice) external onlyOwner {
    if (block.timestamp < priceUpdatedAt + 7 days) {
      revert EntryPriceUpdateTooEarly();
    }

    uint256 oldPrice = entryPrice;
    uint256 minPrice = Math.mulDiv(oldPrice, 96, 100);
    uint256 maxPrice = Math.mulDiv(oldPrice, 104, 100);

    if (newPrice < minPrice || newPrice > maxPrice) {
      revert EntryPriceUpdateOutOfRange();
    }

    entryPrice = newPrice;
    priceUpdatedAt = block.timestamp;

    emit EntryPriceUpdated(oldPrice, newPrice);
  }

  /**
   * @notice Lets the owner replace the dollar token in an emergency. The Free
   * Mine is expected to keep the same token during normal operation.
   */
  function changeDollar(IDollar newDollar) external onlyOwner {
    _updateDollar(newDollar);
  }
}
