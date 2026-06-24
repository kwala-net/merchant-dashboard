# CLAUDE.md

## What this project is

OnchainPay merchant dashboard — a Next.js 15 app that shows real-time payment data sourced from a Solidity contract on Ethereum Sepolia. Kwala automation workflows bridge on-chain events to off-chain API routes.

## Commands

```bash
# frontend
npm run dev          # dev server at localhost:3000
npm run build        # production build
npm run lint         # eslint

# contract (from foundry/)
forge build
forge test -vvvv
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify -vvvv
```

## Key files

| File | Purpose |
|---|---|
| `foundry/src/MerchantPayments.sol` | Main contract — all payment, refund, webhook, and sync logic |
| `foundry/script/Deploy.s.sol` | Forge deploy script — registers sample merchant, mints test USDC |
| `src/types/index.ts` | Shared TypeScript interfaces — keep in sync with contract structs/enums |
| `src/app/page.tsx` | Single dashboard page, client component, imports static JSON data |
| `src/app/api/payments/sync/route.ts` | Kwala posts here after PaymentClassified; should call `recordSync()` on-chain |
| `src/app/api/webhook/kwala/route.ts` | Merchant webhook receiver; 20% simulated failure for retry testing |
| `kwala/onchainpay_classifyTrigger.yaml` | Kwala W1: PaymentReceived → classifyPayment(paymentId) |
| `kwala/onchainpay_postsync.yaml` | Kwala W2: PaymentClassified → parallel POST to sync + webhook |
| `src/data/*.json` | Static fixture data — the dashboard reads these directly; no live DB yet |

## Contract facts to keep in mind

- `classifyPayment` has two overloads: `(bytes32)` (onlyOperator, self-classifying — used by Kwala) and `(bytes32, PaymentClassification)` (onlyClassifier, manual override). Do not confuse them.
- `receivePayment()` auto-classifies at intake (SUSPICIOUS on velocity/amount breach, HIGH_VALUE otherwise, UNCLASSIFIED if no rule fires). `classifyPayment(bytes32)` only normalises UNCLASSIFIED→STANDARD and emits the event; it does not re-run heuristics.
- A velocity breach no longer reverts — it records the payment as SUSPICIOUS so it surfaces on the dashboard.
- `recordSync()` and `recordWebhookAttempt()` are onlyOperator. The Kwala executor wallet and any backend service that writes sync records need to be granted operator role via `addOperator()`.
- `tokenAddress` is a hex address (e.g. MockERC20), not a symbol string. The frontend type uses `tokenAddress`, not `token`.

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
        → POST /api/payments/sync  (writes DB, should call recordSync() on-chain)
        → POST /api/webhook/kwala  (notifies merchant, 5 retries)
```

## Kwala workflow setup checklist

Before deploying the YAMLs in `kwala/`:
1. Replace `0x1111111111111111111111111111111111111111` with the real contract address
2. Replace `https://example.com` with the real app URL
3. Populate `APIPayload.Message` using `re.event(N)` interpolation (see YAML comments for field mapping)
4. Call `mp.addOperator(<kwala-executor-wallet>)` on the deployed contract

## What is not wired up yet

- The dashboard reads `src/data/*.json` static files — no live DB queries in any route
- `POST /api/payments/sync` does not call `recordSync()` on-chain
- `POST /api/webhook/kwala` does not call `recordWebhookAttempt()` on-chain
- No real HMAC verification on the webhook signature field
- No real-time WebSocket push to the dashboard

## Do not

- Add a `token` field to `Payment` — the contract field is `tokenAddress`
- Use `'COMPLETED'` or free-text classification strings — neither exists in the contract enums
- Rename the two `classifyPayment` overloads — the selector difference matters for Kwala's ABI resolution
- Skip granting operator role to any backend/Kwala address that needs to write on-chain records
