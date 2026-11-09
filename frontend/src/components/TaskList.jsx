/*
  TaskList.jsx
  author: Kabera Clapton

  description: Tasks grouped by urgency (overdue, due today, coming up, done), soonest deadline first.
*/
import { dueGroup, dueLabel } from "../time";
import StatusStamp from "./StatusStamp";

const GROUPS = [
  { key: "overdue", title: "Overdue" },
  { key: "today", title: "Due today" },
  { key: "later", title: "Coming up" },
  { key: "done", title: "Done" },
];

export default function TaskList({ tasks, isAdmin, selectedId, onSelect, loading }) {
  if (!loading && tasks.length === 0) {
    return (
      <p className="list-empty">
        {isAdmin ? "No tasks yet. Create one and assign it to a team member." : "Nothing assigned to you right now."}
      </p>
    );
  }

  const sorted = [...tasks].sort((a, b) => a.deadline.localeCompare(b.deadline));

  return (
    <div className="task-groups" aria-busy={loading}>
      {GROUPS.map(({ key, title }) => {
        const items = sorted.filter((t) => dueGroup(t) === key);
        if (items.length === 0) return null;
        return (
          <div key={key} className="task-group">
            <h2 className="group-title">{title} <span className="group-count">{items.length}</span></h2>
            <ul className="task-rows">
              {items.map((task) => (
                <li key={task.taskId}>
                  <button
                    type="button"
                    className={`task-row urgency-${key} ${task.taskId === selectedId ? "is-selected" : ""}`}
                    aria-current={task.taskId === selectedId ? "true" : undefined}
                    onClick={() => onSelect(task.taskId)}
                  >
                    <span className="task-row-due">{dueLabel(task.deadline, task.status)}</span>
                    <span className="task-row-title">{task.title}</span>
                    <span className="task-row-meta">
                      <StatusStamp status={task.status} />
                      {isAdmin && <span className="task-row-assignee">{task.assigneeEmail}</span>}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </div>
  );
}
