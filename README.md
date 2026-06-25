# OnchainPay — Merchant Dashboard

Real-time merchant payment dashboard that bridges on-chain payment events with an off-chain database and merchant notification system. Built with Next.js 15, Solidity (Foundry), Kwala automation workflows, and Upstash Redis.

## Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 15 (App Router), React 18, Recharts, Tailwind CSS |
| API routes | Next.js Route Handlers (`src/app/api/`) |
| Database | Upstash Redis (persistent across deploys, Vercel-compatible) |
| Smart contract | Solidity 0.8.24, Foundry (forge) |
| Chain interaction | viem |
| Automation | Kwala event-driven workflows (YAML) |
| Chain | Ethereum Sepolia (testnet) |

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ONCHAIN  (Sepolia)                                │
│                                                                             │
│   Payer / bridge                                                            │
│       │                                                                     │
│       │  receivePayment(merchant, token, amount, ...)                       │
│       ▼                                                                     │
│  ┌──────────────────────────────────────────────┐                          │
│  │           MerchantPayments.sol               │                          │
│  │                                              │                          │
│  │  • validates token allowlist & daily limit   │                          │
│  │  • runs velocity window check                │                          │
│  │  • auto-classifies: HIGH_VALUE / SUSPICIOUS  │                          │
│  │    (UNCLASSIFIED if no rule fires)           │                          │
│  │  • stores Payment struct                     │                          │
│  │                                              │                          │
│  │  emit PaymentReceived(paymentId, payer,      │──────────────┐           │
│  │       merchant, amount, token, timestamp)    │              │           │
│  └──────────────────────────────────────────────┘              │           │
│                      ▲                                         │           │
│                      │ classifyPayment(paymentId)              │           │
│                      │ [onlyOperator — Kwala executor]         │           │
│                      │                                         │           │
└──────────────────────┼─────────────────────────────────────────┼───────────┘
                       │                                         │
                ┌──────┘                                         │
                │                                                ▼
┌───────────────┴────────────────────────────────────────────────────────────┐
│                      KWALA AUTOMATION LAYER                                │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  Workflow 1: onchainpay_classifyTrigger                             │  │
│  │                                                                     │  │
│  │  trigger: PaymentReceived event (recurring, every event)            │  │
│  │  action:  call classifyPayment(re.event(0))  ← paymentId           │  │
│  │           on MerchantPayments contract                              │  │
│  │           retries: 5  |  wallet: DEFAULT_SMART_WALLET               │  │
│  └────────────────────────────────┬────────────────────────────────────┘  │
│                                   │                                        │
│         classifyPayment() reads stored classification,                     │
│         sets status → CLASSIFIED, emits PaymentClassified                  │
│                                   │                                        │
│                                   ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  Workflow 2: onchainpay_postsync                                    │  │
│  │                                                                     │  │
│  │  trigger: PaymentClassified event (recurring, every event)          │  │
│  │                                                                     │  │
│  │  actions (parallel):                                                │  │
│  │    ├─ POST /api/payments/sync     retries: 3                        │  │
│  │    └─ POST /api/webhook/kwala    retries: 5 (RetriesUntilSuccess)   │  │
│  └────────────────────┬──────────────────────┬─────────────────────────┘  │
│                       │                      │                             │
└───────────────────────┼──────────────────────┼─────────────────────────────┘
                        │                      │
         ┌──────────────┘                      └──────────────────┐
         ▼                                                         ▼
┌────────────────────────────────────────┐   ┌────────────────────────────────┐
│        NEXT.JS API ROUTES              │   │    MERCHANT WEBHOOK ENDPOINT   │
│                                        │   │                                │
│  POST /api/payments/sync               │   │  POST /api/webhook/kwala       │
│    body: { paymentId, amount, payer,   │   │    body: { paymentId, event,   │
│            merchant, classification,   │   │            data, signature }   │
│            syncLatencyMs, dbSynced,    │   │                                │
│            webhookDelivered }          │   │  → notifies merchant system    │
│                                        │   │  → simulates 20% failure rate  │
│  → upserts to Upstash Redis            │   │    (tests retry resilience)    │
│  → should call recordSync() on-chain   │   │  → logs attempt to Redis       │
│                                        │   └────────────────────────────────┘
│  GET  /api/payments/sync               │
│  GET  /api/payments/status?paymentId=  │
│  GET  /api/merchant/balance?merchant=  │
│  POST /api/refunds/initiate            │
│  POST /api/notifications/send          │
└────────────────────────────────────────┘
                        │
                        │  reads "payments" list from Redis
                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DASHBOARD FRONTEND                                   │
│                      src/app/page.tsx (server component)                    │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │  StatsCard  │  │  StatsCard  │  │  StatsCard  │  │    StatsCard    │  │
│  │ Volume (24h)│  │  Payments   │  │  Webhooks   │  │    Sync lag     │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────┘  │
│                                                                             │
│  ┌──────────────────────────┐  ┌────────────────────────────────────────┐  │
│  │    LivePaymentFeed       │  │         SyncStatus                     │  │
│  │  top 5 recent payments   │  │  5-stage onchain→offchain pipeline     │  │
│  │  colour-coded by status  │  │  progress bars + Kwala retry count     │  │
│  │  HIGH_VALUE / SUSPICIOUS │  └────────────────────────────────────────┘  │
│  │  classification badges   │                                              │
│  └──────────────────────────┘                                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                        VolumeChart                                  │  │
│  │            USDC volume bars + tx count line — last 12 hours         │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────────────────────┐  ┌────────────────────────────────────────┐  │
│  │     ApiHealthTable       │  │      KwalaWorkflowEvents               │  │
│  │  method / endpoint /     │  │  timeline of workflow steps:           │  │
│  │  status / latency per    │  │  trigger → fn → event → sync → retry  │  │
│  │  API route               │  └────────────────────────────────────────┘  │
│  └──────────────────────────┘                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Payment lifecycle (status machine)

```
receivePayment()
      │
      ▼
  PENDING ──── confirmPayment() ────► CONFIRMED
      │                                   │
      └──── (velocity / amount breach)    │
             auto-set SUSPICIOUS          │
             or HIGH_VALUE                │
                                          │
                          classifyPayment() [Kwala W1]
                                          │
                                          ▼
                                     CLASSIFIED
                                          │
                             recordSync() [Kwala W2 → /api/payments/sync]
                                          │
                                          ▼
                                       SYNCED
                                          │
                        webhook delivered?
                         ├── yes ──► WEBHOOK_DELIVERED
                         └── no  ──► WEBHOOK_FAILED
                                          │
                              requestRefund() + approveRefund()
                                          │
                                          ▼
                                      REFUNDED
```

### Classification buckets

| Value | Meaning | Set by |
|---|---|---|
| `UNCLASSIFIED` | Not yet classified | `receivePayment()` default |
| `STANDARD` | Normal payment | `classifyPayment(bytes32)` — UNCLASSIFIED normalised |
| `HIGH_VALUE` | Amount ≥ `highValueThreshold` | `receivePayment()` auto or classifier |
| `SUSPICIOUS` | Velocity breach or amount ≥ `suspiciousThreshold` | `receivePayment()` auto or classifier |
| `BLOCKED` | Hard-blocked by classifier | `classifyPayment(bytes32, BLOCKED)` |

---

## Project Structure

```
merchant-dashboard/
├── src/
│   ├── app/
│   │   ├── page.tsx                    # dashboard page (server component, reads from Redis)
│   │   ├── layout.tsx
│   │   └── api/
│   │       ├── payments/
│   │       │   ├── sync/route.ts       # POST: upsert payment to Redis, GET: list payments
│   │       │   └── status/route.ts     # GET: payment status by ID
│   │       ├── merchant/
│   │       │   └── balance/route.ts    # GET: merchant balance
│   │       ├── refunds/
│   │       │   └── initiate/route.ts   # POST: open refund request
│   │       ├── notifications/
│   │       │   └── send/route.ts       # POST: send notification
│   │       └── webhook/
│   │           └── kwala/route.ts      # POST: Kwala webhook receiver (20% simulated failure, logs to Redis)
│   ├── components/
│   │   ├── StatsCard.tsx
│   │   ├── LivePaymentFeed.tsx
│   │   ├── SyncStatus.tsx
│   │   ├── VolumeChart.tsx             # Recharts ComposedChart
│   │   ├── ApiHealthTable.tsx
│   │   ├── KwalaWorkflowEvents.tsx
│   │   └── index.ts
│   ├── data/                           # static JSON fixtures (stats, chart, health — not runtime-written)
│   │   ├── merchantStats.json
│   │   ├── syncStatus.json
│   │   ├── volumeChart.json
│   │   ├── apiHealth.json
│   │   └── kwalaEvents.json
│   ├── lib/
│   │   └── redis.ts                    # Upstash Redis client singleton
│   └── types/index.ts                  # shared TypeScript interfaces
├── foundry/
│   ├── src/
│   │   ├── MerchantPayments.sol        # main contract
│   │   └── MockERC20.sol               # test token (6 decimals, mock USDC)
│   ├── test/MerchantPayments.t.sol
│   ├── script/
│   │   ├── Deploy.s.sol                # deploys contracts, registers demo merchant
│   │   └── SeedSepolia.s.sol           # seeds 5 payments on Sepolia (single-key, no Anvil required)
│   └── foundry.toml
├── scripts/
│   └── seed-redis.mjs                  # reads on-chain payments via RPC, writes to Redis
└── kwala/
    ├── onchainpay_classifyTrigger.yaml # W1: PaymentReceived → classifyPayment()
    └── onchainpay_postsync.yaml        # W2: PaymentClassified → parallel POSTs
```

---

## Setup

### 1. Install dependencies

```bash
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
```

Fill in `.env`:

| Variable | Where to get it |
|---|---|
| `UPSTASH_REDIS_REST_URL` | [console.upstash.com](https://console.upstash.com) → create database → REST API |
| `UPSTASH_REDIS_REST_TOKEN` | same page |
| `SEPOLIA_RPC_URL` | [alchemy.com](https://alchemy.com) → create app → Ethereum Sepolia |
| `ETHERSCAN_API_KEY` | [etherscan.io/myapikey](https://etherscan.io/myapikey) |
| `PRIVATE_KEY` | your deployer wallet private key (needs Sepolia ETH — get some at [sepoliafaucet.com](https://sepoliafaucet.com)) |
| `MERCHANT_PAYMENTS_ADDRESS` | set this after step 4 |
| `MOCK_ERC20_ADDRESS` | set this after step 4 |

### 3. Run the dashboard locally (static fixtures only)

```bash
npm run dev        # http://localhost:3000
```

The dashboard loads with static fixture data. Continue with steps 4–6 to replace it with real on-chain data.

### 4. Deploy the contract to Sepolia

```bash
cd foundry

# load .env into the current shell (needed for vm.envUint inside the script)
export $(grep -v '^#' ../.env | xargs)

forge script script/Deploy.s.sol:Deploy \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  -vvvv
```

Copy the two addresses logged at the end and add them to your `.env`:

```
MERCHANT_PAYMENTS_ADDRESS=0x...
MOCK_ERC20_ADDRESS=0x...
```

### 5. Seed on-chain payment data

```bash
# still in foundry/, env already exported from step 4
forge script script/SeedSepolia.s.sol:SeedSepolia \
  --rpc-url sepolia \
  --broadcast \
  -vvvv
```

This creates 5 payments on Sepolia with a natural classification mix:
- **2 × UNCLASSIFIED** — standard-value payments awaiting Kwala classification
- **1 × HIGH_VALUE** — 15,000 USDC, above the 10k threshold
- **2 × SUSPICIOUS** — velocity breach (4th and 5th payments from same payer in the same window)

### 6. Populate Redis from the chain

```bash
cd ..   # back to project root
npm run seed:redis
```

This reads all 5 payments from the Sepolia contract via RPC and writes them to the `payments` Redis list. Refresh the dashboard and the live data will appear.

---

## Development

### Frontend

```bash
npm run dev        # http://localhost:3000
npm run build
npm run lint
```

### Smart contract (Foundry)

```bash
cd foundry

forge build
forge test -vvvv

# deploy to local Anvil
anvil &
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvvv

# seed local Anvil (uses hardcoded Anvil keys — do not use on Sepolia)
forge script script/Seed.s.sol:Seed \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvvv
```

The deploy script registers a sample merchant (`0xdEADbeEF...0001`) as `GROWTH` tier with:
- `highValueThreshold`: 500 USDC
- `suspiciousThreshold`: 900 USDC
- `dailyLimit`: 100,000 USDC
- `velocityWindow`: 1 hour / 200 payments max

The Sepolia seed script (`SeedSepolia.s.sol`) uses a separate seed merchant (`0xdeADbeEf...0002`) as `ENTERPRISE` tier with tighter thresholds to force velocity breaches quickly:
- `highValueThreshold`: 10,000 USDC
- `suspiciousThreshold`: 50,000 USDC
- `maxPaymentsPerWindow`: 3

### Redis seeder

```bash
npm run seed:redis
# equivalent to: node --env-file=.env scripts/seed-redis.mjs
```

Reads `getMerchantPayments(SEED_MERCHANT, 0, 100)` from the contract, fetches each payment struct via `getPayment(id)`, and writes the full list to the `payments` Redis key. Safe to re-run — it clears and repopulates the list each time.

---

## Kwala Workflows

Workflows live in `kwala/`. Deploy them via the Kwala dashboard or CLI after filling in:

1. The real deployed `MerchantPayments` contract address (replace `0x1111...1111`)
2. Your Next.js app base URL (replace `https://example.com`)
3. The `APIPayload.Message` bodies using `re.event(N)` interpolation (see comments in each file)
4. Grant Kwala's executor wallet the operator role on the contract:

```solidity
mp.addOperator(<kwala-executor-wallet>);
```

### Workflow 1 — `onchainpay_classifyTrigger`

```
PaymentReceived event
        │
        ▼
classifyPayment(paymentId)      [call, onlyOperator, 5 retries]
        │
        ▼
PaymentClassified event emitted
```

### Workflow 2 — `onchainpay_postsync`

```
PaymentClassified event
        │
        ├──► POST /api/payments/sync      [3 retries]
        │
        └──► POST /api/webhook/kwala      [5 retries — RetriesUntilSuccess]
```

---

## Contract Role Model

| Role | Address | Capability |
|---|---|---|
| `owner` | deployer | all privileged ops, grant/revoke roles, pause |
| `operator` | deployer + Kwala executor | `classifyPayment(bytes32)`, `recordSync`, `recordWebhookAttempt`, `confirmPayment`, refund approval |
| `classifier` | deployer | `classifyPayment(bytes32, PaymentClassification)` (manual override) |

---

## Production TODOs

- [ ] Call `recordSync()` on-chain from `POST /api/payments/sync` after writing to Redis
- [ ] Call `recordWebhookAttempt()` on-chain from `POST /api/webhook/kwala` with HTTP response code + latency
- [ ] Add HMAC signature verification to `POST /api/webhook/kwala` (currently only presence-checked)
- [ ] Wire up live WebSocket or polling in the dashboard for real-time updates without page reload
- [ ] Update `APIPayload.Message` in Kwala YAMLs with `re.event(N)` field interpolation
- [ ] Replace static `src/data/*.json` fixtures (stats, chart, health) with real queries once Kwala is live
