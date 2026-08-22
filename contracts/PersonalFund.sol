// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import './ManuallyOperated.sol';

interface IGate {
  function completeStage() external;
  function changeDollar(address newDollar) external;
  function changeEntryPrice(uint256 newPrice) external;
  function provideStageLiquidity(uint256 price) external;
  function cancelRequestByOwner(uint256 stageId, uint256 requestId) external;
}

/**
 * @notice Entry point for the Fund manager.
 *
 * Lets the manager manage the capital and call Gate's admin functions.
 */
contract PersonalFund is ManuallyOperated {
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

  function completeStage() external staffOnly {
    gate.completeStage();
  }

  function provideStageLiquidity(uint256 price) external staffOnly {
    gate.provideStageLiquidity(price);
  }

  function cancelRequestByOwner(
    uint256 stageId,
    uint256 requestId
  ) external staffOnly {
    gate.cancelRequestByOwner(stageId, requestId);
  }

  function changeDollar(address newDollar) external staffOnly {
    gate.changeDollar(newDollar);
  }

  function changeEntryPrice(uint256 newPrice) external staffOnly {
    gate.changeEntryPrice(newPrice);
  }
}
