import React, { useCallback, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const API = '/api';
const STATUSES = ['TODO', 'IN_PROGRESS', 'DONE'];
const FILTERS = ['ALL', ...STATUSES];
const OWNER = 'Aman Yadav';

const label = (value) => value.replace('_', ' ');

async function request(path, options) {
  const response = await fetch(`${API}${path}`, options);
  if (!response.ok) throw new Error(`${options?.method || 'GET'} ${path} failed (${response.status})`);
  return response.status === 204 ? null : response.json();
}

function Stat({ label: text, value, icon }) {
  return (
    <div className="stat">
      <div className="stat-icon">{icon}</div>
      <div>
        <small>{text}</small>
        <strong>{value}</strong>
        <span>Live from /api/tasks/stats</span>
      </div>
    </div>
  );
}

function Activity({ icon, text, time }) {
  return (
    <div className="activity-row">
      <span className="activity-icon">{icon}</span>
      <div>
        <b>{text}</b>
        <small>{time}</small>
      </div>
    </div>
  );
}

function TaskRow({ task, onStatusChange, onDelete, busy }) {
  return (
    <tr>
      <td>
        <div className="task-title">
          <span className={`dot ${task.status.toLowerCase()}`} />
          <div>
            <b>{task.title}</b>
            <small>{task.description}</small>
          </div>
        </div>
      </td>
      <td>{task.assignee}</td>
      <td>
        <span className={`priority ${task.priority.toLowerCase()}`}>{task.priority}</span>
      </td>
      <td>
        <select
          className={`status-select ${task.status.toLowerCase()}`}
          value={task.status}
          disabled={busy}
          aria-label={`Status of ${task.title}`}
          onChange={(event) => onStatusChange(task, event.target.value)}
        >
          {STATUSES.map((status) => (
            <option key={status} value={status}>{label(status)}</option>
          ))}
        </select>
      </td>
      <td className="row-actions">
        <button
          className="icon-btn"
          disabled={busy}
          title="Advance status"
          aria-label={`Advance ${task.title}`}
          onClick={() => onStatusChange(task, STATUSES[(STATUSES.indexOf(task.status) + 1) % STATUSES.length])}
        >
          ↻
        </button>
        <button
          className="icon-btn danger"
          disabled={busy}
          title="Delete task"
          aria-label={`Delete ${task.title}`}
          onClick={() => onDelete(task)}
        >
          ✕
        </button>
      </td>
    </tr>
  );
}

function App() {
  const [tasks, setTasks] = useState([]);
  const [stats, setStats] = useState({ total: 0, todo: 0, inProgress: 0, done: 0 });
  const [filter, setFilter] = useState('ALL');
  const [showForm, setShowForm] = useState(false);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    try {
      setError('');
      const [list, summary] = await Promise.all([request('/tasks'), request('/tasks/stats')]);
      setTasks(list);
      setStats(summary);
    } catch (problem) {
      setError(problem.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const mutate = async (work) => {
    setBusy(true);
    try {
      await work();
      await load();
    } catch (problem) {
      setError(problem.message);
    } finally {
      setBusy(false);
    }
  };

  const changeStatus = (task, status) => {
    if (status === task.status) return;
    return mutate(() => request(`/tasks/${task.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status }),
    }));
  };

  const removeTask = (task) => {
    if (!window.confirm(`Delete "${task.title}"?`)) return;
    return mutate(() => request(`/tasks/${task.id}`, { method: 'DELETE' }));
  };

  const createTask = (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const values = new FormData(form);
    return mutate(async () => {
      await request('/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: values.get('title'),
          description: values.get('description'),
          priority: values.get('priority'),
          assignee: values.get('assignee'),
          status: values.get('status'),
        }),
      });
      form.reset();
      setShowForm(false);
    });
  };

  const visible = filter === 'ALL' ? tasks : tasks.filter((task) => task.status === filter);

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark">T</span>
          <div>
            <b>TaskBoard</b>
            <small>DevOps Capstone</small>
          </div>
        </div>
        <nav>
          <a className="active">▦ <span>Dashboard</span></a>
          <a>✓ <span>My Tasks</span></a>
          <a>◫ <span>Projects</span></a>
          <a>◌ <span>Activity</span></a>
        </nav>
        <div className="side-bottom">
          <div className="upgrade">
            <strong>Ship with confidence.</strong>
            <p>Build, deploy and observe your application.</p>
          </div>
          <div className="profile">
            <div className="avatar">AY</div>
            <div>
              <b>{OWNER}</b>
              <small>Developer</small>
            </div>
            <span>⋮</span>
          </div>
        </div>
      </aside>

      <main className="main">
        <header>
          <div>
            <p className="eyebrow">WORKSPACE / OVERVIEW</p>
            <h1>Welcome back, Aman</h1>
            <p className="muted">Here is what is happening across the delivery pipeline today.</p>
          </div>
          <button className="primary" onClick={() => setShowForm(true)}>＋ New task</button>
        </header>

        {error && <div className="alert">⚠ {error}. Start PostgreSQL and the backend, then refresh.</div>}

        <section className="stats">
          <Stat label="Total tasks" value={stats.total} icon="▦" />
          <Stat label="To do" value={stats.todo} icon="○" />
          <Stat label="In progress" value={stats.inProgress} icon="◔" />
          <Stat label="Completed" value={stats.done} icon="✓" />
        </section>

        <section className="content-grid">
          <div className="panel tasks-panel">
            <div className="panel-head">
              <div>
                <h2>Tasks</h2>
                <p className="muted">Track work across the platform team.</p>
              </div>
              <div className="filters">
                {FILTERS.map((option) => (
                  <button
                    key={option}
                    className={filter === option ? 'selected' : ''}
                    onClick={() => setFilter(option)}
                  >
                    {option === 'ALL' ? 'All' : label(option)}
                  </button>
                ))}
              </div>
            </div>
            {loading ? (
              <div className="empty">Loading tasks…</div>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Task</th>
                      <th>Assignee</th>
                      <th>Priority</th>
                      <th>Status</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {visible.map((task) => (
                      <TaskRow
                        key={task.id}
                        task={task}
                        busy={busy}
                        onStatusChange={changeStatus}
                        onDelete={removeTask}
                      />
                    ))}
                  </tbody>
                </table>
                {!visible.length && <div className="empty">No tasks in this filter. Create one to get started.</div>}
              </div>
            )}
          </div>

          <aside className="panel activity">
            <div className="panel-head">
              <div>
                <h2>Delivery pipeline</h2>
                <p className="muted">How a change reaches the cluster.</p>
              </div>
            </div>
            <Activity icon="✓" text="Pytest gate runs on every push" time="stage 1" />
            <Activity icon="◫" text="Backend and frontend images built" time="stage 2" />
            <Activity icon="◌" text="Trivy scans both images" time="stage 3" />
            <Activity icon="↗" text="Helm upgrade rolls out the release" time="stage 4" />
            <div className="pipeline">
              <span>CI</span><i /><span>Build</span><i /><span>Scan</span><i /><span>Deploy</span>
            </div>
          </aside>
        </section>

        {showForm && (
          <div className="modal-backdrop" onClick={(event) => event.target === event.currentTarget && setShowForm(false)}>
            <form className="modal" onSubmit={createTask}>
              <div className="modal-head">
                <div>
                  <p className="eyebrow">CREATE TASK</p>
                  <h2>Add a new task</h2>
                </div>
                <button type="button" className="close" onClick={() => setShowForm(false)}>×</button>
              </div>
              <label>Task title
                <input name="title" required maxLength={200} placeholder="e.g. Configure production ingress" />
              </label>
              <label>Description
                <textarea name="description" placeholder="What needs to be done?" />
              </label>
              <div className="form-row">
                <label>Priority
                  <select name="priority" defaultValue="MEDIUM">
                    <option>LOW</option>
                    <option>MEDIUM</option>
                    <option>HIGH</option>
                  </select>
                </label>
                <label>Status
                  <select name="status" defaultValue="TODO">
                    {STATUSES.map((status) => (
                      <option key={status} value={status}>{label(status)}</option>
                    ))}
                  </select>
                </label>
              </div>
              <label>Assignee
                <input name="assignee" defaultValue={OWNER} />
              </label>
              <button className="primary full" disabled={busy}>{busy ? 'Saving…' : 'Create task'}</button>
            </form>
          </div>
        )}
      </main>
    </div>
  );
}

createRoot(document.getElementById('root')).render(<App />);
