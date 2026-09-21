import { useEffect, useRef, useState } from 'react'
import { eur, parse } from './calc.js'

const blank = (day) => ({ id: null, type: 'in', title: '', amount: '', date: day })
const newId = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2))

export default function DayDialog({ day, entries, onSave, onDelete, onClose }) {
  const ref = useRef(null)
  const [form, setForm] = useState(blank(day))
  const list = entries.filter((e) => e.date === day)

  useEffect(() => {
    ref.current.showModal()
  }, [])

  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  function submit(e) {
    e.preventDefault()
    const amount = Math.abs(parseFloat(String(form.amount).replace(',', '.')))
    if (!amount || !form.date) return
    onSave({
      id: form.id || newId(),
      type: form.type,
      title: form.title.trim() || (form.type === 'in' ? 'Input' : 'Output'),
      amount,
      date: form.date,
    })
    setForm(blank(day))
  }

  return (
    <dialog ref={ref} className="dialog" onClose={onClose} onClick={(e) => e.target === ref.current && ref.current.close()}>
      <div className="dialog-body">
        <div className="dialog-head">
          <h2>{parse(day).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</h2>
          <button className="icon" onClick={() => ref.current.close()} aria-label="Close">
            ✕
          </button>
        </div>

        {list.length === 0 && <p className="muted">No entries on this day.</p>}
        <ul className="entries">
          {list.map((e) => (
            <li key={e.id} className={form.id === e.id ? 'editing' : ''}>
              <span className={'num ' + e.type}>
                {e.type === 'in' ? '+' : '−'}
                {eur(e.amount)}
              </span>
              <span className="title">{e.title}</span>
              <button onClick={() => setForm({ ...e, amount: String(e.amount) })}>Edit</button>
              <button className="danger" onClick={() => onDelete(e.id)}>
                Delete
              </button>
            </li>
          ))}
        </ul>

        <form onSubmit={submit} className="entry-form">
          <h3>{form.id ? 'Edit entry' : 'Add entry'}</h3>
          <div className="toggle">
            <button type="button" className={form.type === 'in' ? 'on in' : ''} onClick={() => setForm({ ...form, type: 'in' })}>
              + Input
            </button>
            <button type="button" className={form.type === 'out' ? 'on out' : ''} onClick={() => setForm({ ...form, type: 'out' })}>
              − Output
            </button>
          </div>
          <label>
            Title
            <input value={form.title} onChange={set('title')} placeholder={form.type === 'in' ? 'e.g. Salary' : 'e.g. Insurance'} />
          </label>
          <div className="row">
            <label>
              Amount (€)
              <input value={form.amount} onChange={set('amount')} inputMode="decimal" placeholder="0,00" required />
            </label>
            <label>
              Date
              <input type="date" value={form.date} onChange={set('date')} required />
            </label>
          </div>
          <div className="row end">
            {form.id && (
              <button type="button" onClick={() => setForm(blank(day))}>
                Cancel
              </button>
            )}
            <button type="submit" className="primary">
              {form.id ? 'Save' : 'Add'}
            </button>
          </div>
        </form>
      </div>
    </dialog>
  )
}
