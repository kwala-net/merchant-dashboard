import { NextRequest, NextResponse } from 'next/server'
import { redis } from '@/lib/redis'
import type { Payment } from '@/types'

const PAYMENTS_KEY = 'payments'

const CLASS_MAP: Record<string, Payment['classification']> = {
  UNCLASSIFIED: 'UNCLASSIFIED', '0': 'UNCLASSIFIED',
  STANDARD:     'STANDARD',     '1': 'STANDARD',
  HIGH_VALUE:   'HIGH_VALUE',   '2': 'HIGH_VALUE',
  SUSPICIOUS:   'SUSPICIOUS',   '3': 'SUSPICIOUS',
  BLOCKED:      'BLOCKED',      '4': 'BLOCKED',
}

function parseBody(raw: unknown): Record<string, unknown> {
  if (typeof raw === 'string') {
    try { return JSON.parse(raw) } catch { return {} }
  }
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    return raw as Record<string, unknown>
  }
  return {}
}

async function readPayments(): Promise<Payment[]> {
  return redis.lrange<Payment>(PAYMENTS_KEY, 0, -1)
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Record<string, unknown> = {}
  try {
    body = parseBody(await request.json())
  } catch {
    // unparseable body — fall through with empty body
  }

  const paymentId = String(body.paymentId ?? '').trim()
  if (!paymentId) {
    return NextResponse.json(
      { success: false, error: 'Missing required field: paymentId', _received: body },
      { status: 400 }
    )
  }

  // Kwala sends classification as uint8 (e.g. 1) or string enum — accept both
  const classification: Payment['classification'] =
    CLASS_MAP[String(body.classification ?? '')] ?? 'UNCLASSIFIED'

  // Kwala sends amount as raw uint256 — coerce to number; fall back to 0
  const amount = body.amount !== undefined && body.amount !== null
    ? Number(body.amount)
    : NaN
  const safeAmount = isNaN(amount) ? 0 : amount

  const syncLatencyMs   = Number(body.syncLatencyMs  ?? 0)
  const dbSynced        = body.dbSynced        !== false  // default true
  const webhookDelivered = body.webhookDelivered === true  // default false

  const syncedAt = Date.now()
  const payments = await readPayments()
  const existingIdx = payments.findIndex(p => p.paymentId === paymentId)

  const status: Payment['status'] = webhookDelivered
    ? 'WEBHOOK_DELIVERED'
    : dbSynced
      ? 'SYNCED'
      : 'CONFIRMED'

  if (existingIdx >= 0) {
    const updated: Payment = {
      ...payments[existingIdx],
      classification,
      status,
      syncLatencyMs,
      syncedAt,
      ...(body.txHash  ? { txHash:  String(body.txHash)  } : {}),
    }
    await redis.lset(PAYMENTS_KEY, existingIdx, updated)
  } else {
    const newPayment: Payment = {
      paymentId,
      payer:         String(body.payer         ?? ''),
      merchant:      String(body.merchant      ?? ''),
      amount:        safeAmount,
      tokenAddress:  String(body.tokenAddress  ?? ''),
      timestamp:     Number(body.timestamp     ?? syncedAt),
      blockNumber:   Number(body.blockNumber   ?? 0),
      status,
      classification,
      txHash:        String(body.txHash        ?? ''),
      metadata:      String(body.metadata      ?? ''),
      webhookRetryCount:   0,
      lastWebhookAttempt:  0,
      syncedAt,
      syncLatencyMs,
      refunded:      false,
      refundAmount:  0,
      countryCode:   String(body.countryCode   ?? ''),
      currencyCode:  String(body.currencyCode  ?? ''),
      processorFee:  0,
      networkFee:    0,
    }
    await redis.lpush(PAYMENTS_KEY, newPayment)
  }

  return NextResponse.json({ success: true, paymentId, syncedAt, message: 'Payment synced' })
}

export async function GET(): Promise<NextResponse> {
  const payments = await readPayments()
  return NextResponse.json({ success: true, payments })
}
