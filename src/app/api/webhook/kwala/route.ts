import { NextRequest, NextResponse } from 'next/server'
import { redis } from '@/lib/redis'

const WEBHOOK_KEY = 'webhookAttempts'

interface WebhookAttempt {
  id: string
  paymentId: string
  event: string
  data: unknown
  receivedAt: number
  success: boolean
  error?: string
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

async function appendAttempt(attempt: WebhookAttempt): Promise<void> {
  await redis.lpush(WEBHOOK_KEY, attempt)
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Record<string, unknown> = {}
  try {
    body = parseBody(await request.json())
  } catch {
    // unparseable body — still log and respond
  }

  const paymentId = String(body.paymentId ?? '')
  const event     = String(body.event ?? 'PaymentClassified')
  const data      = body.data ?? null

  const receivedAt = Date.now()
  const attemptId  = `wh_${paymentId || 'unknown'}_${receivedAt}`

  // Simulate 20% failure rate for retry resilience testing
  if (Math.random() < 0.2) {
    await appendAttempt({ id: attemptId, paymentId, event, data, receivedAt, success: false, error: 'Simulated upstream failure' })
    return NextResponse.json({ received: false, error: 'Simulated upstream failure' }, { status: 502 })
  }

  await appendAttempt({ id: attemptId, paymentId, event, data, receivedAt, success: true })

  return NextResponse.json({ received: true, paymentId, event, processedAt: receivedAt })
}
