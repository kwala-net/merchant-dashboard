export interface Payment {
  paymentId: string
  payer: string
  merchant: string
  amount: number
  tokenAddress: string
  timestamp: number
  blockNumber: number
  status: 'PENDING'|'CONFIRMED'|'CLASSIFIED'|'SYNCED'|'WEBHOOK_DELIVERED'|'WEBHOOK_FAILED'|'REFUNDED'|'DISPUTED'
  classification: 'UNCLASSIFIED'|'STANDARD'|'HIGH_VALUE'|'SUSPICIOUS'|'BLOCKED'
  txHash: string
  metadata: string
  webhookRetryCount: number
  lastWebhookAttempt: number
  syncedAt: number
  syncLatencyMs: number
  refunded: boolean
  refundAmount: number
  countryCode: string
  currencyCode: string
  processorFee: number
  networkFee: number
}

export interface SyncStatusData {
  paymentEventsCapture: { completed: number; total: number }
  kwalaFunctionProcessed: { completed: number; total: number }
  backendDbSynced: { completed: number; total: number }
  webhookDelivered: { completed: number; total: number }
  merchantDashboardUpdated: { completed: number; total: number }
  pendingKwalaRetry: number
  avgSyncLatencyMs: number
}

export interface VolumeDataPoint {
  hour: string
  usdcVolume: number
  txCount: number
}

export interface ApiEndpoint {
  method: 'GET'|'POST'|'PUT'|'DELETE'
  endpoint: string
  statusCode: number
  latencyMs: number | null
  healthy: boolean
  slow?: boolean
}

export interface KwalaEvent {
  id: string
  name: string
  subtitle: string
  tag: string
  tagColor: 'green'|'blue'|'purple'|'red'|'yellow'
  status: 'success'|'failed'|'pending'
}

export interface MerchantStats {
  volume24h: number
  volume24hChange: number
  totalPayments: number
  successRate: number
  webhookCalls: number
  webhookFailed: number
  syncLagMs: number
  merchantAddress: string
  merchantName: string
  tier: string
}
