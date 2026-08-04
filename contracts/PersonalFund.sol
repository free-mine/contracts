// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import './ManuallyOperated.sol';


interface IGate {
  function completeStage(uint256 price) external;
  function changeDollar(address newDollar) external;
  function changeEntryPrice(uint256 newPrice) external;
}

/**
 * @notice Entry point for the Fund manager.
 *
 * Lets the manager manage the capital and call Gate's admin functions.
 */
contract Fund is ManuallyOperated {
  event ContractURIUpdated();

  string public contractURI;
  IGate public immutable gate;

  constructor(IGate gateContract, string memory initialContractURI) {
    gate = gateContract;
    contractURI = initialContractURI;
  }

  function setContractURI(string calldata newContractURI) external staffOnly {
    contractURI = newContractURI;

    emit ContractURIUpdated();
  }

  function completeStage(uint256 price) external staffOnly {
    gate.completeStage(price);
  }

  function changeDollar(address newDollar) external staffOnly {
    gate.changeDollar(newDollar);
  }

  function changeEntryPrice(uint256 newPrice) external staffOnly {
    gate.changeEntryPrice(newPrice);
  }
}
