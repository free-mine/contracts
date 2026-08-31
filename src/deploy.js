import { readFileSync } from 'fs'

import { ContractFactory } from 'ethers'

import { wallet } from './wallet.js'
import { dist, usdAddress, deployerContract } from './constants.js'

const fileTemplate = `${dist}/${deployerContract}`
const bin = readFileSync(`${fileTemplate}.bin`, 'utf8')
const abi = JSON.parse(readFileSync(`${fileTemplate}.abi`, 'utf8'))
const factory = new ContractFactory(abi, bin, wallet)

const contract = await factory.deploy(
  usdAddress,
  'https://free-mine.online/contract.json',
)

const address = await contract.getAddress()

console.log('Address', address)
console.log('Please wait...')

await contract.waitForDeployment()

console.log('Successfully deployed!')
