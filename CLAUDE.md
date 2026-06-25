# CLAUDE.md

## What this project is

OnchainPay merchant dashboard — a Next.js 15 app that shows real-time payment data sourced from a Solidity contract on Ethereum Sepolia. Kwala automation workflows bridge on-chain events to off-chain API routes. Payments are persisted in Upstash Redis (not a local DB or static files).

## Commands

```bash
# frontend
npm run dev          # dev server at localhost:3000
npm run build        # production build
npm run lint         # eslint

# seed Redis from on-chain data (run after deploying + seeding the contract)
npm run seed:redis   # node --env-file=.env scripts/seed-redis.mjs

# contract (from foundry/ — export .env first: export $(grep -v '^#' ../.env | xargs))
forge build
forge test -vvvv
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify -vvvv
forge script script/SeedSepolia.s.sol:SeedSepolia --rpc-url sepolia --broadcast -vvvv
```

## Key files

| File | Purpose |
|---|---|
| `foundry/src/MerchantPayments.sol` | Main contract — all payment, refund, webhook, and sync logic |
| `foundry/script/Deploy.s.sol` | Forge deploy script — registers sample merchant, mints test USDC |
| `foundry/script/SeedSepolia.s.sol` | Forge seed script for Sepolia — single deployer key, 5 payments with varied classifications |
| `scripts/seed-redis.mjs` | Node.js script — reads on-chain payments via RPC, writes to Upstash Redis |
| `src/lib/redis.ts` | Upstash Redis client singleton (uses `UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN`) |
| `src/types/index.ts` | Shared TypeScript interfaces — keep in sync with contract structs/enums |
| `src/app/page.tsx` | Dashboard page — server component, reads payments live from Redis on each request |
| `src/app/api/payments/sync/route.ts` | Kwala posts here after PaymentClassified; upserts payment to Redis `payments` list |
| `src/app/api/webhook/kwala/route.ts` | Merchant webhook receiver; 20% simulated failure; logs each attempt to Redis `webhookAttempts` list |
| `kwala/onchainpay_classifyTrigger.yaml` | Kwala W1: PaymentReceived → classifyPayment(paymentId) |
| `kwala/onchainpay_postsync.yaml` | Kwala W2: PaymentClassified → parallel POST to sync + webhook |
| `src/data/*.json` | Static fixture data for stats, chart, health widgets — NOT written at runtime; payments live in Redis |

## Redis keys

| Key | Type | Written by | Read by |
|---|---|---|---|
| `payments` | list (newest first) | `POST /api/payments/sync`, `seed-redis.mjs` | `page.tsx`, `GET /api/payments/sync` |
| `webhookAttempts` | list (newest first) | `POST /api/webhook/kwala` | (not read by dashboard yet) |

## Contract facts to keep in mind

- `classifyPayment` has two overloads: `(bytes32)` (onlyOperator, self-classifying — used by Kwala) and `(bytes32, PaymentClassification)` (onlyClassifier, manual override). Do not confuse them.
- `receivePayment()` auto-classifies at intake (SUSPICIOUS on velocity/amount breach, HIGH_VALUE otherwise, UNCLASSIFIED if no rule fires). `classifyPayment(bytes32)` only normalises UNCLASSIFIED→STANDARD and emits the event; it does not re-run heuristics.
- A velocity breach no longer reverts — it records the payment as SUSPICIOUS so it surfaces on the dashboard.
- `recordSync()` and `recordWebhookAttempt()` are onlyOperator. The Kwala executor wallet and any backend service that writes sync records need to be granted operator role via `addOperator()`.
- `tokenAddress` is a hex address (e.g. MockERC20), not a symbol string. The frontend type uses `tokenAddress`, not `token`.

## Forge scripting gotcha — block.timestamp mismatch

When a Forge script calls a function that returns a value (e.g. `receivePayment` returning a `paymentId`) and then uses that value in a later broadcast call, the local dry-run and the on-chain simulation run with different `block.timestamp` values. Any ID derived from `block.timestamp` will differ between phases, causing "payment not found" reverts in the simulation phase.

**Rule**: never use return values from broadcast calls as arguments to subsequent broadcast calls in the same script. Instead, read IDs back from contract storage via a view function ONLY in a separate script run after the first is confirmed on-chain.

## Enums — contract vs frontend

**PaymentStatus** (contract int → frontend string):
`PENDING` | `CONFIRMED` | `CLASSIFIED` | `SYNCED` | `WEBHOOK_DELIVERED` | `WEBHOOK_FAILED` | `REFUNDED` | `DISPUTED`

**PaymentClassification**:
`UNCLASSIFIED` | `STANDARD` | `HIGH_VALUE` | `SUSPICIOUS` | `BLOCKED`

Never use free-text values (`invoice`, `subscription`, `COMPLETED`, etc.) — these do not exist in the contract.

## Data flow summary

```
Payer → receivePayment() → PaymentReceived event
  → Kwala W1 → classifyPayment(paymentId) → PaymentClassified event
    → Kwala W2 (parallel):
        → POST /api/payments/sync  (upserts to Redis "payments" list; should also call recordSync() on-chain)
        → POST /api/webhook/kwala  (notifies merchant, 5 retries; logs to Redis "webhookAttempts")
```

For local dev/demo without Kwala running:
```
forge script SeedSepolia.s.sol  →  5 on-chain payments
  → npm run seed:redis           →  payments written to Redis "payments" list
    → npm run dev                →  dashboard reads from Redis and shows data
```

## Kwala workflow setup checklist

Before deploying the YAMLs in `kwala/`:
1. Replace `0x1111111111111111111111111111111111111111` with the real contract address
2. Replace `https://example.com` with the real app URL
3. Populate `APIPayload.Message` using `re.event(N)` interpolation (see YAML comments for field mapping)
4. Call `mp.addOperator(<kwala-executor-wallet>)` on the deployed contract

## What is not wired up yet

- `POST /api/payments/sync` does not call `recordSync()` on-chain
- `POST /api/webhook/kwala` does not call `recordWebhookAttempt()` on-chain
- No real HMAC verification on the webhook signature field
- No real-time WebSocket push to the dashboard
- Static `src/data/*.json` fixtures (stats, chart, health) are not backed by real queries

## Do not

- Add a `token` field to `Payment` — the contract field is `tokenAddress`
- Use `'COMPLETED'` or free-text classification strings — neither exists in the contract enums
- Rename the two `classifyPayment` overloads — the selector difference matters for Kwala's ABI resolution
- Skip granting operator role to any backend/Kwala address that needs to write on-chain records
- Write to `src/data/payments.json` or `src/data/webhookAttempts.json` — those files no longer exist as the runtime DB; Redis is the store
