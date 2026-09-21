import { useEffect, useMemo, useRef, useState } from 'react'
import Chart from './Chart.jsx'
import DayDialog from './DayDialog.jsx'
import EntryList from './EntryList.jsx'
import { dayRange, eur, monthlyPayment, series, signed, todayIso, totalUntil } from './calc.js'

// Keeps the typed text (so "0" or "0." stay visible) and reports it as a number; empty = 0.
function NumField({ value, onChange, ...props }) {
  const [text, setText] = useState(String(value ?? ''))
  useEffect(() => {
    if ((text === '' ? 0 : Number(text)) !== value) setText(String(value ?? ''))
  }, [value])
  return (
    <input
      type="number"
      min="0"
      {...props}
      value={text}
      onChange={(e) => {
        setText(e.target.value)
        const n = Number(e.target.value)
        if (!Number.isNaN(n)) onChange(n)
      }}
    />
  )
}

const ListIcon = () => (
  <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
    <rect x="1" y="2.5" width="2" height="2" />
    <rect x="5" y="3" width="10" height="1" />
    <rect x="1" y="7" width="2" height="2" />
    <rect x="5" y="7.5" width="10" height="1" />
    <rect x="1" y="11.5" width="2" height="2" />
    <rect x="5" y="12" width="10" height="1" />
  </svg>
)

const GraphIcon = () => (
  <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.3" aria-hidden="true">
    <path d="M1.5 1.5v13h13" />
    <path d="M3.5 11H6V7.5h3V9h2.5V4H14" />
  </svg>
)

export default function App() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [picked, setPicked] = useState(null)
  const [today, setToday] = useState(todayIso())
  const [view, setView] = useState(() => {
    try {
      return localStorage.getItem('view') || 'graph'
    } catch {
      return 'graph'
    }
  })

  function toggleView() {
    const next = view === 'graph' ? 'list' : 'graph'
    setView(next)
    try {
      localStorage.setItem('view', next)
    } catch {}
  }

  const version = useRef(null) // data.json version this page last saw
  const pending = useRef(0) // own saves still in flight

  async function load() {
    try {
      const r = await fetch('/api/data')
      const d = await r.json()
      if (pending.current) return // a local save started meanwhile; don't overwrite it
      version.current = Number(r.headers.get('X-Version'))
      setData(d)
      setError('')
    } catch {
      setError('Could not load data')
    }
    setToday(todayIso())
  }

  useEffect(() => {
    load()
    const onVis = () => document.visibilityState === 'visible' && load()
    document.addEventListener('visibilitychange', onVis)
    // Poll for changes made on another device.
    const timer = setInterval(async () => {
      if (document.visibilityState !== 'visible' || pending.current) return
      try {
        const { version: v } = await fetch('/api/version').then((r) => r.json())
        if (v !== version.current && !pending.current) load()
      } catch {}
    }, 3000)
    return () => {
      document.removeEventListener('visibilitychange', onVis)
      clearInterval(timer)
    }
  }, [])

  function update(patch) {
    const next = { ...data, ...patch }
    setData(next)
    pending.current++
    fetch('/api/data', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(next) })
      .then(async (r) => {
        setError(r.ok ? '' : 'Save failed')
        if (r.ok) version.current = Math.max(version.current || 0, (await r.json()).version)
      })
      .catch(() => setError('Save failed'))
      .finally(() => pending.current--)
  }

  const points = useMemo(() => {
    if (!data || !data.startDate || !data.endDate || data.endDate < data.startDate) return []
    return series(dayRange(data.startDate, data.endDate), data.entries)
  }, [data])

  if (!data) return <main className="app">{error || 'Loading…'}</main>

  const num = (k) => (v) => update({ [k]: v })
  const have = totalUntil(today, data.entries)
  const goal = data.goal || 0
  // Net of the entries still to come (after today, up to the end date) — not including what we already have.
  const upcoming = data.entries.reduce(
    (s, e) => (e.date > today && e.date <= data.endDate ? s + signed(e) : s),
    0
  )
  const expected = have + upcoming
  const pct = (v) => (goal > 0 ? Math.min(100, Math.max(0, (v / goal) * 100)) : v > 0 ? 100 : 0)
  const greenPct = pct(have)
  const grayPct = Math.max(0, pct(expected) - greenPct)
  const remaining = Math.max(0, goal - expected)
  const monthly = monthlyPayment(data.loanAmount, data.apr, data.loanYears)
  const interest = monthly * data.loanYears * 12 - data.loanAmount

  return (
    <main className="app">
      <header>
        <h1>Savings</h1>
        {error && <span className="err">{error}</span>}
      </header>

      <section className="panel">
        <div className="row wrap">
          <label>
            Start
            <input type="date" value={data.startDate} onChange={(e) => e.target.value && update({ startDate: e.target.value })} />
          </label>
          <label>
            End
            <input type="date" value={data.endDate} onChange={(e) => e.target.value && update({ endDate: e.target.value })} />
          </label>
          <div className="stat">
            <span className="muted">Today</span>
            <span className={'num big ' + (have < 0 ? 'out' : 'in')}>{eur(have)}</span>
          </div>
          <button
            className="icon view-toggle"
            onClick={toggleView}
            aria-label={view === 'graph' ? 'Show list' : 'Show graph'}
            title={view === 'graph' ? 'Show list' : 'Show graph'}
          >
            {view === 'graph' ? <ListIcon /> : <GraphIcon />}
          </button>
        </div>
        {view === 'list' ? (
          <EntryList
            entries={data.entries}
            today={today}
            onPick={setPicked}
            onAdd={() => setPicked(today)}
            onDelete={(id) => update({ entries: data.entries.filter((e) => e.id !== id) })}
          />
        ) : points.length ? (
          <Chart points={points} today={today} entries={data.entries} onPick={setPicked} />
        ) : (
          <p className="muted">Set an end date after the start date.</p>
        )}
      </section>

      <section className="panel">
        <div className="row wrap between">
          <h2>Goal</h2>
          <label className="inline">
            Target €
            <NumField step="100" value={data.goal} onChange={num('goal')} />
          </label>
        </div>
        <div className="bar">
          <div className="bar-green" style={{ width: greenPct + '%' }} />
          <div className="bar-gray" style={{ width: grayPct + '%' }} />
          <div className="bar-red" style={{ width: 100 - greenPct - grayPct + '%' }} />
        </div>
        <div className="row wrap between">
          <span className="num in">Have {eur(have)}</span>
          <span className="num expected">
            Expected {upcoming >= 0 ? '+' : '−'}
            {eur(Math.abs(upcoming))} → {eur(expected)}
          </span>
          <span className="num out">Remaining {eur(remaining)}</span>
        </div>
      </section>

      <section className="panel">
        <h2>Loan</h2>
        <div className="row wrap">
          <label>
            Max loan €
            <NumField step="100" value={data.loanAmount} onChange={num('loanAmount')} />
          </label>
          <label>
            APR %
            <NumField step="0.1" value={data.apr} onChange={num('apr')} />
          </label>
          <label>
            Years
            <NumField
              className="years"
              min="1"
              step="1"
              value={data.loanYears}
              onChange={(v) => v >= 1 && update({ loanYears: Math.floor(v) })}
            />
          </label>
        </div>
        <div className="row wrap">
          <div className="stat">
            <span className="muted">Monthly payment</span>
            <span className="num big">{eur(monthly)}</span>
          </div>
          <div className="stat">
            <span className="muted">Total interest</span>
            <span className="num">{eur(interest > 0 ? interest : 0)}</span>
          </div>
        </div>
      </section>

      {picked && (
        <DayDialog
          key={picked}
          day={picked}
          entries={data.entries}
          onClose={() => setPicked(null)}
          onDelete={(id) => update({ entries: data.entries.filter((e) => e.id !== id) })}
          onSave={(entry) => {
            const exists = data.entries.some((e) => e.id === entry.id)
            update({ entries: exists ? data.entries.map((e) => (e.id === entry.id ? entry : e)) : [...data.entries, entry] })
          }}
        />
      )}
    </main>
  )
}
