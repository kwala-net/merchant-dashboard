'use client'

import {
  StatsCard,
  LivePaymentFeed,
  SyncStatus,
  VolumeChart,
  ApiHealthTable,
  KwalaWorkflowEvents,
} from '@/components'

import type { Payment, SyncStatusData, VolumeDataPoint, ApiEndpoint, KwalaEvent, MerchantStats } from '@/types'

import merchantStats from '@/data/merchantStats.json'
import payments from '@/data/payments.json'
import syncStatus from '@/data/syncStatus.json'
import volumeChart from '@/data/volumeChart.json'
import apiHealth from '@/data/apiHealth.json'
import kwalaEvents from '@/data/kwalaEvents.json'

const stats = merchantStats as MerchantStats
const paymentsData = payments as Payment[]
const syncData = syncStatus as SyncStatusData
const volumeData = volumeChart as VolumeDataPoint[]
const apiEndpoints = apiHealth as ApiEndpoint[]
const kwalaEventsData = kwalaEvents as KwalaEvent[]

export default function DashboardPage() {
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
        {/* Left: Brand */}
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

        {/* Right: Kwala live badge */}
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
          {/* Pulsing green dot */}
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

      {/* Main Content */}
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

        {/* Middle Row: Live Payment Feed | Sync Status */}
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

        {/* Full-width Volume Chart */}
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

        {/* Bottom Row: API Health | Kwala Workflow Events */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
            gap: '16px',
          }}
        >
          <ApiHealthTable endpoints={apiEndpoints} />
          <KwalaWorkflowEvents events={kwalaEventsData} />
        </div>
      </main>
    </div>
  )
}
