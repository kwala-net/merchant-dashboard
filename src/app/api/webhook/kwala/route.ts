import { NextRequest, NextResponse } from 'next/server'

interface KwalaWebhookBody {
  paymentId: string
  event: string
  data: unknown
  signature: string
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Partial<KwalaWebhookBody>

  try {
    body = await request.json()
  } catch {
    return NextResponse.json(
      { received: false, error: 'Invalid JSON body' },
      { status: 400 }
    )
  }

  const { paymentId, event, data, signature } = body

  if (!signature) {
    return NextResponse.json(
      { received: false, error: 'Missing required field: signature' },
      { status: 400 }
    )
  }

  if (!paymentId || !event) {
    return NextResponse.json(
      { received: false, error: 'Missing required fields: paymentId, event' },
      { status: 400 }
    )
  }

  // Simulate 20% failure rate
  if (Math.random() < 0.2) {
    return NextResponse.json(
      { received: false, error: 'Upstream webhook processing failed' },
      { status: 502 }
    )
  }

  return NextResponse.json({
    received: true,
    paymentId,
    event,
    data: data ?? null,
    processedAt: Date.now(),
  })
}
