import React from 'react';

export interface KwalaEvent {
  id: string;
  name: string;
  subtitle: string;
  tag: string;
  tagColor: string;
  status: string;
}

interface KwalaWorkflowEventsProps {
  events: KwalaEvent[];
}

type TagVariant = 'trigger' | 'fn' | 'event' | 'sync' | 'retry';

interface TagStyle {
  color: string;
  bg: string;
  border: string;
}

const tagStyles: Record<TagVariant, TagStyle> = {
  trigger: {
    color: '#22c55e',
    bg: 'transparent',
    border: 'rgba(34,197,94,0.5)',
  },
  fn: {
    color: '#60a5fa',
    bg: 'transparent',
    border: 'rgba(96,165,250,0.5)',
  },
  event: {
    color: '#c084fc',
    bg: 'transparent',
    border: 'rgba(192,132,252,0.5)',
  },
  sync: {
    color: '#111111',
    bg: '#22c55e',
    border: '#22c55e',
  },
  retry: {
    color: '#fff',
    bg: '#ef4444',
    border: '#ef4444',
  },
};

function TagBadge({ tag }: { tag: string }) {
  const style = tagStyles[tag as TagVariant] ?? {
    color: '#9ca3af',
    bg: 'transparent',
    border: 'rgba(156,163,175,0.4)',
  };

  return (
    <span
      style={{
        display: 'inline-block',
        fontSize: '9px',
        fontWeight: 700,
        letterSpacing: '0.1em',
        textTransform: 'uppercase',
        fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
        padding: '2px 7px',
        borderRadius: '4px',
        background: style.bg,
        border: `1px solid ${style.border}`,
        color: style.color,
        whiteSpace: 'nowrap',
        flexShrink: 0,
      }}
    >
      {tag}
    </span>
  );
}

function StatusDot({ status }: { status: string }) {
  let color = '#22c55e';
  if (status === 'failed')  color = '#ef4444';
  if (status === 'pending') color = '#eab308';
  if (status === 'warning') color = '#f97316';

  return (
    <span
      style={{
        width: '7px',
        height: '7px',
        borderRadius: '50%',
        background: color,
        flexShrink: 0,
        marginTop: '3px',
      }}
    />
  );
}

// Connector line between events (visual chain)
function ConnectorLine() {
  return (
    <div
      style={{
        position: 'absolute',
        left: '23px',
        top: '20px',
        bottom: '-4px',
        width: '1px',
        background:
          'linear-gradient(to bottom, rgba(55,65,81,0.8), rgba(55,65,81,0.1))',
      }}
    />
  );
}

export default function KwalaWorkflowEvents({ events }: KwalaWorkflowEventsProps) {
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
          Kwala Workflow Events
        </span>
      </div>

      {/* Event list */}
      <div style={{ padding: '8px 0 4px' }}>
        {events.map((ev, i) => (
          <div
            key={ev.id}
            style={{
              position: 'relative',
              display: 'flex',
              alignItems: 'flex-start',
              gap: '12px',
              padding: '12px 20px',
            }}
          >
            {/* Connector line between events */}
            {i < events.length - 1 && <ConnectorLine />}

            {/* Status dot column */}
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                paddingTop: '1px',
                width: '16px',
                flexShrink: 0,
                zIndex: 1,
              }}
            >
              {/* Dot sits on the connector */}
              <span
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: '16px',
                  height: '16px',
                  borderRadius: '50%',
                  background: '#1a1a1a',
                  border: '1px solid #272727',
                  flexShrink: 0,
                }}
              >
                <StatusDot status={ev.status} />
              </span>
            </div>

            {/* Content */}
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: '3px' }}>
              <span
                style={{
                  fontSize: '13px',
                  fontWeight: 600,
                  color: ev.status === 'failed' ? '#fca5a5' : '#e5e5e5',
                  fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
                  letterSpacing: '0.01em',
                  lineHeight: 1.3,
                }}
              >
                {ev.name}
              </span>
              <span
                style={{
                  fontSize: '11px',
                  color: '#6b7280',
                  fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
                  letterSpacing: '0.02em',
                  lineHeight: 1.4,
                }}
              >
                {ev.subtitle}
              </span>
            </div>

            {/* Tag */}
            <div style={{ paddingTop: '1px', flexShrink: 0 }}>
              <TagBadge tag={ev.tag} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
