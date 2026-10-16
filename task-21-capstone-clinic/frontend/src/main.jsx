import React, { useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const STATUSES = ['waiting', 'in_consultation', 'discharged']
const LABEL = { waiting: 'Waiting', in_consultation: 'In consultation', discharged: 'Discharged' }

function App() {
  const [patients, setPatients] = useState([])
  const [stats, setStats] = useState({ total: 0, by_status: {} })
  const [name, setName] = useState('')
  const [age, setAge] = useState('')
  const [phone, setPhone] = useState('')
  const [error, setError] = useState(null)

  async function load() {
    try {
      const [p, s] = await Promise.all([
        fetch('/api/patients').then((r) => r.json()),
        fetch('/api/stats').then((r) => r.json()),
      ])
      setPatients(p)
      setStats(s)
      setError(null)
    } catch (e) {
      setError('Could not reach the API')
    }
  }

  useEffect(() => { load() }, [])

  async function addPatient(e) {
    e.preventDefault()
    if (!name.trim() || !age || !phone.trim()) return
    await fetch('/api/patients', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, age: Number(age), phone }),
    })
    setName('')
    setAge('')
    setPhone('')
    load()
  }

  async function cycle(patient) {
    const next = STATUSES[(STATUSES.indexOf(patient.status) + 1) % STATUSES.length]
    await fetch(`/api/patients/${patient.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: next }),
    })
    load()
  }

  async function remove(patient) {
    await fetch(`/api/patients/${patient.id}`, { method: 'DELETE' })
    load()
  }

  return (
    <div className="wrap">
      <header>
        <h1>ClinicDesk</h1>
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

      <form onSubmit={addPatient}>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Patient name"
          maxLength={200}
        />
        <input
          value={age}
          onChange={(e) => setAge(e.target.value)}
          placeholder="Age"
          type="number"
          min="0"
          max="130"
        />
        <input
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          placeholder="Phone"
          maxLength={20}
        />
        <button type="submit">Check in</button>
      </form>

      {patients.length === 0 ? (
        <div className="empty">No patients checked in yet.</div>
      ) : (
        <ul>
          {patients.map((p) => (
            <li key={p.id} className={p.status}>
              <span className={`badge ${p.status}`}>{LABEL[p.status]}</span>
              <span className="title">{p.name} &middot; {p.age}y &middot; {p.phone}</span>
              <button className="ghost" onClick={() => cycle(p)}>Advance</button>
              <button className="ghost" onClick={() => remove(p)}>Delete</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

createRoot(document.getElementById('root')).render(<App />)
