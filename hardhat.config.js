import { defineConfig } from 'hardhat/config'

const compiler = {
  version: '0.8.37',
  settings: { evmVersion: 'cancun' },
}

export default defineConfig({
  solidity: {
    profiles: {
      default: compiler,
      production: compiler,
    },
  },
})
