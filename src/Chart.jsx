import { useEffect, useMemo, useRef, useState } from 'react'
import { eur, eurShort, parse } from './calc.js'

const W = 28 // px per day
const TOP = 12
const PH = 220 // plot height
const H = TOP + PH + 54 // extra space at the bottom keeps month labels clear of the scrollbar
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function niceStep(span) {
  const raw = span / 4
  const mag = Math.pow(10, Math.floor(Math.log10(raw)))
  const f = raw / mag
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * mag
}

export default function Chart({ points, today, entries, onPick }) {
  const scrollRef = useRef(null)
  const [hover, setHover] = useState(null)
  const [view, setView] = useState({ left: 0, width: 10000 })
  const onScroll = () => {
    const el = scrollRef.current
    setView({ left: el.scrollLeft, width: el.clientWidth })
  }
  // Month label sits in the middle of the month's currently visible days.
  const monthX = (m) => {
    const a = Math.max(m.first * W, view.left)
    const b = Math.min((m.last + 1) * W, view.left + view.width)
    return b > a ? (a + b) / 2 : ((m.first + m.last + 1) / 2) * W
  }

  const { lo, hi, ticks } = useMemo(() => {
    const vals = points.map((p) => p.balance)
    let lo = Math.min(0, ...vals)
    let hi = Math.max(0, ...vals)
    if (hi === lo) hi = lo + 1000
    const step = niceStep(hi - lo)
    lo = Math.floor(lo / step) * step
    hi = Math.ceil(hi / step) * step
    const ticks = []
    for (let v = lo; v <= hi + step / 2; v += step) ticks.push(v)
    return { lo, hi, ticks }
  }, [points])

  const y = (v) => TOP + PH - ((v - lo) / (hi - lo)) * PH
  const width = points.length * W
  const todayIdx = points.findIndex((p) => p.day === today)

  // Step path per section (past = on/before today, future = after).
  const paths = useMemo(() => {
    let past = ''
    let future = ''
    points.forEach((p, i) => {
      const x0 = i * W
      const yy = y(p.balance)
      const isPast = p.day <= today
      const prev = points[i - 1]
      if (isPast) past += `${past ? 'L' : 'M'}${x0},${yy}H${x0 + W}`
      else if (!future) future = `M${x0},${prev ? y(prev.balance) : yy}V${yy}H${x0 + W}`
      else future += `L${x0},${yy}H${x0 + W}`
    })
    return { past, future }
  }, [points, today, lo, hi])

  const months = useMemo(() => {
    const groups = []
    points.forEach((p, i) => {
      const key = p.day.slice(0, 7)
      const g = groups[groups.length - 1]
      if (g && g.key === key) g.last = i
      else groups.push({ key, first: i, last: i })
    })
    const multiYear = points.length && points[0].day.slice(0, 4) !== points[points.length - 1].day.slice(0, 4)
    return groups.map((g) => {
      const d = parse(g.key + '-01')
      return { ...g, label: MONTHS[d.getMonth()] + (multiYear ? ' ' + d.getFullYear() : '') }
    })
  }, [points])

  useEffect(() => {
    const el = scrollRef.current
    if (!el) return
    const idx = todayIdx >= 0 ? todayIdx : points.length && today > points[points.length - 1].day ? points.length - 1 : 0
    el.scrollLeft = idx * W - el.clientWidth / 2
    onScroll()
  }, [points.length, points[0]?.day, todayIdx])

  const hp = hover != null ? points[hover] : null
  const hoverEntries = hp ? entries.filter((e) => e.date === hp.day) : []

  return (
    <div className="chart">
      <svg className="yaxis" width="64" height={H}>
        {ticks.map((t) => (
          <text key={t} x="58" y={y(t) + 4} textAnchor="end">
            {eurShort(t)}
          </text>
        ))}
      </svg>
      <div className="scroll" ref={scrollRef} onScroll={onScroll}>
        <svg width={width} height={H} onMouseLeave={() => setHover(null)}>
          {lo < 0 && <rect x="0" y={y(0)} width={width} height={TOP + PH - y(0)} className="neg" />}
          {ticks.map((t) => (
            <line key={t} x1="0" x2={width} y1={y(t)} y2={y(t)} className={t === 0 ? 'zero' : 'grid'} />
          ))}
          {months.map((m) =>
            m.first > 0 ? <line key={m.key} x1={m.first * W} x2={m.first * W} y1={TOP} y2={H} className="msep" /> : null
          )}
          {todayIdx >= 0 && <rect x={todayIdx * W} y={TOP} width={W} height={PH} className="todaycol" />}
          {hover != null && <rect x={hover * W} y={TOP} width={W} height={PH} className="hovercol" />}
          <path d={paths.past} className="line past" />
          <path d={paths.future} className="line future" />
          {todayIdx >= 0 && (
            <line x1={todayIdx * W + W / 2} x2={todayIdx * W + W / 2} y1={TOP} y2={TOP + PH} className="todayline" />
          )}
          {points.map((p, i) =>
            p.count ? (
              <circle
                key={p.day}
                cx={i * W + W / 2}
                cy={y(p.balance)}
                r="5"
                className={(p.net >= 0 ? 'dot in' : 'dot out') + (p.day > today ? ' fut' : '')}
              />
            ) : null
          )}
          {points.map((p, i) => (
            <text
              key={p.day}
              x={i * W + W / 2}
              y={TOP + PH + 16}
              textAnchor="middle"
              className={'dnum' + (i === todayIdx ? ' today' : '')}
            >
              {Number(p.day.slice(8))}
            </text>
          ))}
          {months.map((m) => (
            <text key={m.key} x={monthX(m)} y={TOP + PH + 36} textAnchor="middle" className="mname">
              {m.label}
            </text>
          ))}
          {points.map((p, i) => (
            <rect
              key={p.day}
              x={i * W}
              y="0"
              width={W}
              height={H}
              className="hit"
              onClick={() => onPick(p.day)}
              onPointerEnter={(e) => e.pointerType === 'mouse' && setHover(i)}
            />
          ))}
        </svg>
        {hp && (
          <div className="tip" style={{ left: Math.min(hover * W + W + 6, width - 190), top: 8 }}>
            <div className="tip-date">{parse(hp.day).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' })}</div>
            <div className="num">{eur(hp.balance)}</div>
            {hoverEntries.map((e) => (
              <div key={e.id} className={e.type}>
                {e.type === 'in' ? '+' : '−'}
                {eur(e.amount)} {e.title}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
