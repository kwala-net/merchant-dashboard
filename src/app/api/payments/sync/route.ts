import { NextRequest, NextResponse } from 'next/server'
import fs from 'fs'
import path from 'path'

import type { Payment } from '@/types'

const PAYMENTS_FILE = path.join(process.cwd(), 'src/data/payments.json')

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

function readPayments(): Payment[] {
  try {
    const raw = fs.readFileSync(PAYMENTS_FILE, 'utf8')
    return JSON.parse(raw) as Payment[]
  } catch {
    return []
  }
}

function writePayments(payments: Payment[]): void {
  fs.writeFileSync(PAYMENTS_FILE, JSON.stringify(payments, null, 2), 'utf8')
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
    paymentId, txHash, amount, payer, merchant, classification,
    syncLatencyMs, dbSynced, webhookDelivered,
    tokenAddress, timestamp, blockNumber, metadata, countryCode, currencyCode,
  } = body

  const missingFields: string[] = []
  if (!paymentId) missingFields.push('paymentId')
  if (amount === undefined || amount === null) missingFields.push('amount')
  if (!payer) missingFields.push('payer')
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

  const payments = readPayments()
  const existingIdx = payments.findIndex((p) => p.paymentId === paymentId)

  const status: Payment['status'] = webhookDelivered
    ? 'WEBHOOK_DELIVERED'
    : dbSynced
      ? 'SYNCED'
      : 'CONFIRMED'

  if (existingIdx >= 0) {
    // Update existing record
    payments[existingIdx] = {
      ...payments[existingIdx],
      classification: classification!,
      status,
      syncLatencyMs: syncLatencyMs!,
      syncedAt,
      ...(txHash ? { txHash } : {}),
      ...(webhookDelivered !== undefined ? { webhookDelivered } : {}),
    }
  } else {
    // Insert new record from Kwala sync payload
    const newPayment: Payment = {
      paymentId: paymentId!,
      payer: payer!,
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
    payments.unshift(newPayment)
  }

  writePayments(payments)

  return NextResponse.json({
    success: true,
    paymentId,
    syncedAt,
    message: 'Payment synced',
  })
}

export async function GET(): Promise<NextResponse> {
  const payments = readPayments()
  return NextResponse.json({ success: true, payments })
}
