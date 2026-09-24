import { Wallet, JsonRpcProvider } from 'ethers'

import { env } from './environment.js'

const url = `https://avax-mainnet.g.alchemy.com/v2/${env.RPC_TOKEN}`
const provider = new JsonRpcProvider(url)

export const wallet = new Wallet(env.PRIVATE_KEY, provider)
