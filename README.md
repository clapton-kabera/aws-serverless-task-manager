# Field Tasks: AWS Serverless Task Management System

A task manager for a field team. An **admin** creates tasks, assigns them to **team members** and
tracks progress; team members see only their own tasks, update their status and attach photos or
documents. Everyone gets email notifications for assignments, updates and approaching deadlines.

The whole system is serverless (API Gateway, Lambda, DynamoDB, Cognito, SNS, S3, CloudFront,
EventBridge Scheduler, CloudWatch) and every resource is defined in Terraform.

**Live application:** [Frontend URL](https://d1ze303wf897xh.cloudfront.net)

---

## Features

| | Admin | Team member |
|---|---|---|
| Sign in (no public sign-up) | ✓ | ✓ |
| See tasks | All tasks | Only tasks assigned to them |
| Create and assign tasks | ✓ | |
| Edit title, instructions, deadline; reassign | ✓ | |
| Change status (Open, In progress, Done) | ✓ | Own tasks only |
| Upload and download attachments | ✓ | Own tasks only |
| Send a manual reminder | ✓ | |
| Task history (who changed what, when) | ✓ | Own tasks only |

**Notifications (email):**

- New task or reassignment: the assignee (and the previous assignee when reassigned).
- An admin changes a task's details or status: the assignee.
- A team member changes a task's status: the admins.
- Deadline within 24 hours: one reminder to the assignee.

---

## Architecture

![Architecture diagram](docs/architecture.png)
<!-- architecture diagram goes here -->

**Request path (synchronous).** The browser loads the React app from **CloudFront**, which reads a
private **S3** bucket through Origin Access Control. The user signs in against a **Cognito** user
pool and receives JWTs. Every API call carries the access token to an **API Gateway HTTP API**, whose
JWT authorizer verifies it before anything runs. Each route invokes its own **Lambda** function, which
checks the caller's role and ownership and reads or writes **DynamoDB**.

**Files.** The API never handles file bytes. A Lambda returns a short-lived **presigned POST**, and
the browser uploads straight to a private attachments **S3** bucket; downloads use presigned GETs.

**Events (asynchronous).** Every change to a task flows through the table's **DynamoDB stream** to a
notifier Lambda, which publishes to one **SNS** topic. Each person's email subscription has a filter
policy, so SNS delivers each message only to the right people. Records that keep failing go to an
**SQS dead-letter queue**. **EventBridge Scheduler** runs a reminder Lambda every hour.

**Observability.** Every Lambda writes to its own **CloudWatch Logs** group (14-day retention).

---

## Tech stack

| Layer | Choice |
|---|---|
| Infrastructure as code | Terraform (S3 remote state with native lock file) |
| API | API Gateway HTTP API (v2), Cognito JWT authorizer, CORS |
| Compute | AWS Lambda, Python 3.14, arm64, one function per route, shared code as a layer |
| Data | DynamoDB single table, on-demand, point-in-time recovery, stream |
| Auth | Amazon Cognito user pool, groups `admin` and `member` |
| Notifications | SNS (email) with filter policies, SQS dead-letter queue, EventBridge Scheduler |
| Files | S3 with presigned POST / GET |
| Front end | React (Vite), Amplify UI Authenticator, hosted on S3 + CloudFront |
| Tests | pytest + moto (mocked AWS), shell scripts against the deployed stack |

---

## Repository structure

```
.
├── backend/
│   ├── functions/          # one folder per Lambda, each with app.py
│   ├── shared/python/common/  # shared layer: auth, http, db, tasks, users, notify, attachments
│   ├── tests/              # pytest unit tests (mocked AWS)
│   └── requirements-dev.txt
├── frontend/               # React app (Vite)
├── infra/                  # Terraform: one file per concern
├── scripts/                # setup, deploy, evidence and teardown scripts
└── docs/
    ├── decisions/          # architecture decision records (ADRs)
    └── evidence/           # captured output from the deployed system
```

Adding a Lambda means adding one entry to `local.functions` in `infra/locals.tf` (route, memory,
timeout and its extra IAM permissions) and a folder under `backend/functions/`.

---

## API

Base URL: `terraform output -raw gateway_url`. Every route requires
`Authorization: Bearer <Cognito access token>`. Errors are JSON: `{"error": "..."}`.

| Method and path | Who | Purpose |
|---|---|---|
| `GET /tasks` | Admin: all. Member: own | List tasks. Query: `status`, `limit` (1–100), `nextToken` |
| `POST /tasks` | Admin | Create and assign: `title`, `description`, `deadline` (ISO-8601 with timezone), `assigneeId` |
| `GET /tasks/{taskId}` | Admin, or the assignee | One task with its history |
| `PUT /tasks/{taskId}` | Admin: any field. Member: `status` only | Update; must include the `version` last read |
| `POST /tasks/{taskId}/notify` | Admin | Email the assignee a reminder now |
| `POST /tasks/{taskId}/attachments` | Admin, or the assignee | Get a presigned POST: `fileName`, `contentType`, `size` |
| `GET /tasks/{taskId}/attachments` | Admin, or the assignee | List files with download links |
| `GET /users` | Admin | List team members (for assigning) |
| `GET /hello` | Any signed-in user | Returns the caller's ID and groups (auth check) |

Status codes used: `200`, `201`, `400` invalid input, `401` missing or invalid token, `403` role not
allowed, `404` not found or not yours, `409` the task changed since you read it.

---

## Data model

One DynamoDB table, designed around the access patterns (see
[ADR 0003](docs/decisions/0003-single-table-dynamodb.md)).

| Item | `pk` | `sk` | Main attributes |
|---|---|---|---|
| Task | `TASK#<id>` | `META` | title, description, status, assigneeId, assigneeEmail, deadline, version, createdBy, updatedBy, openDueDate, reminderSentAt |
| History event | `TASK#<id>` | `EVENT#<time>#<rand>` | action, actor, at, changes |

| Index | Keys | Serves |
|---|---|---|
| Table | `pk`, `sk` | One task and its history in a single Query |
| `by_assignee` | `assigneeId`, `deadline` | "My tasks", soonest first |
| `open_by_due_date` (sparse) | `openDueDate`, `deadline` | Reminder job: only unfinished tasks have `openDueDate` |

Users live only in Cognito (no users table). All times are stored in UTC.

---

## Prerequisites

- An AWS account and the AWS CLI v2, signed in with a non-root identity (`aws sts get-caller-identity`)
- Terraform 1.10 or later
- Python 3.11 or later (for the tests)
- Node.js 20.19+ or 22.12+ (for the front end)
- `curl` and `python3` (used by the scripts)

Region: `eu-west-1`.

---

## Setup and deployment

**1. Remote state (once per account).** Create the state bucket, then point the backend at it.

```bash
./scripts/bootstrap-backend.sh      # TODO(kabera): your script's name
# backend settings: infra/versions.tf  TODO(kabera): or backend.hcl if you use partial configuration
```

**2. Infrastructure.**

```bash
cd infra
terraform init
terraform validate
terraform plan        # review before applying
terraform apply       # first run takes several minutes (CloudFront)
cd ..
```

**3. Users.** Creates the user with a verified email, puts them in a group, and subscribes their email
to notifications. Each person must click the confirmation link AWS emails them.

```bash
./scripts/admin_setup.sh admin@example.com admin
./scripts/admin_setup.sh worker@example.com member
```

**4. Front end.** Builds with the Terraform outputs, uploads, refreshes CloudFront and prints the link.

```bash
./scripts/deploy-frontend.sh
```

For local front-end development: copy `frontend/.env.example` to `frontend/.env.local`, fill it from
`terraform output`, then `cd frontend && npm ci && npm run dev` (http://localhost:5173 is already
allowed by CORS).

---

## Usage

1. Open the live link and sign in as the admin. Choose **New task**, fill in the title, deadline and
   team member, and choose **Create and assign**. The team member receives an email.
2. Sign in as the team member. The task appears under *Due today* or *Coming up*. Choose
   **Start work**, add a photo under *Photos and documents*, then **Mark as done**. The admin is
   emailed about each status change.
3. As the admin, open the task to see its history, edit details or send a reminder.

---

## Testing

**Unit tests** (no AWS account needed; AWS is mocked with moto):

```bash
pip install -r backend/requirements-dev.txt
python3 -m pytest backend/tests -v
```

They cover role and ownership rules, input validation, optimistic locking, history, the sparse
reminder index, who is notified for each change, reminder idempotency, presigned upload policies and
file name sanitising.

**End-to-end checks** against the deployed stack. Each prints PASS or FAIL per check and writes its
output to `docs/evidence/`:

```bash
./scripts/test_auth.sh admin@example.com
./scripts/test_tasks.sh admin@example.com worker@example.com
./scripts/test_notifications.sh admin@example.com worker@example.com
./scripts/test_attachments.sh worker@example.com
```

---

## Security

- **Authentication vs authorization.** API Gateway's JWT authorizer verifies every token (signature,
  issuer, expiry, audience) before any Lambda runs. The Lambdas then check the role, and DynamoDB
  condition expressions re-check ownership and the version inside the write itself, so a race between
  read and write cannot bypass the rules. The front end hides buttons only for convenience.
- **Groups are matched exactly.** HTTP APIs pass `cognito:groups` as one string (e.g. `"[admin]"`); it
  is split and compared by exact name, so a group like `superadmin` cannot pass as `admin`.
- **No self sign-up.** Only admins create accounts. The app client has no secret (it runs in a browser)
  and enables only SRP sign-in, refresh, and admin password auth (which requires IAM credentials).
- **Least-privilege IAM.** Every Lambda has its own role with only the actions and resources it needs
  (see `infra/locals.tf`). API Gateway may invoke functions only on behalf of this API (`source_arn`).
  The scheduler role can invoke only the reminder function and is limited to this account.
- **Members cannot probe other tasks.** Another member's task returns 404, not 403.
- **Private buckets.** Both buckets block all public access, disable ACLs, encrypt objects and refuse
  non-HTTPS requests. The site bucket is readable only by this CloudFront distribution.
- **Attachments.** Presigned URLs expire after 5 minutes. S3 itself enforces the 10 MB limit and the
  signed content type. Only safe types are allowed and downloads are forced
  (`Content-Disposition: attachment`), so an uploaded file is never displayed as a web page.
- **CORS** allows only the CloudFront origin (and localhost for development).
- **Secrets.** None in the repository. Passwords are read with hidden prompts and never written to disk;
  test tokens are never saved to evidence files. Front-end configuration values are not secrets.
- **Accepted risk.** The CLI scripts pass the password as an `aws` command argument, so it is briefly
  visible in the local process list. Acceptable on a single-user machine for a lab.

---

## Cost

Everything is pay-per-use, so an idle deployment costs close to nothing: no NAT gateways, load
balancers or provisioned databases. Lambdas run outside a VPC. DynamoDB is on-demand. Log groups keep
logs for 14 days instead of forever. The only scheduled work is one reminder run per hour. An AWS
Budget alert is recommended (`TODO(kabera): note the budget you set`).

---

## Design decisions

Recorded in [`docs/decisions/`](docs/decisions/):

| ADR | Decision |
|---|---|
| [0001](docs/decisions/0001-terraform-with-sam-cli-for-local-testing.md) | Terraform for everything; SAM CLI only for local testing |
| [0002](docs/decisions/0002-http-api-instead-of-rest-api.md) | HTTP API instead of REST API |
| [0003](docs/decisions/0003-single-table-dynamodb.md) | Single-table DynamoDB; admin list uses Scan deliberately |
| [0004](docs/decisions/0004-assignment-inside-create-and-update.md) | Assignment inside create and update, not a separate endpoint |
| [0005](docs/decisions/0005-notifications-via-stream-and-filter-policies.md) | Notifications from the DynamoDB stream with SNS filter policies; no Step Functions |
| [0006](docs/decisions/0006-attachments-via-presigned-post.md) | Attachments via presigned POST straight to S3 |
| [0007](docs/decisions/0007-react-amplify-ui-on-cloudfront.md) | React + Amplify UI on private S3 behind CloudFront |

---

## Troubleshooting

| Symptom | Likely cause | What to check |
|---|---|---|
| Every API call returns 401, even with a fresh token | Issuer or audience mismatch | Decode the token; compare `iss` with the authorizer issuer (must start with `https://`) and `client_id` with the app client |
| 403 `Forbidden` for a valid user | User is in neither group | `aws cognito-idp admin-list-groups-for-user` |
| `Internal Server Error` and **no** Lambda logs | API Gateway cannot invoke the function | `aws_lambda_permission` and its `source_arn` |
| `Internal Server Error` **with** a stack trace in the logs | Code or IAM error | `aws logs tail /aws/lambda/<function> --since 10m` |
| Browser shows "Could not reach the server" | CORS | DevTools console; the page's origin must be in `local.frontend_origins` |
| No emails arrive | Subscription not confirmed, or filter mismatch | `aws sns list-subscriptions-by-topic`: `PendingConfirmation` means the link was not clicked |
| No deadline reminder | Not in the 24 h window, already reminded, or task is Done | The task's `deadline` and `reminderSentAt`; the reminder function's logs |
| `KMS.AccessDenied` when publishing | Encrypted topic | Add `kms:GenerateDataKey` and `kms:Decrypt` for the SNS key to the publishing functions |
| Messages in the dead-letter queue | Notifier kept failing | Read the message, then the notifier's logs for that time |
| Upload fails with 403 from S3 | URL expired (5 min) or a signed field changed | Request a new upload URL |
| Old version of the site after deploy | Browser or CloudFront cache | The deploy script invalidates `/index.html`; hard-refresh the browser |
| `terraform destroy` fails with `BucketNotEmpty` | Attachments bucket still has files | Use `scripts/teardown.sh`, which empties it first |
| `ConflictException` creating a route | Two resources claiming the same route key | Use `moved` blocks when renaming resources |

---

## Evidence

Captured with `tee` from the deployed system (`docs/evidence/`):

| File | Shows |
|---|---|
| `02-terraform-init.txt` | Remote backend configured |
| `03-hello-curl.txt` | First Lambda reachable through API Gateway |
| `04-auth-tests.txt` | No token 401, valid token 200, tampered token 401 |
| `05-task-api.txt` | Full task flow as admin and member, including 403 and 409 cases |
| `06-notifications.txt` | Subscriptions, stream notification, reminder sent once, manual nudge, empty DLQ |
| `07-attachments.txt` | Direct S3 upload; S3 rejecting an oversized file and a changed content type; byte-for-byte download |
| `08-frontend-deploy.txt` | Site live over HTTPS with security headers; HTTP redirected; bucket not public |
| `TODO(kabera)` screenshots | Sign-in, admin view, member view, the notification emails |

---

## Cleanup

```bash
./scripts/teardown.sh
```

It asks for confirmation, empties the attachments bucket (Terraform will not delete a bucket that
still holds files, so attachments cannot be wiped by accident), runs `terraform destroy`, and saves the
output to `docs/evidence/09-teardown.txt`.

The **Terraform state bucket is kept on purpose**: it is created outside this configuration. To remove
it as the very last step, delete every object version (versioning is on) and then the bucket, for
example in the S3 console with *Empty* followed by *Delete*.

---

## Known limitations and next steps

- **Monitoring is logs only.** Next: CloudWatch alarms on Lambda errors, API 5xx and dead-letter queue
  depth, notifying the admins.
- **Users are added with a script.** Next: an admin-only user management screen and API.
- **No malware scanning** of attachments (e.g. GuardDuty Malware Protection for S3), no attachment
  deletion, no per-task file quota.
- **Admin task list uses Scan**, fine for a small team; add a status index if the table grows large.
- **One assignee per task.** Tasks are not deleted through the API.
- **Default CloudFront domain.** A custom domain needs an ACM certificate in us-east-1 and DNS.
- **No CI pipeline.** Next: GitHub Actions running the unit tests, `terraform fmt -check` and
  `terraform validate` on every pull request.

---

Author: Kabera Clapton
