/*
  App.jsx
  author: Kabera Clapton

  description: The signed-in app. Admins see every task, can create and assign tasks and manage them;
               members see their own tasks and update status and attachments. The role comes from the
               ID token's cognito:groups claim and only decides what the UI shows; the API enforces it.
*/
import { fetchAuthSession } from "aws-amplify/auth";
import { useCallback, useEffect, useState } from "react";
import { listMembers, listTasks } from "./api";
import NewTaskForm from "./components/NewTaskForm";
import TaskDetail from "./components/TaskDetail";
import TaskList from "./components/TaskList";

const STATUS_FILTERS = [
  { value: "", label: "All tasks" },
  { value: "OPEN", label: "Open" },
  { value: "IN_PROGRESS", label: "In progress" },
  { value: "DONE", label: "Done" },
];

export default function App({ signOut }) {
  const [me, setMe] = useState(null);
  const [tasks, setTasks] = useState([]);
  const [nextToken, setNextToken] = useState(null);
  const [statusFilter, setStatusFilter] = useState("");
  const [selectedId, setSelectedId] = useState(null);
  const [creating, setCreating] = useState(false);
  const [members, setMembers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    fetchAuthSession().then(({ tokens }) => {
      const claims = tokens?.idToken?.payload ?? {};
      const groups = claims["cognito:groups"] ?? [];
      setMe({ email: claims.email, sub: claims.sub, isAdmin: groups.includes("admin") });
    });
  }, []);

  const load = useCallback(async (token) => {
    setLoading(true);
    setError("");
    try {
      const data = await listTasks({ status: statusFilter, nextToken: token });
      setTasks((previous) => (token ? [...previous, ...data.items] : data.items));
      setNextToken(data.nextToken);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [statusFilter]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (me?.isAdmin) listMembers().then((data) => setMembers(data.items)).catch((e) => setError(e.message));
  }, [me]);

  function replaceTask(updated) {
    setTasks((previous) => previous.map((t) => (t.taskId === updated.taskId ? { ...t, ...updated } : t)));
  }

  function addTask(task) {
    setTasks((previous) => [task, ...previous]);
    setCreating(false);
    setSelectedId(task.taskId);
  }

  function select(taskId) {
    setCreating(false);
    setSelectedId(taskId);
  }

  if (!me) return <p className="page-message">Loading your account…</p>;

  const showingPanel = creating || selectedId;

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <img src="/favicon.svg" alt="" width="28" height="28" />
          <span>Field Tasks</span>
        </div>
        <div className="account">
          <span className="account-email">{me.email}</span>
          <span className={`role role-${me.isAdmin ? "admin" : "member"}`}>{me.isAdmin ? "Admin" : "Team member"}</span>
          <button type="button" className="button button-quiet" onClick={signOut}>Sign out</button>
        </div>
      </header>

      <main className={`layout ${showingPanel ? "layout-panel-open" : ""}`}>
        <section className="list-column" aria-label="Tasks">
          <div className="toolbar">
            <label className="filter">
              <span className="visually-hidden">Show</span>
              <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
                {STATUS_FILTERS.map((f) => <option key={f.value} value={f.value}>{f.label}</option>)}
              </select>
            </label>
            {me.isAdmin && (
              <button type="button" className="button button-primary" onClick={() => { setSelectedId(null); setCreating(true); }}>
                New task
              </button>
            )}
          </div>

          {error && <p className="notice notice-error" role="alert">{error}</p>}

          <TaskList tasks={tasks} isAdmin={me.isAdmin} selectedId={selectedId} onSelect={select} loading={loading} />

          {nextToken && (
            <button type="button" className="button button-quiet load-more" disabled={loading} onClick={() => load(nextToken)}>
              Load more tasks
            </button>
          )}
        </section>

        <section className="panel-column" aria-label="Task details">
          {creating && <NewTaskForm members={members} onCreated={addTask} onCancel={() => setCreating(false)} />}
          {!creating && selectedId && (
            <TaskDetail
              key={selectedId}
              taskId={selectedId}
              me={me}
              members={members}
              onChanged={replaceTask}
              onClose={() => setSelectedId(null)}
            />
          )}
          {!showingPanel && (
            <div className="panel-empty">
              <p>{me.isAdmin ? "Pick a task to review it, or create a new one." : "Pick a task to update its status or add photos and documents."}</p>
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
