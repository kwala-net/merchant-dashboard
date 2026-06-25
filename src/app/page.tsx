import {
  StatsCard,
  LivePaymentFeed,
  SyncStatus,
  VolumeChart,
  KwalaWorkflowEvents,
} from '@/components'

import type { Payment, SyncStatusData, VolumeDataPoint, KwalaEvent, MerchantStats } from '@/types'
import { redis } from '@/lib/redis'

interface WebhookAttempt {
  id: string
  paymentId: string
  success: boolean
}

const CLASS_COLOR: Record<string, KwalaEvent['tagColor']> = {
  STANDARD: 'green',
  HIGH_VALUE: 'blue',
  SUSPICIOUS: 'red',
  BLOCKED: 'red',
  UNCLASSIFIED: 'yellow',
}

function computeStats(payments: Payment[], attempts: WebhookAttempt[]): MerchantStats {
  const nowMs = Date.now()
  const oneDayAgoMs = nowMs - 86_400_000

  const payments24h = payments.filter(p => p.timestamp * 1000 >= oneDayAgoMs)
  const volume24h = payments24h.reduce((s, p) => s + p.amount, 0) / 1e6

  const successful = payments.filter(p =>
    ['CONFIRMED', 'CLASSIFIED', 'SYNCED', 'WEBHOOK_DELIVERED'].includes(p.status)
  ).length
  const successRate = payments.length > 0 ? Math.round((successful / payments.length) * 100) : 100

  const withLatency = payments.filter(p => p.syncLatencyMs > 0)
  const avgSyncLag = withLatency.length > 0
    ? Math.round(withLatency.reduce((s, p) => s + p.syncLatencyMs, 0) / withLatency.length)
    : 0

  return {
    volume24h: Math.round(volume24h * 100) / 100,
    volume24hChange: 0,
    totalPayments: payments.length,
    successRate,
    webhookCalls: attempts.length,
    webhookFailed: attempts.filter(a => !a.success).length,
    syncLagMs: avgSyncLag,
    merchantAddress: payments[0]?.merchant ?? '',
    merchantName: 'Seed Merchant',
    tier: 'ENTERPRISE',
  }
}

function computeSyncStatus(payments: Payment[], attempts: WebhookAttempt[]): SyncStatusData {
  const total = payments.length
  if (total === 0) {
    return {
      paymentEventsCapture: { completed: 0, total: 0 },
      kwalaFunctionProcessed: { completed: 0, total: 0 },
      backendDbSynced: { completed: 0, total: 0 },
      webhookDelivered: { completed: 0, total: 0 },
      merchantDashboardUpdated: { completed: 0, total: 0 },
      pendingKwalaRetry: 0,
      avgSyncLatencyMs: 0,
    }
  }

  const classified = payments.filter(p => p.classification !== 'UNCLASSIFIED').length
  const dbSynced = payments.filter(p => p.syncedAt > 0).length
  const webhookDelivered = payments.filter(p => p.status === 'WEBHOOK_DELIVERED').length

  const withLatency = payments.filter(p => p.syncLatencyMs > 0)
  const avgSyncLatencyMs = withLatency.length > 0
    ? Math.round(withLatency.reduce((s, p) => s + p.syncLatencyMs, 0) / withLatency.length)
    : 0

  return {
    paymentEventsCapture: { completed: total, total },
    kwalaFunctionProcessed: { completed: classified, total },
    backendDbSynced: { completed: dbSynced, total },
    webhookDelivered: { completed: webhookDelivered, total },
    merchantDashboardUpdated: { completed: total, total },
    pendingKwalaRetry: attempts.filter(a => !a.success).length,
    avgSyncLatencyMs,
  }
}

function computeVolumeChart(payments: Payment[]): VolumeDataPoint[] {
  const nowMs = Date.now()
  return Array.from({ length: 12 }, (_, i) => {
    const bucketEndMs = nowMs - i * 3_600_000
    const bucketStartMs = bucketEndMs - 3_600_000
    const bucket = payments.filter(p => {
      const tsMs = p.timestamp * 1000
      return tsMs >= bucketStartMs && tsMs < bucketEndMs
    })
    return {
      hour: new Date(bucketEndMs).toLocaleTimeString('en-US', {
        hour: '2-digit', minute: '2-digit', hour12: false,
      }),
      usdcVolume: Math.round(bucket.reduce((s, p) => s + p.amount, 0) / 1e6 * 100) / 100,
      txCount: bucket.length,
    }
  }).reverse()
}

function computeKwalaEvents(payments: Payment[]): KwalaEvent[] {
  return payments.slice(0, 8).map(p => ({
    id: p.paymentId.slice(0, 18),
    name: p.classification === 'UNCLASSIFIED' ? 'PaymentReceived' : 'PaymentClassified',
    subtitle: `${(p.amount / 1e6).toFixed(2)} USDC · ${p.classification}`,
    tag: p.classification,
    tagColor: CLASS_COLOR[p.classification] ?? 'yellow',
    status: (
      p.status === 'WEBHOOK_DELIVERED' ? 'success' :
      p.status === 'WEBHOOK_FAILED' ? 'failed' :
      'pending'
    ) as KwalaEvent['status'],
  }))
}

export default async function DashboardPage() {
  const [paymentsData, attemptsData] = await Promise.all([
    redis.lrange<Payment>('payments', 0, -1),
    redis.lrange<WebhookAttempt>('webhookAttempts', 0, -1),
  ])

  const stats = computeStats(paymentsData, attemptsData)
  const syncData = computeSyncStatus(paymentsData, attemptsData)
  const volumeData = computeVolumeChart(paymentsData)
  const kwalaEventsData = computeKwalaEvents(paymentsData)

  return (
    <div
      style={{
        minHeight: '100vh',
        background: '#0a0a0a',
        color: '#e5e5e5',
        fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
      }}
    >
      {/* Top Header Bar */}
      <header
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '16px 24px',
          borderBottom: '1px solid #1e1e1e',
          background: '#0a0a0a',
          position: 'sticky',
          top: 0,
          zIndex: 10,
        }}
      >
        <span
          style={{
            fontWeight: 700,
            fontSize: '15px',
            color: '#ffffff',
            letterSpacing: '-0.01em',
          }}
        >
          OnchainPay — merchant dashboard
        </span>

        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '7px',
            background: '#0d2218',
            border: '1px solid rgba(34,197,94,0.25)',
            borderRadius: '9999px',
            padding: '5px 12px 5px 10px',
          }}
        >
          <span
            style={{
              position: 'relative',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '14px',
              height: '14px',
              flexShrink: 0,
            }}
          >
            <style>{`
              @keyframes kwala-pulse {
                0%   { transform: scale(1);   opacity: 0.7; }
                70%  { transform: scale(2.2); opacity: 0; }
                100% { transform: scale(2.2); opacity: 0; }
              }
            `}</style>
            <span
              style={{
                position: 'absolute',
                width: '10px',
                height: '10px',
                borderRadius: '50%',
                background: 'rgba(34,197,94,0.3)',
                animation: 'kwala-pulse 2s ease-out infinite',
              }}
            />
            <span
              style={{
                position: 'relative',
                width: '6px',
                height: '6px',
                borderRadius: '50%',
                background: '#22c55e',
              }}
            />
          </span>

          <span
            style={{
              fontSize: '12px',
              fontWeight: 600,
              color: '#22c55e',
              letterSpacing: '0.04em',
            }}
          >
            Kwala live
          </span>
        </div>
      </header>

      <main
        style={{
          maxWidth: '1400px',
          margin: '0 auto',
          padding: '24px',
          display: 'flex',
          flexDirection: 'column',
          gap: '20px',
        }}
      >
        {/* Stats Row */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
            gap: '16px',
          }}
        >
          <StatsCard
            title="Volume (24h)"
            value={`$${stats.volume24h.toLocaleString()}`}
            subtitle={`+${stats.volume24hChange}% vs yesterday`}
            subtitleColor="green"
          />
          <StatsCard
            title="Payments"
            value={stats.totalPayments.toString()}
            subtitle={`${stats.successRate}% success rate`}
            subtitleColor="green"
          />
          <StatsCard
            title="Webhook calls"
            value={stats.webhookCalls.toString()}
            subtitle={`${stats.webhookFailed} failed (retrying)`}
            subtitleColor="yellow"
          />
          <StatsCard
            title="Sync lag"
            value={`${(stats.syncLagMs / 1000).toFixed(1)}s`}
            subtitle="On-chain → off-chain avg"
            subtitleColor="muted"
          />
        </div>

        {/* Live Payment Feed | Sync Status */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
            gap: '16px',
          }}
        >
          <LivePaymentFeed payments={paymentsData} />
          <SyncStatus syncData={syncData} />
        </div>

        {/* Volume Chart */}
        <div
          style={{
            background: '#111111',
            border: '1px solid #1e1e1e',
            borderRadius: '12px',
            padding: '20px 24px',
          }}
        >
          <VolumeChart data={volumeData} />
        </div>

        {/* Kwala Workflow Events */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
            gap: '16px',
          }}
        >
          <KwalaWorkflowEvents events={kwalaEventsData} />
        </div>
      </main>
    </div>
  )
}
