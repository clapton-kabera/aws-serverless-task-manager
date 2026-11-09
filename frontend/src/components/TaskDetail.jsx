/*
  TaskDetail.jsx
  author: Kabera Clapton

  description: One task: deadline, status actions, instructions, attachments and history. Admins can
               also edit details, reassign and send a reminder. Every update sends the version that
               was read; if someone changed the task in the meantime the API answers 409 and the
               latest version is reloaded instead of overwriting their change.
*/
import { useCallback, useEffect, useState } from "react";
import { getTask, notifyAssignee, updateTask } from "../api";
import { dueGroup, dueLabel, fromInputValue, localDateTime, toInputValue } from "../time";
import Attachments from "./Attachments";
import StatusStamp from "./StatusStamp";

const STATUS_ACTIONS = {
  OPEN: [{ to: "IN_PROGRESS", label: "Start work" }, { to: "DONE", label: "Mark as done" }],
  IN_PROGRESS: [{ to: "DONE", label: "Mark as done" }, { to: "OPEN", label: "Move back to open" }],
  DONE: [{ to: "OPEN", label: "Reopen" }],
};
const STATUS_WORDS = { OPEN: "open", IN_PROGRESS: "in progress", DONE: "done" };
const FIELD_NAMES = { title: "Title", description: "Instructions", deadline: "Deadline", status: "Status", assigneeId: "Assignee" };

export default function TaskDetail({ taskId, me, members, onChanged, onClose }) {
  const [task, setTask] = useState(null);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null); // { kind: "error" | "info", text }

  const load = useCallback(async () => {
    try {
      setTask(await getTask(taskId));
    } catch (e) {
      setMessage({ kind: "error", text: e.message });
    }
  }, [taskId]);

  useEffect(() => {
    load();
  }, [load]);

  const who = (sub) => (sub === me.sub ? "You" : members.find((m) => m.id === sub)?.email ?? (sub === task?.createdBy ? "Admin" : "Team member"));

  async function save(changes, doneText) {
    setBusy(true);
    setMessage(null);
    try {
      const updated = await updateTask(taskId, { ...changes, version: task.version });
      onChanged(updated);
      await load(); // fetch the new history entry too
      setEditing(false);
      setMessage({ kind: "info", text: doneText });
    } catch (e) {
      if (e.status === 409) {
        await load();
        setMessage({ kind: "error", text: "Someone else changed this task while you had it open. This is the latest version; check it and try again." });
      } else {
        setMessage({ kind: "error", text: e.message });
      }
    } finally {
      setBusy(false);
    }
  }

  async function remind() {
    setBusy(true);
    setMessage(null);
    try {
      const { notified } = await notifyAssignee(taskId);
      setMessage({ kind: "info", text: `Reminder emailed to ${notified}.` });
    } catch (e) {
      setMessage({ kind: "error", text: e.message });
    } finally {
      setBusy(false);
    }
  }

  if (!task) {
    return (
      <div className="sheet">
        {message ? <p className="notice notice-error" role="alert">{message.text}</p> : <p>Loading task…</p>}
      </div>
    );
  }

  return (
    <article className="sheet">
      <button type="button" className="button button-quiet back" onClick={onClose}>Back to tasks</button>

      <div className={`due-banner urgency-${dueGroup(task)}`}>
        <span className="due-banner-label">{dueLabel(task.deadline, task.status)}</span>
        <span className="due-banner-date">{localDateTime(task.deadline)}</span>
      </div>

      <header className="sheet-header">
        <h1 className="sheet-title">{task.title}</h1>
        <StatusStamp status={task.status} />
      </header>
      <p className="sheet-meta">Assigned to {task.assigneeEmail}</p>

      <div className="actions" aria-label="Change status">
        {STATUS_ACTIONS[task.status].map(({ to, label }) => (
          <button key={to} type="button" className={`button ${to === "DONE" ? "button-primary" : ""}`} disabled={busy}
            onClick={() => save({ status: to }, `Status changed to ${STATUS_WORDS[to]}.`)}>
            {label}
          </button>
        ))}
        {me.isAdmin && task.status !== "DONE" && (
          <button type="button" className="button button-quiet" disabled={busy} onClick={remind}>Send reminder</button>
        )}
        {me.isAdmin && !editing && (
          <button type="button" className="button button-quiet" onClick={() => setEditing(true)}>Edit details</button>
        )}
      </div>

      {message && (
        <p className={`notice ${message.kind === "error" ? "notice-error" : "notice-info"}`} role={message.kind === "error" ? "alert" : "status"}>
          {message.text}
        </p>
      )}

      {editing ? (
        <EditForm task={task} members={members} busy={busy} onSave={(changes) => save(changes, "Task updated.")} onCancel={() => setEditing(false)} />
      ) : (
        <section className="block">
          <h2 className="block-title">Instructions</h2>
          <p className="instructions">{task.description || "No instructions."}</p>
        </section>
      )}

      <Attachments taskId={taskId} />

      <section className="block">
        <h2 className="block-title">History</h2>
        <ol className="history">
          {[...task.history].reverse().map((event) => (
            <li key={`${event.at}-${event.action}-${JSON.stringify(event.changes)}`}>
              <span className="history-when">{localDateTime(event.at)}</span>
              <span className="history-what">
                {who(event.actor)} {event.action === "CREATED" ? "created this task" : "changed " +
                  Object.entries(event.changes).map(([field, c]) =>
                    field === "status" ? `status to ${STATUS_WORDS[c.to] ?? c.to}`
                      : field === "deadline" ? `deadline to ${localDateTime(c.to)}`
                      : (FIELD_NAMES[field] ?? field).toLowerCase()).join(", ")}
              </span>
            </li>
          ))}
        </ol>
      </section>
    </article>
  );
}

function EditForm({ task, members, busy, onSave, onCancel }) {
  const [form, setForm] = useState({
    title: task.title,
    description: task.description,
    deadline: toInputValue(task.deadline),
    assigneeId: task.assigneeId,
  });
  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value });

  function submit(e) {
    e.preventDefault();
    const changes = {};
    if (form.title !== task.title) changes.title = form.title;
    if (form.description !== task.description) changes.description = form.description;
    if (form.assigneeId !== task.assigneeId) changes.assigneeId = form.assigneeId;
    if (form.deadline !== toInputValue(task.deadline)) changes.deadline = fromInputValue(form.deadline);
    if (Object.keys(changes).length === 0) return onCancel();
    onSave(changes);
  }

  return (
    <form className="block edit-form" onSubmit={submit}>
      <label className="field">
        <span>Title</span>
        <input required maxLength={200} value={form.title} onChange={update("title")} />
      </label>
      <label className="field">
        <span>Instructions</span>
        <textarea rows={4} maxLength={2000} value={form.description} onChange={update("description")} />
      </label>
      <div className="field-row">
        <label className="field">
          <span>Deadline</span>
          <input required type="datetime-local" value={form.deadline} onChange={update("deadline")} />
        </label>
        <label className="field">
          <span>Assign to</span>
          <select value={form.assigneeId} onChange={update("assigneeId")}>
            {members.filter((m) => m.enabled || m.id === task.assigneeId).map((m) => (
              <option key={m.id} value={m.id}>{m.email}</option>
            ))}
          </select>
        </label>
      </div>
      <div className="actions">
        <button type="submit" className="button button-primary" disabled={busy}>Save changes</button>
        <button type="button" className="button button-quiet" onClick={onCancel}>Cancel</button>
      </div>
    </form>
  );
}
