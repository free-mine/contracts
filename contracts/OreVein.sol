// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import './MineCrew.sol';
import './MineOperations.sol';

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
contract OreVein is MineCrew, MineOperations {
  error InvalidTarget();

  event ContractURIUpdated();

  string public contractURI;
  IFreeMine public immutable freeMine;

  constructor(IFreeMine freeMineAddress, string memory initialContractURI) {
    freeMine = freeMineAddress;
    contractURI = initialContractURI;
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

  // Below is the forwarding zone

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
  }

  function updateEntryPrice(uint256 newPrice) external crew {
    freeMine.updateEntryPrice(newPrice);
  }
}
