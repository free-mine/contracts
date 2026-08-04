// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IDollar } from '../contracts/DepositStore.sol';
import { SystemFixture } from './helpers/SystemFixture.sol';

contract SystemDeploymentTest is SystemFixture {
  function testDeploymentTopologyAndInitialState() public view {
    assertEq(token.owner(), address(gate));
    assertEq(gate.owner(), address(fund));
    assertEq(fund.owner(), owner);
    assertEq(address(gate.fundToken()), address(token));
    assertEq(address(gate.dollar()), address(dollar));
    assertEq(address(fund.gate()), address(gate));
    assertEq(INITIAL_PRICE, 1e18);
    assertEq(gate.entryPrice(), INITIAL_PRICE);
    assertEq(gate.currentStageId(), 1);
    assertEq(fund.contractURI(), CONTRACT_URI);
    assertEq(token.decimals(), 18);
    assertEq(dollar.decimals(), 6);
    assertEq(token.totalSupply(), 0);

    (
      uint256 stagePrice,
      IDollar stageDollar,
      uint256 stageDollarScale,
      uint256 stageTokenAmount,
      uint256 currentRequestId
    ) = gate.stages(1);

    assertEq(stagePrice, 0);
    assertEq(address(stageDollar), address(0));
    assertEq(stageDollarScale, 0);
    assertEq(stageTokenAmount, 0);
    assertEq(currentRequestId, 0);
  }
}
