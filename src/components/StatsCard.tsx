import React from 'react';

type SubtitleColor = 'green' | 'red' | 'yellow' | 'muted';

interface StatsCardProps {
  title: string;
  value: string;
  subtitle?: string;
  subtitleColor?: SubtitleColor;
  icon?: React.ReactNode;
}

const subtitleColorMap: Record<SubtitleColor, string> = {
  green: '#22c55e',
  red:   '#ef4444',
  yellow:'#eab308',
  muted: '#6b7280',
};

export default function StatsCard({
  title,
  value,
  subtitle,
  subtitleColor = 'muted',
  icon,
}: StatsCardProps) {
  const subtitleHex = subtitleColorMap[subtitleColor];

  return (
    <div
      style={{
        background: '#111111',
        border: '1px solid #1e1e1e',
        borderRadius: '12px',
        padding: '20px',
        display: 'flex',
        flexDirection: 'column',
        gap: '10px',
        minWidth: 0,
      }}
    >
      {/* Header row */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '8px',
        }}
      >
        <span
          style={{
            fontSize: '10px',
            fontWeight: 600,
            letterSpacing: '0.12em',
            textTransform: 'uppercase',
            color: '#6b7280',
            fontVariantCaps: 'small-caps',
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
            lineHeight: 1,
          }}
        >
          {title}
        </span>
        {icon && (
          <span
            style={{
              color: '#6b7280',
              display: 'flex',
              alignItems: 'center',
              flexShrink: 0,
            }}
          >
            {icon}
          </span>
        )}
      </div>

      {/* Value */}
      <span
        style={{
          fontSize: 'clamp(22px, 3.5vw, 30px)',
          fontWeight: 700,
          color: '#e5e5e5',
          lineHeight: 1.1,
          letterSpacing: '-0.02em',
          fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
          wordBreak: 'break-all',
        }}
      >
        {value}
      </span>

      {/* Subtitle */}
      {subtitle && (
        <span
          style={{
            fontSize: '12px',
            fontWeight: 500,
            color: subtitleHex,
            lineHeight: 1.4,
            fontFamily: '"ui-monospace", "Cascadia Code", "Source Code Pro", Menlo, monospace',
            letterSpacing: '0.02em',
          }}
        >
          {subtitle}
        </span>
      )}
    </div>
  );
}
