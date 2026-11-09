/*
  StatusStamp.jsx
  author: Kabera Clapton

  description: The task's status, shown like a stamp on a job card.
*/
const LABELS = { OPEN: "Open", IN_PROGRESS: "In progress", DONE: "Done" };

export default function StatusStamp({ status }) {
  return <span className={`stamp stamp-${status.toLowerCase()}`}>{LABELS[status] ?? status}</span>;
}
