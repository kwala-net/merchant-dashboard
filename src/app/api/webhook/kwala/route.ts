import { NextRequest, NextResponse } from 'next/server'
import fs from 'fs'
import path from 'path'

const WEBHOOK_LOG_FILE = path.join(process.cwd(), 'src/data/webhookAttempts.json')

interface KwalaWebhookBody {
  paymentId: string
  event: string
  data: unknown
  signature: string
}

interface WebhookAttempt {
  id: string
  paymentId: string
  event: string
  data: unknown
  receivedAt: number
  success: boolean
  error?: string
}

function readAttempts(): WebhookAttempt[] {
  try {
    const raw = fs.readFileSync(WEBHOOK_LOG_FILE, 'utf8')
    return JSON.parse(raw) as WebhookAttempt[]
  } catch {
    return []
  }
}

function appendAttempt(attempt: WebhookAttempt): void {
  const attempts = readAttempts()
  attempts.unshift(attempt)
  fs.writeFileSync(WEBHOOK_LOG_FILE, JSON.stringify(attempts, null, 2), 'utf8')
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

  const receivedAt = Date.now()
  const attemptId = `wh_${paymentId}_${receivedAt}`

  // Simulate 20% failure rate for retry resilience testing
  if (Math.random() < 0.2) {
    appendAttempt({
      id: attemptId,
      paymentId,
      event,
      data: data ?? null,
      receivedAt,
      success: false,
      error: 'Upstream webhook processing failed',
    })
    return NextResponse.json(
      { received: false, error: 'Upstream webhook processing failed' },
      { status: 502 }
    )
  }

  appendAttempt({
    id: attemptId,
    paymentId,
    event,
    data: data ?? null,
    receivedAt,
    success: true,
  })

  return NextResponse.json({
    received: true,
    paymentId,
    event,
    data: data ?? null,
    processedAt: receivedAt,
  })
}
