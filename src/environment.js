import 'dotenv/config'

const { RPC_TOKEN, PRIVATE_KEY } = process.env

if (!RPC_TOKEN || !PRIVATE_KEY) {
  throw new Error('Create .env from example before launching')
}

export const env = { RPC_TOKEN, PRIVATE_KEY }
