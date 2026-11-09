/*
  api.js
  author: Kabera Clapton

  description: Calls to the task API with the user's Cognito ACCESS token, and the two-step upload
               (ask the API for a presigned POST, then send the file straight to S3).
               Role checks in the UI are only for convenience; the API enforces every rule.
*/
import { fetchAuthSession } from "aws-amplify/auth";
import { config } from "./config";

export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function accessToken() {
  // Amplify refreshes expired tokens here using the refresh token.
  const { tokens } = await fetchAuthSession();
  if (!tokens?.accessToken) throw new ApiError(401, "Your session has ended. Sign in again.");
  return tokens.accessToken.toString();
}

async function request(method, path, body) {
  let res;
  try {
    res = await fetch(`${config.apiUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    // fetch only throws on network failure or a CORS rejection, never on an HTTP error status.
    throw new ApiError(0, "Could not reach the server. Check your connection and try again.");
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, data.error || data.message || `Request failed (${res.status})`);
  return data;
}

function query(params) {
  const clean = Object.fromEntries(Object.entries(params).filter(([, v]) => v !== undefined && v !== ""));
  const text = new URLSearchParams(clean).toString();
  return text ? `?${text}` : "";
}

export const listTasks = (params = {}) => request("GET", `/tasks${query(params)}`);
export const getTask = (id) => request("GET", `/tasks/${id}`);
export const createTask = (task) => request("POST", "/tasks", task);
export const updateTask = (id, changes) => request("PUT", `/tasks/${id}`, changes);
export const notifyAssignee = (id) => request("POST", `/tasks/${id}/notify`);
export const listMembers = () => request("GET", "/users");
export const listAttachments = (id) => request("GET", `/tasks/${id}/attachments`);

export async function uploadAttachment(taskId, file) {
  const { upload } = await request("POST", `/tasks/${taskId}/attachments`, {
    fileName: file.name,
    contentType: file.type,
    size: file.size,
  });

  const form = new FormData();
  Object.entries(upload.fields).forEach(([key, value]) => form.append(key, value));
  form.append("file", file); // S3 requires the file to be the LAST field

  const res = await fetch(upload.url, { method: "POST", body: form });
  if (!res.ok) {
    const code = (await res.text()).match(/<Code>(.*?)<\/Code>/)?.[1];
    const message =
      code === "EntityTooLarge"
        ? "That file is larger than 10 MB."
        : `The upload was refused (${code || res.status}). Try again.`;
    throw new ApiError(res.status, message);
  }
}
