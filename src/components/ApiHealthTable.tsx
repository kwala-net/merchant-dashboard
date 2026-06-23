import React from 'react';

export interface ApiEndpoint {
  method: string;
  endpoint: string;
  statusCode: number | null;
  latencyMs: number | null;
  healthy: boolean;
  slow?: boolean;
}

interface ApiHealthTableProps {
  endpoints: ApiEndpoint[];
}

function MethodBadge({ method }: { method: string }) {
  const isPost = method === 'POST';
  return (
    <span
      style={{
        display: 'inline-block',
        fontSize: '9px',
        fontWeight: 700,
        letterSpacing: '0.08em',
        textTransform: 'uppercase',
        fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
        padding: '2px 6px',
        borderRadius: '4px',
        background: isPost ? 'rgba(96,165,250,0.12)' : 'rgba(34,197,94,0.12)',
        border: `1px solid ${isPost ? 'rgba(96,165,250,0.35)' : 'rgba(34,197,94,0.35)'}`,
        color: isPost ? '#60a5fa' : '#22c55e',
        whiteSpace: 'nowrap',
        minWidth: '36px',
        textAlign: 'center',
      }}
    >
      {method}
    </span>
  );
}

function StatusBadge({ code }: { code: number | null }) {
  if (code === null) {
    return (
      <span
        style={{
          fontSize: '12px',
          color: '#4b5563',
          fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
        }}
      >
        —
      </span>
    );
  }

  let color = '#22c55e';
  let bg = 'rgba(34,197,94,0.1)';
  let border = 'rgba(34,197,94,0.3)';
  if (code >= 500) {
    color = '#ef4444';
    bg = 'rgba(239,68,68,0.1)';
    border = 'rgba(239,68,68,0.3)';
  } else if (code >= 400) {
    color = '#eab308';
    bg = 'rgba(234,179,8,0.1)';
    border = 'rgba(234,179,8,0.3)';
  }

  return (
    <span
      style={{
        display: 'inline-block',
        fontSize: '11px',
        fontWeight: 700,
        fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
        padding: '2px 6px',
        borderRadius: '4px',
        background: bg,
        border: `1px solid ${border}`,
        color,
        whiteSpace: 'nowrap',
      }}
    >
      {code}
    </span>
  );
}

function LatencyCell({ latencyMs, slow }: { latencyMs: number | null; slow?: boolean }) {
  if (latencyMs === null) {
    return (
      <span
        style={{
          fontSize: '12px',
          color: '#4b5563',
          fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
        }}
      >
        —
      </span>
    );
  }

  const isWarning = latencyMs > 1000 || slow;
  const textColor = isWarning ? '#eab308' : '#9ca3af';

  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '4px',
        fontSize: '12px',
        fontWeight: isWarning ? 600 : 400,
        color: textColor,
        fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
        whiteSpace: 'nowrap',
      }}
    >
      {isWarning && (
        <svg
          width="12"
          height="12"
          viewBox="0 0 12 12"
          fill="none"
          aria-label="Slow response"
          style={{ flexShrink: 0 }}
        >
          <path
            d="M6 1L11 10H1L6 1Z"
            stroke="#eab308"
            strokeWidth="1"
            strokeLinejoin="round"
            fill="rgba(234,179,8,0.12)"
          />
          <line x1="6" y1="4.5" x2="6" y2="7" stroke="#eab308" strokeWidth="1" strokeLinecap="round" />
          <circle cx="6" cy="8.5" r="0.6" fill="#eab308" />
        </svg>
      )}
      {latencyMs}ms
    </span>
  );
}

export default function ApiHealthTable({ endpoints }: ApiHealthTableProps) {
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
          API Health
        </span>
      </div>

      {/* Scrollable table wrapper */}
      <div style={{ overflowX: 'auto' }}>
        <table
          style={{
            width: '100%',
            borderCollapse: 'collapse',
            tableLayout: 'fixed',
            minWidth: '480px',
          }}
        >
          <thead>
            <tr>
              {(['Method', 'Endpoint', 'Status', 'Latency'] as const).map((col) => (
                <th
                  key={col}
                  style={{
                    padding: '8px 20px',
                    textAlign: 'left',
                    fontSize: '9px',
                    fontWeight: 700,
                    letterSpacing: '0.12em',
                    textTransform: 'uppercase',
                    color: '#4b5563',
                    fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
                    borderBottom: '1px solid #1a1a1a',
                    width:
                      col === 'Method'   ? '80px' :
                      col === 'Endpoint' ? 'auto'  :
                      col === 'Status'   ? '80px'  :
                                           '90px',
                  }}
                >
                  {col}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {endpoints.map((ep, i) => (
              <tr
                key={`${ep.method}-${ep.endpoint}`}
                style={{
                  borderBottom: i < endpoints.length - 1 ? '1px solid #161616' : 'none',
                  background: ep.healthy ? 'transparent' : 'rgba(239,68,68,0.03)',
                }}
              >
                <td style={{ padding: '11px 20px' }}>
                  <MethodBadge method={ep.method} />
                </td>
                <td style={{ padding: '11px 20px' }}>
                  <span
                    style={{
                      fontSize: '12px',
                      color: '#e5e5e5',
                      fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
                      letterSpacing: '0.01em',
                    }}
                  >
                    {ep.endpoint}
                  </span>
                </td>
                <td style={{ padding: '11px 20px' }}>
                  <StatusBadge code={ep.statusCode} />
                </td>
                <td style={{ padding: '11px 20px' }}>
                  <LatencyCell latencyMs={ep.latencyMs} slow={ep.slow} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
