import { NextRequest, NextResponse } from 'next/server'

interface MerchantBalance {
  merchant: string
  balance: number
  currency: string
  pendingRefunds: number
  lastUpdated: number
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  const { searchParams } = new URL(request.url)
  const merchant = searchParams.get('merchant')

  if (!merchant) {
    return NextResponse.json(
      { success: false, error: 'Missing required query param: merchant' },
      { status: 400 }
    )
  }

  const balanceData: MerchantBalance = {
    merchant,
    balance: 84210,
    currency: 'USDC',
    pendingRefunds: 320,
    lastUpdated: Date.now(),
  }

  return NextResponse.json({ success: true, ...balanceData })
}
