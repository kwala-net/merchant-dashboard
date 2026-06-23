import React from 'react';

export interface SyncStatusData {
  paymentEventsCapture: { completed: number; total: number };
  kwalaFunctionProcessed: { completed: number; total: number };
  backendDbSynced: { completed: number; total: number };
  webhookDelivered: { completed: number; total: number };
  merchantDashboardUpdated: { completed: number; total: number };
  pendingKwalaRetry: number;
  avgSyncLatencyMs: number;
}

interface SyncStatusProps {
  syncData: SyncStatusData;
}

interface SyncStage {
  label: string;
  key: keyof Omit<SyncStatusData, 'pendingKwalaRetry' | 'avgSyncLatencyMs'>;
}

const STAGES: SyncStage[] = [
  { label: 'Payment events captured', key: 'paymentEventsCapture' },
  { label: 'Kwala fn processed',      key: 'kwalaFunctionProcessed' },
  { label: 'Backend DB synced',        key: 'backendDbSynced' },
  { label: 'Webhook delivered',        key: 'webhookDelivered' },
  { label: 'Dashboard updated',        key: 'merchantDashboardUpdated' },
];

function barColor(pct: number): string {
  if (pct >= 100) return '#22c55e';
  if (pct >= 95)  return '#eab308';
  return '#f97316';
}

function ProgressRow({
  label,
  completed,
  total,
}: {
  label: string;
  completed: number;
  total: number;
}) {
  const pct = total === 0 ? 0 : Math.round((completed / total) * 100);
  const fill = barColor(pct);
  const widthPct = `${Math.min(pct, 100)}%`;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
      {/* Label row */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'baseline',
          gap: '8px',
        }}
      >
        <span
          style={{
            fontSize: '11px',
            color: '#9ca3af',
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
            letterSpacing: '0.02em',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {label}
        </span>
        <span
          style={{
            fontSize: '11px',
            fontWeight: 600,
            color: fill,
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
            whiteSpace: 'nowrap',
            flexShrink: 0,
          }}
        >
          {completed} / {total}
        </span>
      </div>

      {/* Progress bar */}
      <div
        style={{
          height: '4px',
          borderRadius: '2px',
          background: '#1e1e1e',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            height: '100%',
            width: widthPct,
            borderRadius: '2px',
            background: fill,
            transition: 'width 0.4s ease',
          }}
        />
      </div>
    </div>
  );
}

export default function SyncStatus({ syncData }: SyncStatusProps) {
  return (
    <div
      style={{
        background: '#111111',
        border: '1px solid #1e1e1e',
        borderRadius: '12px',
        overflow: 'hidden',
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: '16px 20px',
          borderBottom: '1px solid #1e1e1e',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '8px',
        }}
      >
        <span
          style={{
            fontSize: '10px',
            fontWeight: 700,
            letterSpacing: '0.14em',
            textTransform: 'uppercase',
            color: '#6b7280',
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
          }}
        >
          Onchain → Offchain Sync
        </span>
        <span
          style={{
            fontSize: '10px',
            fontWeight: 500,
            color: '#6b7280',
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
            letterSpacing: '0.05em',
          }}
        >
          avg {syncData.avgSyncLatencyMs}ms
        </span>
      </div>

      {/* Stages */}
      <div
        style={{
          padding: '16px 20px',
          display: 'flex',
          flexDirection: 'column',
          gap: '14px',
        }}
      >
        {STAGES.map((stage) => {
          const bucket = syncData[stage.key] as { completed: number; total: number };
          return (
            <ProgressRow
              key={stage.key}
              label={stage.label}
              completed={bucket.completed}
              total={bucket.total}
            />
          );
        })}
      </div>

      {/* Footer */}
      <div
        style={{
          padding: '12px 20px',
          borderTop: '1px solid #1e1e1e',
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
        }}
      >
        <span
          style={{
            width: '6px',
            height: '6px',
            borderRadius: '50%',
            background: '#f97316',
            flexShrink: 0,
          }}
        />
        <span
          style={{
            fontSize: '11px',
            color: '#9ca3af',
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
            letterSpacing: '0.02em',
          }}
        >
          {syncData.pendingKwalaRetry} events pending Kwala retry
          <span style={{ color: '#6b7280' }}> (RetriesUntilSuccess: 5)</span>
        </span>
      </div>
    </div>
  );
}
