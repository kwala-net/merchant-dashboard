'use client'

import {
  ComposedChart,
  Bar,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts'
import { VolumeDataPoint } from '@/types'

interface VolumeChartProps {
  data: VolumeDataPoint[]
}

function formatUSDC(value: number): string {
  if (value >= 1000) {
    return `$${(value / 1000).toFixed(1)}k`
  }
  return `$${value}`
}

export default function VolumeChart({ data }: VolumeChartProps) {
  return (
    <div className="w-full">
      <h2
        className="text-xs font-semibold tracking-widest mb-4"
        style={{ color: '#6b7280' }}
      >
        PAYMENT VOLUME &mdash; LAST 12 HOURS
      </h2>
      <ResponsiveContainer width="100%" height={280}>
        <ComposedChart
          data={data}
          margin={{ top: 8, right: 24, left: 8, bottom: 0 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" vertical={false} />
          <XAxis
            dataKey="hour"
            tick={{ fill: '#6b7280', fontSize: 11 }}
            axisLine={{ stroke: '#1e1e1e' }}
            tickLine={false}
          />
          <YAxis
            yAxisId="volume"
            orientation="left"
            tick={{ fill: '#6b7280', fontSize: 11 }}
            axisLine={false}
            tickLine={false}
            tickFormatter={formatUSDC}
            width={56}
          />
          <YAxis
            yAxisId="txCount"
            orientation="right"
            tick={{ fill: '#6b7280', fontSize: 11 }}
            axisLine={false}
            tickLine={false}
            width={40}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: '#111111',
              border: '1px solid #1e1e1e',
              borderRadius: '6px',
              color: '#d1d5db',
              fontSize: 12,
            }}
            labelStyle={{ color: '#9ca3af', marginBottom: 4 }}
            formatter={(value: number, name: string) => {
              if (name === 'usdcVolume') return [`$${value.toLocaleString()}`, 'USDC Volume']
              if (name === 'txCount') return [value, 'Tx Count']
              return [value, name]
            }}
          />
          <Legend
            wrapperStyle={{ fontSize: 11, color: '#6b7280', paddingTop: 12 }}
            formatter={(value: string) => {
              if (value === 'usdcVolume') return 'USDC Volume'
              if (value === 'txCount') return 'Tx Count'
              return value
            }}
          />
          <Bar
            yAxisId="volume"
            dataKey="usdcVolume"
            fill="#3b82f6"
            radius={[3, 3, 0, 0]}
            maxBarSize={32}
          />
          <Line
            yAxisId="txCount"
            type="monotone"
            dataKey="txCount"
            stroke="#22c55e"
            strokeWidth={2}
            dot={{ fill: '#22c55e', r: 3, strokeWidth: 0 }}
            activeDot={{ r: 5, fill: '#22c55e' }}
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}
