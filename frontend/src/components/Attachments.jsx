/*
  Attachments.jsx
  author: Kabera Clapton

  description: A task's files. Uploads go straight from the browser to S3 with a presigned POST;
               download links expire after 5 minutes, so the list is refreshed when a link is used late.
*/
import { useCallback, useEffect, useRef, useState } from "react";
import { listAttachments, uploadAttachment } from "../api";
import { formatBytes, localDateTime } from "../time";

const ACCEPT = ".jpg,.jpeg,.png,.pdf,.txt,.docx,.xlsx";

export default function Attachments({ taskId }) {
  const [items, setItems] = useState([]);
  const [loadedAt, setLoadedAt] = useState(0);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");
  const input = useRef(null);

  const load = useCallback(async () => {
    try {
      const data = await listAttachments(taskId);
      setItems(data.items);
      setLoadedAt(Date.now());
    } catch (e) {
      setError(e.message);
    }
  }, [taskId]);

  useEffect(() => {
    load();
  }, [load]);

  async function upload(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setError("");
    try {
      await uploadAttachment(taskId, file);
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setUploading(false);
      input.current.value = "";
    }
  }

  async function open(event, item) {
    // Links are signed for 5 minutes; if this list is older, fetch fresh links first.
    if (Date.now() - loadedAt > 4 * 60 * 1000) {
      event.preventDefault();
      const data = await listAttachments(taskId);
      setItems(data.items);
      setLoadedAt(Date.now());
      const fresh = data.items.find((i) => i.attachmentId === item.attachmentId);
      if (fresh) window.location.assign(fresh.downloadUrl);
    }
  }

  return (
    <section className="block">
      <h2 className="block-title">Photos and documents</h2>
      {items.length === 0 ? (
        <p className="muted">No files yet.</p>
      ) : (
        <ul className="files">
          {items.map((item) => (
            <li key={item.attachmentId}>
              <a href={item.downloadUrl} onClick={(e) => open(e, item)}>{item.fileName}</a>
              <span className="muted">{formatBytes(item.size)}, {localDateTime(item.uploadedAt)}</span>
            </li>
          ))}
        </ul>
      )}
      <label className={`button upload ${uploading ? "is-busy" : ""}`}>
        {uploading ? "Uploading…" : "Add a file"}
        <input ref={input} type="file" accept={ACCEPT} onChange={upload} disabled={uploading} className="visually-hidden" />
      </label>
      <p className="muted small">Photos, PDF, text, Word or Excel, up to 10 MB.</p>
      {error && <p className="notice notice-error" role="alert">{error}</p>}
    </section>
  );
}
