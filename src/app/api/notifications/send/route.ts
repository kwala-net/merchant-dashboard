import { NextRequest, NextResponse } from 'next/server'

interface SendNotificationBody {
  type: string
  message: string
  merchantId: string
  severity: 'info' | 'warning' | 'error' | 'critical'
}

function generateNotificationId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
  let suffix = ''
  for (let i = 0; i < 10; i++) {
    suffix += chars[Math.floor(Math.random() * chars.length)]
  }
  return `notif_${suffix}`
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Partial<SendNotificationBody>

  try {
    body = await request.json()
  } catch {
    return NextResponse.json(
      { success: false, error: 'Invalid JSON body' },
      { status: 400 }
    )
  }

  const { type, message, merchantId, severity } = body

  const missingFields: string[] = []
  if (!type) missingFields.push('type')
  if (!message) missingFields.push('message')
  if (!merchantId) missingFields.push('merchantId')
  if (!severity) missingFields.push('severity')

  if (missingFields.length > 0) {
    return NextResponse.json(
      { success: false, error: `Missing required fields: ${missingFields.join(', ')}` },
      { status: 400 }
    )
  }

  return NextResponse.json({
    success: true,
    notificationId: generateNotificationId(),
    type,
    message,
    merchantId,
    severity,
    sent: true,
    channel: 'webhook',
    sentAt: Date.now(),
  })
}
