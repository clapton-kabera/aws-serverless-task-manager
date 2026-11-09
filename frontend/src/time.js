/*
  time.js
  author: Kabera Clapton

  description: The API stores and returns every time in UTC. These helpers convert to the person's
               local time for display, and back to UTC for the API.
*/
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

export function dueLabel(deadline, status) {
  if (status === "DONE") return "Done";
  const diff = new Date(deadline) - Date.now();
  const abs = Math.abs(diff);
  const amount = abs < HOUR ? `${Math.max(1, Math.round(abs / 60000))} min`
    : abs < 2 * DAY ? `${Math.round(abs / HOUR)} h`
    : `${Math.round(abs / DAY)} days`;
  return diff < 0 ? `Overdue by ${amount}` : `Due in ${amount}`;
}

export function dueGroup(task) {
  if (task.status === "DONE") return "done";
  const deadline = new Date(task.deadline);
  if (deadline < Date.now()) return "overdue";
  const endOfToday = new Date();
  endOfToday.setHours(23, 59, 59, 999);
  return deadline <= endOfToday ? "today" : "later";
}

export function localDateTime(iso) {
  return new Date(iso).toLocaleString(undefined, {
    weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

// <input type="datetime-local"> works in local time without a timezone
export function toInputValue(iso) {
  const d = new Date(iso);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function fromInputValue(value) {
  return new Date(value).toISOString(); // local -> UTC, e.g. 2026-11-20T15:00:00.000Z
}

export function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
