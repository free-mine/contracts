// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

interface IDollar is IERC20 {
  function decimals() external view returns (uint8);
}

/** @dev `IFundToken` must use 18 decimals. */
interface IFundToken is IERC20 {
  function mint(address to, uint256 amount) external;
  function burn(address from, uint256 amount) external;
  function take(address from, uint256 amount) external;
}

/**
 * @notice Lets users buy deposits and manages the purchase price and the
 * dollar token. This contract owns the Fund token and can mint or burn it.
 * Users interact with this contract, but all funds go directly to the owner.
 *
 * A different dollar token may be preferred later, so the dollar token can be
 * changed. The Fund token cannot be used as the dollar token because that
 * would break the price logic.
 *
 * To prevent sudden changes, the price can change by at most 4% and no more
 * than once a week.
 *
 * @dev Dollar tokens may use different `decimals` values. A dollar token
 * cannot use more than 18 decimals. Fund token amounts and the price use
 * 18 decimals. Conversions work correctly for every allowed dollar token.
 */
abstract contract DepositStore is Ownable {
  using SafeERC20 for IDollar;

  error OwnerCannotBuy();
  error NewDollarIsFundToken();
  error EntryPriceChangeTooEarly();
  error EntryPriceChangeOutOfRange();
  error TooBigDollarDecimals(uint256 decimals);

  event EntryPriceChanged(uint256 oldPrice, uint256 newPrice);
  event Bought(address indexed buyer, uint256 dollar, uint256 token);
  event DollarChanged(IDollar indexed dollar, uint256 indexed decimals);

  uint256 private constant FUND_TOKEN_DECIMALS = 18;

  uint256 internal _dollarScale;
  uint256 internal constant ONE_FUND_TOKEN = 10 ** FUND_TOKEN_DECIMALS;

  uint256 public entryPrice;
  uint256 public priceChangeTime;
  IDollar public dollar;
  IFundToken public immutable fundToken;

  constructor(
    uint256 initialPrice,
    address initialDollar,
    address nativeToken
  ) {
    entryPrice = initialPrice;
    priceChangeTime = block.timestamp;
    fundToken = IFundToken(nativeToken);

    _updateDollar(IDollar(initialDollar));
  }

  function _updateDollar(IDollar newDollar) private {
    if (address(newDollar) == address(fundToken)) {
      revert NewDollarIsFundToken();
    }

    uint256 dollarDecimals = newDollar.decimals();

    if (dollarDecimals > FUND_TOKEN_DECIMALS) {
      revert TooBigDollarDecimals(dollarDecimals);
    }

    dollar = newDollar;
    _dollarScale = 10 ** (FUND_TOKEN_DECIMALS - dollarDecimals);

    emit DollarChanged(dollar, dollarDecimals);
  }

  function _dollarsToTokens(
    uint256 dollarAmount,
    uint256 price
  ) internal view returns (uint256) {
    return Math.mulDiv(
      dollarAmount,
      10 ** FUND_TOKEN_DECIMALS * _dollarScale,
      price
    );
  }

  /**
   * @dev Not used here, but useful in a child contract.
   */
  function _tokensToDollars(
    uint256 tokenAmount,
    uint256 price,
    uint256 dollarScale
  ) internal pure returns (uint256) {
    return Math.mulDiv(
      tokenAmount,
      price,
      10 ** FUND_TOKEN_DECIMALS * dollarScale
    );
  }

  function buy(uint256 dollarAmount) external {
    address sender = _msgSender();
    uint256 tokenAmount = _dollarsToTokens(dollarAmount, entryPrice);

    if (sender == owner()) {
      revert OwnerCannotBuy();
    }

    dollar.safeTransferFrom(sender, owner(), dollarAmount);
    fundToken.mint(sender, tokenAmount);

    emit Bought(sender, dollarAmount, tokenAmount);
  }

  function changeEntryPrice(uint256 newPrice) external onlyOwner {
    if (block.timestamp < priceChangeTime + 7 days) {
      revert EntryPriceChangeTooEarly();
    }

    uint256 oldPrice = entryPrice;
    uint256 minPrice = Math.mulDiv(oldPrice, 96, 100);
    uint256 maxPrice = Math.mulDiv(oldPrice, 104, 100);

    if (newPrice < minPrice || newPrice > maxPrice) {
      revert EntryPriceChangeOutOfRange();
    }

    entryPrice = newPrice;
    priceChangeTime = block.timestamp;

    emit EntryPriceChanged(oldPrice, newPrice);
  }

  /**
   * @notice This function is for emergencies. It exists as a safety measure
   * and is not meant for normal use. During normal operation, the Fund will
   * always use the same dollar token.
   */
  function changeDollar(IDollar newDollar) external onlyOwner {
    _updateDollar(newDollar);
  }
}
