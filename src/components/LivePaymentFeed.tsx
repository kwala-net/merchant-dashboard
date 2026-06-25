import React from 'react';
import type { Payment } from '@/types';

interface LivePaymentFeedProps {
  payments: Payment[];
}

// Status -> dot color
type DotVariant = 'green' | 'yellow' | 'red' | 'blue' | 'orange';

function getDotVariant(payment: Payment): DotVariant {
  if (payment.classification === 'HIGH_VALUE') return 'blue';
  if (payment.classification === 'SUSPICIOUS') return 'orange';
  if (payment.status === 'WEBHOOK_FAILED') return 'red';
  if (payment.status === 'WEBHOOK_DELIVERED' || payment.status === 'SYNCED') return 'green';
  return 'yellow';
}

const dotColors: Record<DotVariant, { fill: string; ring: string }> = {
  green:  { fill: '#22c55e', ring: 'rgba(34,197,94,0.18)' },
  yellow: { fill: '#eab308', ring: 'rgba(234,179,8,0.18)' },
  red:    { fill: '#ef4444', ring: 'rgba(239,68,68,0.18)' },
  blue:   { fill: '#60a5fa', ring: 'rgba(96,165,250,0.18)' },
  orange: { fill: '#f97316', ring: 'rgba(249,115,22,0.18)' },
};

function StatusDot({ variant, pulse }: { variant: DotVariant; pulse?: boolean }) {
  const { fill, ring } = dotColors[variant];
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: '20px',
        height: '20px',
        flexShrink: 0,
        position: 'relative',
      }}
    >
      {/* outer ring */}
      <span
        style={{
          position: 'absolute',
          width: '14px',
          height: '14px',
          borderRadius: '50%',
          background: ring,
          ...(pulse
            ? {
                animation: 'sonar-ring 2s ease-out infinite',
              }
            : {}),
        }}
      />
      {/* inner dot */}
      <span
        style={{
          position: 'relative',
          width: '7px',
          height: '7px',
          borderRadius: '50%',
          background: fill,
          flexShrink: 0,
        }}
      />
    </span>
  );
}

function formatTimeAgo(timestamp: number): string {
  const diffMs = Date.now() - timestamp;
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return 'just now';
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  return `${Math.floor(diffHr / 24)}d ago`;
}

function statusLabel(payment: Payment): string {
  const s = payment.status;
  if (s === 'WEBHOOK_DELIVERED') return 'webhook delivered';
  if (s === 'WEBHOOK_FAILED') return `webhook failed · retry ${payment.webhookRetryCount}/5`;
  if (s === 'SYNCED') return 'synced';
  if (s === 'CONFIRMED') return 'confirmed';
  if (s === 'PENDING') return 'pending';
  if (s === 'REFUNDED') return 'refunded';
  if (s === 'CLASSIFIED') return 'classified';
  return s.toLowerCase();
}

function ClassificationBadge({ classification }: { classification: string }) {
  if (classification === 'HIGH_VALUE') {
    return (
      <span
        style={{
          fontSize: '9px',
          fontWeight: 700,
          letterSpacing: '0.1em',
          color: '#60a5fa',
          background: 'rgba(96,165,250,0.1)',
          border: '1px solid rgba(96,165,250,0.3)',
          borderRadius: '4px',
          padding: '1px 5px',
          textTransform: 'uppercase',
          fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
          whiteSpace: 'nowrap',
        }}
      >
        HIGH VALUE
      </span>
    );
  }
  if (classification === 'SUSPICIOUS') {
    return (
      <span
        style={{
          fontSize: '9px',
          fontWeight: 700,
          letterSpacing: '0.1em',
          color: '#f97316',
          background: 'rgba(249,115,22,0.1)',
          border: '1px solid rgba(249,115,22,0.3)',
          borderRadius: '4px',
          padding: '1px 5px',
          textTransform: 'uppercase',
          fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
          whiteSpace: 'nowrap',
        }}
      >
        SUSPICIOUS
      </span>
    );
  }
  return null;
}

export default function LivePaymentFeed({ payments }: LivePaymentFeedProps) {
  const top5 = payments.slice(0, 5);

  return (
    <div
      style={{
        background: '#111111',
        border: '1px solid #1e1e1e',
        borderRadius: '12px',
        overflow: 'hidden',
      }}
    >
      {/* Keyframes injected inline */}
      <style>{`
        @keyframes sonar-ring {
          0%   { transform: scale(1);   opacity: 0.7; }
          70%  { transform: scale(2);   opacity: 0; }
          100% { transform: scale(2);   opacity: 0; }
        }
        @media (prefers-reduced-motion: reduce) {
          .sonar-ring { animation: none !important; }
        }
      `}</style>

      {/* Header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          padding: '16px 20px',
          borderBottom: '1px solid #1e1e1e',
        }}
      >
        {/* Pulsing live dot */}
        <span
          style={{
            position: 'relative',
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: '16px',
            height: '16px',
            flexShrink: 0,
          }}
        >
          <span
            style={{
              position: 'absolute',
              width: '12px',
              height: '12px',
              borderRadius: '50%',
              background: 'rgba(34,197,94,0.25)',
              animation: 'sonar-ring 1.8s ease-out infinite',
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
            fontSize: '10px',
            fontWeight: 700,
            letterSpacing: '0.14em',
            textTransform: 'uppercase',
            color: '#6b7280',
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
          }}
        >
          Live Payment Feed
        </span>
      </div>

      {/* Payment rows */}
      <div>
        {top5.map((p, i) => {
          const variant = getDotVariant(p);
          const isPulse = variant === 'green' && i === 0;
          return (
            <div
              key={p.paymentId}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '12px',
                padding: '12px 20px',
                borderBottom: i < top5.length - 1 ? '1px solid #1a1a1a' : 'none',
              }}
            >
              {/* Status dot */}
              <StatusDot variant={variant} pulse={isPulse} />

              {/* Middle: address, badge, meta */}
              <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: '3px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                  <span
                    style={{
                      fontSize: '13px',
                      fontWeight: 600,
                      color: '#e5e5e5',
                      fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
                      letterSpacing: '0.01em',
                    }}
                  >
                    {p.payer}
                  </span>
                  <ClassificationBadge classification={p.classification} />
                </div>
                <span
                  style={{
                    fontSize: '11px',
                    color: '#6b7280',
                    fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
                    letterSpacing: '0.02em',
                  }}
                >
                  {formatTimeAgo(p.timestamp * 1000)} · {statusLabel(p)}
                </span>
              </div>

              {/* Right: amount */}
              <span
                style={{
                  fontSize: '14px',
                  fontWeight: 700,
                  color: '#e5e5e5',
                  fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
                  letterSpacing: '-0.01em',
                  whiteSpace: 'nowrap',
                  flexShrink: 0,
                }}
              >
                ${(p.amount / 1e6).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
