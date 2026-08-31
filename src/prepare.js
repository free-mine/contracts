import { mkdir, rmSync, existsSync, readFileSync, writeFileSync } from 'fs'

import { dist, artifacts, deployerContract } from './constants.js'

const handleContract = name => {
  const buildPath = `${artifacts}/contracts/${name}.sol/${name}.json`

  const { abi, bytecode, buildInfoId } = JSON
    .parse(readFileSync(buildPath, 'utf8'))

  const infoPath = `${artifacts}/build-info/${buildInfoId}.json`
  const { input } = JSON.parse(readFileSync(infoPath, 'utf8'))

  writeFileSync(`${dist}/${name}.bin`, bytecode)
  writeFileSync(`${dist}/${name}.abi`, JSON.stringify(abi, null, 2))
  writeFileSync(`${dist}/${name}.input.json`, JSON.stringify(input, null, 2))
}

if (existsSync(dist)) {
  rmSync(dist, { recursive: true })
}

mkdir(dist, () => [
  'OreVein',
  'MagicOre',
  'FreeMine',
  deployerContract,
].forEach(handleContract))
