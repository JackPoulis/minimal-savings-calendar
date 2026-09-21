export function parse(s) {
  const [y, m, d] = s.split('-').map(Number)
  return new Date(y, m - 1, d)
}

export function iso(d) {
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

export const todayIso = () => iso(new Date())

export function dayRange(start, end) {
  const days = []
  const d = parse(start)
  const last = parse(end)
  while (d <= last && days.length < 3700) {
    days.push(iso(d))
    d.setDate(d.getDate() + 1)
  }
  return days
}

export const signed = (e) => (e.type === 'in' ? e.amount : -e.amount)

// Balance at the end of each day: all entries dated on or before that day.
export function series(days, entries) {
  const sorted = [...entries].sort((a, b) => a.date.localeCompare(b.date))
  let i = 0
  let bal = 0
  return days.map((day) => {
    let net = 0
    let count = 0
    while (i < sorted.length && sorted[i].date <= day) {
      if (sorted[i].date === day) {
        net += signed(sorted[i])
        count++
      }
      bal += signed(sorted[i])
      i++
    }
    return { day, balance: bal, net, count }
  })
}

export function totalUntil(day, entries) {
  return entries.reduce((s, e) => (e.date <= day ? s + signed(e) : s), 0)
}

export function monthlyPayment(principal, apr, years) {
  const n = years * 12
  if (!principal || !n) return 0
  const r = apr / 12 / 100
  if (!r) return principal / n
  return (principal * r) / (1 - Math.pow(1 + r, -n))
}

const fmt = new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR' })
export const eur = (v) => fmt.format(v)

const fmtShort = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 })
export const eurShort = (v) => fmtShort.format(v) + ' €'
