# 0006: Attachments uploaded directly to S3 with presigned POST

**Status:** Accepted

**Context.** Field staff attach photos and documents to tasks. API Gateway (~10 MB) and Lambda (6 MB
synchronous payload) limits make sending files through the API fragile and expensive.

**Decision.**
- The API returns a **presigned POST** (valid 5 minutes); the browser uploads straight to a private S3
  bucket. POST, not PUT, because its signed policy lets **S3 itself** enforce the 10 MB limit and the
  exact content type.
- Only a short list of file types is allowed (images, PDF, text, Word, Excel); HTML/SVG/JS are refused,
  and downloads use `Content-Disposition: attachment`, so an uploaded file can never run as a web page.
- Keys are `tasks/<taskId>/<attachmentId>/<safe name>`. S3 is the single source of truth: listing reads
  the prefix, so there is no metadata in DynamoDB to keep in sync.
- Only an admin or the task's assignee can request upload or download URLs.

**Consequences.** No file bytes touch Lambda, so cost and limits do not depend on file size. A presigned
URL acts with the Lambda role's permissions and stops working when those temporary credentials expire.
Not implemented (production next steps): malware scanning (e.g. GuardDuty Malware Protection for S3),
deleting attachments, per-task quotas.
