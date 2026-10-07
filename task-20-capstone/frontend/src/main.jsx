import React, { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const STATUSES = ['todo', 'in_progress', 'done']
const LABEL = { todo: 'To do', in_progress: 'In progress', done: 'Done' }

function App() {
  const [tasks, setTasks] = useState([])
  const [stats, setStats] = useState({ total: 0, by_status: {} })
  const [title, setTitle] = useState('')
  const [status, setStatus] = useState('todo')
  const [error, setError] = useState(null)

  async function load() {
    try {
      const [t, s] = await Promise.all([
        fetch('/api/tasks').then((r) => r.json()),
        fetch('/api/stats').then((r) => r.json()),
      ])
      setTasks(t)
      setStats(s)
      setError(null)
    } catch (e) {
      setError('Could not reach the API')
    }
  }

  useEffect(() => { load() }, [])

  async function addTask(e) {
    e.preventDefault()
    if (!title.trim()) return
    await fetch('/api/tasks', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, status }),
    })
    setTitle('')
    load()
  }

  async function cycle(task) {
    const next = STATUSES[(STATUSES.indexOf(task.status) + 1) % STATUSES.length]
    await fetch(`/api/tasks/${task.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: next }),
    })
    load()
  }

  async function remove(task) {
    await fetch(`/api/tasks/${task.id}`, { method: 'DELETE' })
    load()
  }

  return (
    <div className="wrap">
      <header>
        <h1>TaskBoard</h1>
        <p>DevOps capstone &middot; React + FastAPI + PostgreSQL on Kubernetes</p>
      </header>

      {error && <div className="error">{error}</div>}

      <div className="stats">
        <div className="stat"><div className="n">{stats.total}</div><div className="l">Total</div></div>
        {STATUSES.map((s) => (
          <div className="stat" key={s}>
            <div className="n">{stats.by_status?.[s] ?? 0}</div>
            <div className="l">{LABEL[s]}</div>
          </div>
        ))}
      </div>

      <form onSubmit={addTask}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="What needs doing?"
          maxLength={200}
        />
        <select value={status} onChange={(e) => setStatus(e.target.value)}>
          {STATUSES.map((s) => <option key={s} value={s}>{LABEL[s]}</option>)}
        </select>
        <button type="submit">Add</button>
      </form>

      {tasks.length === 0 ? (
        <div className="empty">Nothing here yet.</div>
      ) : (
        <ul>
          {tasks.map((t) => (
            <li key={t.id} className={t.status}>
              <span className={`badge ${t.status}`}>{LABEL[t.status]}</span>
              <span className="title">{t.title}</span>
              <button className="ghost" onClick={() => cycle(t)}>Advance</button>
              <button className="ghost" onClick={() => remove(t)}>Delete</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

createRoot(document.getElementById('root')).render(<App />)
