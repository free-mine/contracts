// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './MineCrew.sol';
import './MiningEquipment.sol';

interface IFreeMine {
  function closeShift() external;
  function fundShift(uint256 price) external;
  function changeDollar(address newDollar) external;
  function updateEntryPrice(uint256 newPrice) external;
  function expireClaim(uint256 shiftId, uint256 claimId) external;
}

/**
 * @notice Entry point for the Free Mine crew.
 *
 * Crew members can manage assets held by the Ore Vein and forward
 * administrative calls to the Free Mine. The Ore Vein must own the Free Mine
 * for these forwarded calls to succeed.
 */
contract OreVein is MineCrew, MiningEquipment {
  using SafeERC20 for IERC20;

  error InvalidTarget();

  event ContractURIUpdated();

  string public contractURI;
  IFreeMine public immutable freeMine;

  constructor(
    address dollar,
    address initialOwner,
    address freeMineAddress,
    string memory initialContractURI
  ) MineCrew(initialOwner) {
    contractURI = initialContractURI;
    freeMine = IFreeMine(freeMineAddress);

    IERC20(dollar).forceApprove(freeMineAddress, type(uint256).max);
  }

  function setContractURI(string calldata newContractURI) external crew {
    contractURI = newContractURI;

    emit ContractURIUpdated();
  }

  function execute(address target, uint256 value, bytes calldata data)
    external crew returns (bytes memory)
  {
    if (target == address(this) || target == address(freeMine)) {
      revert InvalidTarget();
    }

    return _execute(target, value, data);
  }

  function closeShift() external crew {
    freeMine.closeShift();
  }

  function fundShift(uint256 price) external crew {
    freeMine.fundShift(price);
  }

  function expireClaim(uint256 shiftId, uint256 claimId) external crew {
    freeMine.expireClaim(shiftId, claimId);
  }

  function changeDollar(address newDollar) external crew {
    freeMine.changeDollar(newDollar);
    IERC20(newDollar).forceApprove(address(freeMine), type(uint256).max);
  }

  function updateEntryPrice(uint256 newPrice) external crew {
    freeMine.updateEntryPrice(newPrice);
  }
}
