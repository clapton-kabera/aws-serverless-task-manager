/*
  NewTaskForm.jsx
  author: Kabera Clapton

  description: Admin form to create a task and assign it to a team member. The deadline is entered in
               local time and sent to the API in UTC.
*/
import { useState } from "react";
import { createTask } from "../api";
import { fromInputValue, toInputValue } from "../time";

function tomorrowAtFive() {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  d.setHours(17, 0, 0, 0);
  return toInputValue(d.toISOString());
}

export default function NewTaskForm({ members, onCreated, onCancel }) {
  const [form, setForm] = useState({ title: "", description: "", deadline: tomorrowAtFive(), assigneeId: "" });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value });

  async function submit(e) {
    e.preventDefault();
    setSaving(true);
    setError("");
    try {
      const task = await createTask({ ...form, deadline: fromInputValue(form.deadline) });
      onCreated(task);
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  }

  const activeMembers = members.filter((m) => m.enabled);

  return (
    <form className="sheet" onSubmit={submit}>
      <h1 className="sheet-title">New task</h1>

      <label className="field">
        <span>Title</span>
        <input required maxLength={200} value={form.title} onChange={update("title")} placeholder="Inspect pump station 4" />
      </label>

      <label className="field">
        <span>Instructions <small>optional</small></span>
        <textarea rows={4} maxLength={2000} value={form.description} onChange={update("description")} />
      </label>

      <div className="field-row">
        <label className="field">
          <span>Deadline</span>
          <input required type="datetime-local" value={form.deadline} onChange={update("deadline")} />
        </label>

        <label className="field">
          <span>Assign to</span>
          <select required value={form.assigneeId} onChange={update("assigneeId")}>
            <option value="" disabled>Choose a team member</option>
            {activeMembers.map((m) => <option key={m.id} value={m.id}>{m.email}</option>)}
          </select>
        </label>
      </div>

      {activeMembers.length === 0 && (
        <p className="notice">No team members yet. Add one with scripts/admin_setup.sh &lt;email&gt; member.</p>
      )}
      {error && <p className="notice notice-error" role="alert">{error}</p>}

      <div className="actions">
        <button type="submit" className="button button-primary" disabled={saving}>{saving ? "Creating…" : "Create and assign"}</button>
        <button type="button" className="button button-quiet" onClick={onCancel}>Cancel</button>
      </div>
    </form>
  );
}
