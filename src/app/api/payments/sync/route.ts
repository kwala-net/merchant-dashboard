import { NextRequest, NextResponse } from 'next/server'
import { redis } from '@/lib/redis'

import type { Payment } from '@/types'

const PAYMENTS_KEY = 'payments'

interface SyncPaymentBody {
  paymentId: string
  txHash?: string
  amount: number
  payer: string
  merchant: string
  classification: 'UNCLASSIFIED'|'STANDARD'|'HIGH_VALUE'|'SUSPICIOUS'|'BLOCKED'
  syncLatencyMs: number
  dbSynced: boolean
  webhookDelivered: boolean
  tokenAddress?: string
  timestamp?: number
  blockNumber?: number
  metadata?: string
  countryCode?: string
  currencyCode?: string
}

async function readPayments(): Promise<Payment[]> {
  return redis.lrange<Payment>(PAYMENTS_KEY, 0, -1)
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Partial<SyncPaymentBody>

  try {
    body = await request.json()
  } catch {
    return NextResponse.json(
      { success: false, error: 'Invalid JSON body' },
      { status: 400 }
    )
  }

  const {
    paymentId, txHash, payer, merchant,
    syncLatencyMs, dbSynced, webhookDelivered,
    tokenAddress, timestamp, blockNumber, metadata, countryCode, currencyCode,
  } = body

  // Kwala sends classification as a raw uint8 integer (e.g. 1); accept both forms.
  const CLASS_MAP: Record<string, Payment['classification']> = {
    UNCLASSIFIED: 'UNCLASSIFIED', '0': 'UNCLASSIFIED',
    STANDARD:     'STANDARD',     '1': 'STANDARD',
    HIGH_VALUE:   'HIGH_VALUE',   '2': 'HIGH_VALUE',
    SUSPICIOUS:   'SUSPICIOUS',   '3': 'SUSPICIOUS',
    BLOCKED:      'BLOCKED',      '4': 'BLOCKED',
  }
  const classification = CLASS_MAP[String(body.classification ?? '')]

  // Kwala sends amount as a raw uint256 integer; coerce to JS number.
  const amount = body.amount !== undefined && body.amount !== null
    ? Number(body.amount)
    : undefined

  const missingFields: string[] = []
  if (!paymentId) missingFields.push('paymentId')
  if (amount === undefined || isNaN(amount)) missingFields.push('amount')
  if (!merchant) missingFields.push('merchant')
  if (!classification) missingFields.push('classification')
  if (syncLatencyMs === undefined || syncLatencyMs === null) missingFields.push('syncLatencyMs')
  if (dbSynced === undefined || dbSynced === null) missingFields.push('dbSynced')
  if (webhookDelivered === undefined || webhookDelivered === null) missingFields.push('webhookDelivered')

  if (missingFields.length > 0) {
    return NextResponse.json(
      { success: false, error: `Missing required fields: ${missingFields.join(', ')}` },
      { status: 400 }
    )
  }

  const syncedAt = Date.now()

  const payments = await readPayments()
  const existingIdx = payments.findIndex((p) => p.paymentId === paymentId)

  const status: Payment['status'] = webhookDelivered
    ? 'WEBHOOK_DELIVERED'
    : dbSynced
      ? 'SYNCED'
      : 'CONFIRMED'

  if (existingIdx >= 0) {
    const updated: Payment = {
      ...payments[existingIdx],
      classification: classification!,
      status,
      syncLatencyMs: syncLatencyMs!,
      syncedAt,
      ...(txHash ? { txHash } : {}),
      ...(webhookDelivered !== undefined ? { webhookDelivered } : {}),
    }
    await redis.lset(PAYMENTS_KEY, existingIdx, updated)
  } else {
    const newPayment: Payment = {
      paymentId: paymentId!,
      payer: payer ?? '',
      merchant: merchant!,
      amount: amount!,
      tokenAddress: tokenAddress ?? '',
      timestamp: timestamp ?? syncedAt,
      blockNumber: blockNumber ?? 0,
      status,
      classification: classification!,
      txHash: txHash ?? '',
      metadata: metadata ?? '',
      webhookRetryCount: 0,
      lastWebhookAttempt: 0,
      syncedAt,
      syncLatencyMs: syncLatencyMs!,
      refunded: false,
      refundAmount: 0,
      countryCode: countryCode ?? 'USD',
      currencyCode: currencyCode ?? 'USD',
      processorFee: 0,
      networkFee: 0,
    }
    await redis.lpush(PAYMENTS_KEY, newPayment)
  }

  return NextResponse.json({
    success: true,
    paymentId,
    syncedAt,
    message: 'Payment synced',
  })
}

export async function GET(): Promise<NextResponse> {
  const payments = await readPayments()
  return NextResponse.json({ success: true, payments })
}
