/**
 * seed-redis.mjs
 *
 * Reads all payments for SEED_MERCHANT from the deployed MerchantPayments contract
 * on Sepolia, then writes them to Upstash Redis so the dashboard shows live data.
 *
 * Usage:
 *   node --env-file=.env scripts/seed-redis.mjs
 *
 * Required env vars (copy .env.example → .env and fill in):
 *   SEPOLIA_RPC_URL
 *   MERCHANT_PAYMENTS_ADDRESS
 *   UPSTASH_REDIS_REST_URL
 *   UPSTASH_REDIS_REST_TOKEN
 */

import { createPublicClient, http } from 'viem'
import { sepolia } from 'viem/chains'
import { Redis } from '@upstash/redis'

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SEED_MERCHANT = '0xdeADbeEf00000000000000000000000000000002'
const CONTRACT_ADDR = /** @type {`0x${string}`} */ (process.env.MERCHANT_PAYMENTS_ADDRESS)
const RPC_URL       = process.env.SEPOLIA_RPC_URL

if (!CONTRACT_ADDR) throw new Error('MERCHANT_PAYMENTS_ADDRESS is not set in env')
if (!RPC_URL)       throw new Error('SEPOLIA_RPC_URL is not set in env')

// ---------------------------------------------------------------------------
// Clients
// ---------------------------------------------------------------------------

const client = createPublicClient({
  chain: sepolia,
  transport: http(RPC_URL),
})

const redis = new Redis({
  url:   process.env.UPSTASH_REDIS_REST_URL,
  token: process.env.UPSTASH_REDIS_REST_TOKEN,
})

// ---------------------------------------------------------------------------
// Minimal ABI fragments
// ---------------------------------------------------------------------------

const ABI = /** @type {const} */ ([
  {
    name: 'getMerchantPayments',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'merchant', type: 'address' },
      { name: 'offset',   type: 'uint256' },
      { name: 'limit',    type: 'uint256' },
    ],
    outputs: [{ type: 'bytes32[]' }],
  },
  {
    name: 'getPayment',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'paymentId', type: 'bytes32' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'paymentId',         type: 'bytes32'  },
          { name: 'payer',             type: 'address'  },
          { name: 'merchant',          type: 'address'  },
          { name: 'amount',            type: 'uint256'  },
          { name: 'tokenAddress',      type: 'address'  },
          { name: 'timestamp',         type: 'uint256'  },
          { name: 'blockNumber',       type: 'uint256'  },
          { name: 'status',            type: 'uint8'    },
          { name: 'classification',    type: 'uint8'    },
          { name: 'txHash',            type: 'bytes32'  },
          { name: 'metadata',          type: 'string'   },
          { name: 'webhookRetryCount', type: 'uint8'    },
          { name: 'lastWebhookAttempt',type: 'uint256'  },
          { name: 'syncedAt',          type: 'uint256'  },
          { name: 'refunded',          type: 'bool'     },
          { name: 'refundAmount',      type: 'uint256'  },
          { name: 'countryCode',       type: 'bytes3'   },
          { name: 'currencyCode',      type: 'bytes3'   },
          { name: 'processorFee',      type: 'uint256'  },
          { name: 'networkFee',        type: 'uint256'  },
        ],
      },
    ],
  },
])

// ---------------------------------------------------------------------------
// Enum mappings (must stay in sync with contract)
// ---------------------------------------------------------------------------

const STATUS = ['PENDING', 'CONFIRMED', 'CLASSIFIED', 'SYNCED', 'WEBHOOK_DELIVERED', 'WEBHOOK_FAILED', 'REFUNDED', 'DISPUTED']
const CLASS  = ['UNCLASSIFIED', 'STANDARD', 'HIGH_VALUE', 'SUSPICIOUS', 'BLOCKED']

function bytes3ToString(hex) {
  // bytes3 comes back as a 0x-prefixed hex string like "0x555344"
  // Decode to ASCII, strip null chars
  const stripped = hex.replace(/^0x/, '')
  let s = ''
  for (let i = 0; i < stripped.length; i += 2) {
    const code = parseInt(stripped.slice(i, i + 2), 16)
    if (code !== 0) s += String.fromCharCode(code)
  }
  return s
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  console.log('Fetching payment IDs for seed merchant…')

  const ids = await client.readContract({
    address: CONTRACT_ADDR,
    abi: ABI,
    functionName: 'getMerchantPayments',
    args: [SEED_MERCHANT, 0n, 100n],
  })

  if (!ids || ids.length === 0) {
    console.error('No payments found. Run the Forge seed script first.')
    process.exit(1)
  }

  console.log(`Found ${ids.length} payment(s). Reading from chain…`)

  const payments = []

  for (const id of ids) {
    const p = await client.readContract({
      address: CONTRACT_ADDR,
      abi: ABI,
      functionName: 'getPayment',
      args: [id],
    })

    payments.push({
      paymentId:         p.paymentId,
      payer:             p.payer,
      merchant:          p.merchant,
      amount:            Number(p.amount),
      tokenAddress:      p.tokenAddress,
      timestamp:         Number(p.timestamp),
      blockNumber:       Number(p.blockNumber),
      status:            STATUS[p.status] ?? 'PENDING',
      classification:    CLASS[p.classification] ?? 'UNCLASSIFIED',
      txHash:            p.txHash,
      metadata:          p.metadata,
      webhookRetryCount: Number(p.webhookRetryCount),
      lastWebhookAttempt:Number(p.lastWebhookAttempt),
      syncedAt:          Number(p.syncedAt),
      syncLatencyMs:     0,
      refunded:          p.refunded,
      refundAmount:      Number(p.refundAmount),
      countryCode:       bytes3ToString(p.countryCode),
      currencyCode:      bytes3ToString(p.currencyCode),
      processorFee:      Number(p.processorFee),
      networkFee:        Number(p.networkFee),
    })
  }

  console.log('Writing to Redis…')

  // Clear existing payments list and repopulate newest-first
  await redis.del('payments')

  // RPUSH in order so index 0 = oldest; or LPUSH in reverse so newest is at front.
  // The dashboard reads LRANGE 0 -1, matching the insert order.
  // Seed payments come from chain oldest-first; we want newest-first in Redis.
  for (const payment of [...payments].reverse()) {
    await redis.lpush('payments', payment)
  }

  console.log(`Done. ${payments.length} payment(s) written to Redis key "payments".`)
  console.table(payments.map(p => ({
    id:             p.paymentId.slice(0, 10) + '…',
    amount:         `${(p.amount / 1e6).toFixed(2)} USDC`,
    status:         p.status,
    classification: p.classification,
    country:        p.countryCode,
  })))
}

main().catch(err => { console.error(err); process.exit(1) })
