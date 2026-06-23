import { NextRequest, NextResponse } from 'next/server'

interface InitiateRefundBody {
  paymentId: string
  amount: number
  reason: string
  requestedBy: string
}

function generateRefundId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
  let suffix = ''
  for (let i = 0; i < 8; i++) {
    suffix += chars[Math.floor(Math.random() * chars.length)]
  }
  return `ref_${suffix}`
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Partial<InitiateRefundBody>

  try {
    body = await request.json()
  } catch {
    return NextResponse.json(
      { success: false, error: 'Invalid JSON body' },
      { status: 400 }
    )
  }

  const { paymentId, amount, reason, requestedBy } = body

  const missingFields: string[] = []
  if (!paymentId) missingFields.push('paymentId')
  if (amount === undefined || amount === null) missingFields.push('amount')

  if (missingFields.length > 0) {
    return NextResponse.json(
      { success: false, error: `Missing required fields: ${missingFields.join(', ')}` },
      { status: 400 }
    )
  }

  if (typeof amount !== 'number' || amount <= 0) {
    return NextResponse.json(
      { success: false, error: 'amount must be a positive number' },
      { status: 400 }
    )
  }

  return NextResponse.json({
    success: true,
    refundId: generateRefundId(),
    paymentId,
    amount,
    reason: reason ?? null,
    requestedBy: requestedBy ?? null,
    status: 'REQUESTED',
    requestedAt: Date.now(),
  })
}
