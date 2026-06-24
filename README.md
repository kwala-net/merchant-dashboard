# OnchainPay — Merchant Dashboard

Real-time merchant payment dashboard that bridges on-chain payment events with an off-chain database and merchant notification system. Built with Next.js 15, Solidity (Foundry), and Kwala automation workflows.

## Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 15 (App Router), React 18, Recharts, Tailwind CSS |
| API routes | Next.js Route Handlers (`src/app/api/`) |
| Smart contract | Solidity 0.8.24, Foundry (forge) |
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
│  └────────────────────────────────────┬────────────────────────────────┘  │
│                                       │                                    │
│             classifyPayment() reads stored classification,                 │
│             sets status → CLASSIFIED, emits PaymentClassified              │
│                                       │                                    │
│                                       ▼                                    │
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
│  → writes to offchain DB              │   │    (tests retry resilience)    │
│  → should call recordSync() on-chain   │   └────────────────────────────────┘
│                                        │
│  GET  /api/payments/sync               │
│  GET  /api/payments/status?paymentId=  │
│  GET  /api/merchant/balance?merchant=  │
│  POST /api/refunds/initiate            │
│  POST /api/notifications/send          │
└────────────────────────────────────────┘
                        │
                        │  JSON data (currently static files;
                        │  replace with DB queries in production)
                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DASHBOARD FRONTEND                                   │
│                           src/app/page.tsx                                  │
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
│   │   ├── page.tsx                    # dashboard page (client component)
│   │   ├── layout.tsx
│   │   └── api/
│   │       ├── payments/
│   │       │   ├── sync/route.ts       # POST: write sync record, GET: list synced payments
│   │       │   └── status/route.ts     # GET: payment status by ID
│   │       ├── merchant/
│   │       │   └── balance/route.ts    # GET: merchant balance
│   │       ├── refunds/
│   │       │   └── initiate/route.ts   # POST: open refund request
│   │       ├── notifications/
│   │       │   └── send/route.ts       # POST: send notification
│   │       └── webhook/
│   │           └── kwala/route.ts      # POST: Kwala webhook receiver (20% simulated failure)
│   ├── components/
│   │   ├── StatsCard.tsx
│   │   ├── LivePaymentFeed.tsx
│   │   ├── SyncStatus.tsx
│   │   ├── VolumeChart.tsx             # Recharts ComposedChart
│   │   ├── ApiHealthTable.tsx
│   │   ├── KwalaWorkflowEvents.tsx
│   │   └── index.ts
│   ├── data/                           # static JSON fixtures (replace with DB in prod)
│   │   ├── payments.json
│   │   ├── merchantStats.json
│   │   ├── syncStatus.json
│   │   ├── volumeChart.json
│   │   ├── apiHealth.json
│   │   └── kwalaEvents.json
│   └── types/index.ts                  # shared TypeScript interfaces
├── foundry/
│   ├── src/
│   │   ├── MerchantPayments.sol        # main contract
│   │   └── MockERC20.sol               # test token (6 decimals, mock USDC)
│   ├── test/MerchantPayments.t.sol
│   ├── script/Deploy.s.sol
│   └── foundry.toml
└── kwala/
    ├── onchainpay_classifyTrigger.yaml # W1: PaymentReceived → classifyPayment()
    └── onchainpay_postsync.yaml        # W2: PaymentClassified → parallel POSTs
```

---

## Development

### Next.js frontend

```bash
npm install
npm run dev        # http://localhost:3000
npm run build
npm run lint
```

### Smart contract (Foundry)

```bash
cd foundry

# build
forge build

# test
forge test -vvvv

# deploy to Sepolia (set PRIVATE_KEY env var first)
forge script script/Deploy.s.sol:Deploy \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  -vvvv

# deploy to local Anvil
anvil &
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  -vvvv
```

The deploy script registers a sample merchant (`0xdEADbeEF...0001`) as `GROWTH` tier with:
- `highValueThreshold`: 500 USDC
- `suspiciousThreshold`: 900 USDC
- `dailyLimit`: 100,000 USDC
- `velocityWindow`: 1 hour / 200 payments max

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

- [ ] Replace `src/data/*.json` static fixtures with real database queries in each API route
- [ ] Call `recordSync()` on-chain from `POST /api/payments/sync` after writing to DB
- [ ] Call `recordWebhookAttempt()` on-chain from `POST /api/webhook/kwala` with HTTP response code + latency
- [ ] Add HMAC signature verification to `POST /api/webhook/kwala` (currently only presence-checked)
- [ ] Wire up live WebSocket or polling in the dashboard for real-time updates
- [ ] Replace the Alchemy demo RPC endpoints in `foundry/foundry.toml` with a real API key
- [ ] Update `APIPayload.Message` in Kwala YAMLs with `re.event(N)` field interpolation
