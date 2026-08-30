// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import './OreVein.sol';
import './MagicOre.sol';
import './FreeMine.sol';

contract NewCampFounding {
  OreVein public immutable oreVein;
  MagicOre public immutable magicOre;
  FreeMine public immutable freeMine;

  constructor(address dollar, string memory contractURI) {
    magicOre = new MagicOre('Magic Ore', 'ORE');

    freeMine = new FreeMine(
      10 ** magicOre.decimals(),
      dollar,
      address(magicOre)
    );

    magicOre.transferOwnership(address(freeMine));

    oreVein = new OreVein(dollar, msg.sender, address(freeMine), contractURI);

    freeMine.transferOwnership(address(oreVein));
  }
}
