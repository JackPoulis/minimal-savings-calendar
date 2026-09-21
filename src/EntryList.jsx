import { eur, parse } from './calc.js'

// Drawn as SVG so the symbols sit exactly in the middle of the round buttons (text glyphs don't).
const PlusIcon = () => (
  <svg width="18" height="18" viewBox="0 0 16 16" aria-hidden="true">
    <path d="M8 2v12M2 8h12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
  </svg>
)

const MinusIcon = () => (
  <svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true">
    <path d="M2 8h12" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
  </svg>
)

export default function EntryList({ entries, today, onPick, onDelete, onAdd }) {
  const sorted = [...entries].sort((a, b) => a.date.localeCompare(b.date))

  return (
    <div className="list-view">
      {sorted.length === 0 && <p className="muted">No entries yet.</p>}
      <ul className="entry-list">
        {sorted.map((e) => (
          <li key={e.id} className={e.date <= today ? 'past' : ''}>
            <button className="entry-main" onClick={() => onPick(e.date)} title="Edit this day">
              <span className="date num">
                {parse(e.date).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}
              </span>
              <span className="title">{e.title}</span>
              <span className={'num ' + e.type}>
                {e.type === 'in' ? '+' : '−'}
                {eur(e.amount)}
              </span>
            </button>
            <button
              className="icon round remove"
              aria-label={'Remove ' + e.title}
              onClick={() => window.confirm(`Remove "${e.title}"?`) && onDelete(e.id)}
            >
              <MinusIcon />
            </button>
          </li>
        ))}
      </ul>
      <button className="fab" aria-label="Add entry" onClick={onAdd}>
        <PlusIcon />
      </button>
    </div>
  )
}
