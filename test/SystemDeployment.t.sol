// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import './helpers/SystemFixture.sol';
import '../contracts/DepositStore.sol';

contract SystemDeploymentTest is SystemFixture {
  function testDeploymentTopologyAndInitialState() public view {
    assertEq(fund.owner(), owner);
    assertEq(INITIAL_PRICE, 1e18);
    assertEq(token.decimals(), 18);
    assertEq(dollar.decimals(), 6);
    assertEq(token.totalSupply(), 0);
    assertEq(gate.currentStageId(), 1);
    assertEq(gate.owner(), address(fund));
    assertEq(token.owner(), address(gate));
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(fund.contractURI(), CONTRACT_URI);
    assertEq(address(fund.gate()), address(gate));
    assertEq(address(gate.dollar()), address(dollar));
    assertEq(address(gate.fundToken()), address(token));

    (
      uint256 stagePrice,
      IDollar stageDollar,
      uint256 stageDollarScale,
      uint256 stageTokenAmount,
      uint256 currentRequestId
    ) = gate.stages(1);

    assertEq(stagePrice, 0);
    assertEq(stageDollarScale, 0);
    assertEq(stageTokenAmount, 0);
    assertEq(currentRequestId, 0);
    assertEq(address(stageDollar), address(0));
  }
}
