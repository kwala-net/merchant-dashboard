import { NextRequest, NextResponse } from 'next/server'

import type { Payment } from '@/types'

type MockPayment = Pick<Payment, 'paymentId'|'txHash'|'amount'|'payer'|'merchant'|'status'|'classification'> & {
  createdAt: number
}

const MOCK_PAYMENTS: MockPayment[] = [
  {
    paymentId: 'pay_001',
    txHash: '0xabc123',
    amount: 1500,
    payer: '0xPayer1',
    merchant: '0xMerchant1',
    status: 'WEBHOOK_DELIVERED',
    classification: 'STANDARD',
    createdAt: Date.now() - 86400000,
  },
  {
    paymentId: 'pay_002',
    txHash: '0xdef456',
    amount: 3200,
    payer: '0xPayer2',
    merchant: '0xMerchant1',
    status: 'PENDING',
    classification: 'HIGH_VALUE',
    createdAt: Date.now() - 43200000,
  },
  {
    paymentId: 'pay_003',
    txHash: '0xghi789',
    amount: 800,
    payer: '0xPayer3',
    merchant: '0xMerchant2',
    status: 'WEBHOOK_FAILED',
    classification: 'SUSPICIOUS',
    createdAt: Date.now() - 21600000,
  },
]

export async function GET(request: NextRequest): Promise<NextResponse> {
  const { searchParams } = new URL(request.url)
  const paymentId = searchParams.get('paymentId')

  if (!paymentId) {
    return NextResponse.json(
      { success: false, error: 'Missing required query param: paymentId' },
      { status: 400 }
    )
  }

  const payment = MOCK_PAYMENTS.find((p) => p.paymentId === paymentId)

  if (!payment) {
    return NextResponse.json(
      { success: false, error: `Payment not found: ${paymentId}` },
      { status: 404 }
    )
  }

  return NextResponse.json({ success: true, payment })
}
