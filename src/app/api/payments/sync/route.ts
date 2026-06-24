import { NextRequest, NextResponse } from 'next/server'

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

  const { paymentId, txHash, amount, payer, merchant, classification, syncLatencyMs, dbSynced, webhookDelivered } = body

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

  return NextResponse.json({
    success: true,
    paymentId,
    syncedAt: Date.now(),
    message: 'Payment synced',
  })
}

export async function GET(): Promise<NextResponse> {
  const payments = [
    {
      paymentId: 'pay_001',
      txHash: '0xabc123',
      amount: 1500,
      payer: '0xPayer1',
      merchant: '0xMerchant1',
      classification: 'STANDARD',
      syncLatencyMs: 120,
      dbSynced: true,
      webhookDelivered: true,
      syncedAt: Date.now() - 60000,
    },
    {
      paymentId: 'pay_002',
      txHash: '0xdef456',
      amount: 3200,
      payer: '0xPayer2',
      merchant: '0xMerchant1',
      classification: 'HIGH_VALUE',
      syncLatencyMs: 95,
      dbSynced: true,
      webhookDelivered: false,
      syncedAt: Date.now() - 120000,
    },
    {
      paymentId: 'pay_003',
      txHash: '0xghi789',
      amount: 800,
      payer: '0xPayer3',
      merchant: '0xMerchant2',
      classification: 'STANDARD',
      syncLatencyMs: 200,
      dbSynced: true,
      webhookDelivered: true,
      syncedAt: Date.now() - 300000,
    },
  ]

  return NextResponse.json({ success: true, payments })
}
