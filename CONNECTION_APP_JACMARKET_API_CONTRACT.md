# Connection App ↔ JacMarket Compute Contract

**Status:** Proposed MVP interface  
**Audience:** Connection-app team, JacMarket team, and their coding agents  
**Repository:** `jac_ddp`  
**Purpose:** Define exactly what the connection app sends to JacMarket and what JacMarket must return.

---

## 1. Executive summary

The connection app will use JacMarket as an external distributed-compute service. The first supported workload is **ranking a shortlist of potential connections**.

The connection app remains responsible for the social product and its durable data in Supabase. JacMarket is responsible for distributing the ranking calculation across workers, verifying the computation, recovering from worker failure, and returning one globally ranked result.

This is an asynchronous API:

```text
Connection app submits a ranking job
        ↓
JacMarket returns a job ID
        ↓
Connection app polls job status
        ↓
JacMarket distributes and verifies the work
        ↓
Connection app retrieves one global ranking
```

For the MVP, HTTP with JSON and status polling is the required interface. A completion webhook can be added later.

---

## 2. Responsibility boundary

### Connection app and Supabase own

- User authentication and phone numbers
- Approved Markdown profiles
- Profile visibility and consent
- Blocking and eligibility rules
- Candidate retrieval and initial filtering
- Interest decisions
- Matches
- Private chat threads and messages
- Realtime product updates
- The final user-facing connection card

### JacMarket owns

- Compute-job acceptance and validation
- Splitting the candidate list into tasks
- Worker discovery and assignment
- Worker heartbeats, timeouts, and retries
- Candidate scoring
- Combining scores from all task shards
- Verification of worker results
- Global ranking across every submitted candidate
- Compute-job status and audit history
- Worker reputation and payment records

JacMarket must not become the system of record for user accounts, profiles, matches, or chats.

---

## 3. First workload

### Workload name

`connection_candidate_ranking.v1`

### Product behavior

The connection app selects an eligible shortlist, such as 30 candidates, and submits the complete shortlist in one job.

JacMarket may split the candidates across several machines for computation. This sharding must not limit the matching pool. All scores must be recombined and ranked globally.

```text
30 submitted candidates
    ├── Worker A scores 1–10
    ├── Worker B scores 11–20
    └── Worker C scores 21–30
                    ↓
          JacMarket combines all scores
                    ↓
          One ranking across all 30
```

The connection app receives results for all 30 candidates. It may show only the best candidate to the user.

### Input meaning

The ranking calculation uses:

- The subject's approved matching-profile text
- The subject's current request or intent
- Each candidate's opaque ID
- Each candidate's approved matching-profile text
- A versioned ranking algorithm

### Output meaning

JacMarket returns:

- Exactly one score for every submitted candidate
- A global rank for every submitted candidate
- The ranking algorithm version
- Verification status
- A compute execution summary

The MVP score is a number from `0.0` through `1.0`, where a higher score means a stronger potential connection under the submitted intent. The exact model, model revision, score calculation, and score tolerance must be pinned under one server-side algorithm version such as `connection-ranker-v1`.

---

## 4. Privacy and data minimization

The connection app must send only information approved for matching.

It must not send:

- Phone numbers
- Email addresses
- Authentication tokens from Supabase
- Private chat messages
- Unapproved profile drafts
- Internal Supabase rows
- Block lists
- Real names when an opaque ID is sufficient

`subject_id` and `candidate_id` must be opaque job-facing identifiers. JacMarket does not need to know the corresponding Supabase user IDs.

JacMarket must:

- Use submitted text only to execute and verify the job
- Avoid logging raw profile text
- Define an input-retention period
- Delete raw job inputs after that period
- Never expose one worker's input or output to another user
- Return candidate IDs exactly as submitted

---

## 5. API overview

The proposed MVP endpoints are:

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/v1/jobs` | Submit a compute job |
| `GET` | `/v1/jobs/{job_id}` | Read job status and progress |
| `GET` | `/v1/jobs/{job_id}/result` | Retrieve the verified result |

All requests and responses use `application/json`.

The final base URL and authentication mechanism are deployment decisions. The interface should support:

```http
Authorization: Bearer <jacmarket-api-token>
Content-Type: application/json
```

The JacMarket token is a service credential stored on the connection-app server. It must never be sent to the browser.

---

## 6. Submit a job

### Request

```http
POST /v1/jobs
Authorization: Bearer <jacmarket-api-token>
Content-Type: application/json
Idempotency-Key: match-request-018f3e8a
```

```json
{
  "api_version": "v1",
  "job_type": "connection_candidate_ranking.v1",
  "request_id": "match-request-018f3e8a",
  "input": {
    "subject": {
      "subject_id": "subject-7c19",
      "profile_text": "I work in education and care about science and technology.",
      "current_intent": "I want to meet someone working on unusual uses of AI."
    },
    "candidates": [
      {
        "candidate_id": "candidate-001",
        "profile_text": "Applied AI engineer working on agents, MCP, and RAG."
      },
      {
        "candidate_id": "candidate-002",
        "profile_text": "Product developer interested in hospitality and in-person experiences."
      }
    ]
  },
  "algorithm": {
    "algorithm_id": "connection-ranker-v1"
  },
  "execution": {
    "maximum_budget_usdc": "0.06",
    "timeout_seconds": 60,
    "verification_policy": "redundant_sample.v1"
  }
}
```

### Required validation

JacMarket must reject the request before assigning work if:

- `job_type` is unsupported
- `request_id` is missing
- The subject profile or intent is empty
- The candidate list is empty or exceeds the agreed limit
- Candidate IDs are duplicated
- A candidate ID equals the subject ID
- The algorithm version is unsupported
- The timeout or budget is invalid
- The payload exceeds the agreed size limit

### Accepted response

```http
HTTP/1.1 202 Accepted
```

```json
{
  "api_version": "v1",
  "job_id": "job-9f52c8",
  "request_id": "match-request-018f3e8a",
  "job_type": "connection_candidate_ranking.v1",
  "status": "queued",
  "submitted_at": "2026-07-26T18:30:00Z",
  "status_url": "/v1/jobs/job-9f52c8",
  "result_url": "/v1/jobs/job-9f52c8/result"
}
```

### Idempotency rule

Repeating the same request with the same `Idempotency-Key` and identical body must return the original job instead of creating a second paid job.

Reusing an idempotency key with a different body must return `409 Conflict`.

---

## 7. Read job status

### Request

```http
GET /v1/jobs/job-9f52c8
Authorization: Bearer <jacmarket-api-token>
```

### Response

```json
{
  "api_version": "v1",
  "job_id": "job-9f52c8",
  "request_id": "match-request-018f3e8a",
  "status": "running",
  "progress": {
    "candidate_count": 30,
    "tasks_total": 3,
    "tasks_succeeded": 1,
    "tasks_running": 1,
    "tasks_retrying": 1,
    "tasks_failed": 0
  },
  "submitted_at": "2026-07-26T18:30:00Z",
  "started_at": "2026-07-26T18:30:02Z",
  "completed_at": null
}
```

### Job statuses

| Status | Meaning |
|---|---|
| `queued` | Accepted but not assigned |
| `assigning` | Workers are being selected |
| `running` | At least one task is executing |
| `verifying` | Results are being checked |
| `succeeded` | A complete verified result is available |
| `failed` | No valid complete result can be produced |
| `cancelled` | The job was cancelled before completion |

Only `succeeded`, `failed`, and `cancelled` are terminal statuses.

---

## 8. Retrieve the result

### Successful result

```http
GET /v1/jobs/job-9f52c8/result
Authorization: Bearer <jacmarket-api-token>
```

```json
{
  "api_version": "v1",
  "job_id": "job-9f52c8",
  "request_id": "match-request-018f3e8a",
  "status": "succeeded",
  "job_type": "connection_candidate_ranking.v1",
  "algorithm": {
    "algorithm_id": "connection-ranker-v1"
  },
  "ranking": [
    {
      "rank": 1,
      "candidate_id": "candidate-001",
      "score": 0.91
    },
    {
      "rank": 2,
      "candidate_id": "candidate-002",
      "score": 0.64
    }
  ],
  "verification": {
    "status": "passed",
    "policy": "redundant_sample.v1",
    "verified_task_count": 1,
    "rejected_attempt_count": 1
  },
  "execution_summary": {
    "candidate_count": 2,
    "task_count": 1,
    "worker_attempt_count": 2,
    "reassigned_task_count": 1,
    "completed_at": "2026-07-26T18:30:21Z"
  },
  "receipt": {
    "result_hash": "sha256:example",
    "payment_status": "settled",
    "total_paid_usdc": "0.02"
  }
}
```

### Result invariants

For a successful job, JacMarket must guarantee:

1. Every submitted candidate appears exactly once.
2. No unsubmitted candidate appears.
3. Ranks are unique and consecutive, beginning with `1`.
4. Scores are finite numbers from `0.0` through `1.0`.
5. Results are sorted by ascending rank.
6. The ranking is global across all task shards.
7. The algorithm ID is the version actually executed.
8. Verification passed before the result became available.
9. A failed worker attempt does not create a duplicate candidate result.
10. Payment is never released for a rejected attempt.

If JacMarket cannot return a complete verified ranking, the whole job must be marked `failed`. It must not silently return a partial candidate list.

### Result not ready

If the job is not terminal:

```http
HTTP/1.1 409 Conflict
```

```json
{
  "error": {
    "code": "RESULT_NOT_READY",
    "message": "The job is still running.",
    "retryable": true
  }
}
```

### Failed job result

```json
{
  "api_version": "v1",
  "job_id": "job-9f52c8",
  "request_id": "match-request-018f3e8a",
  "status": "failed",
  "error": {
    "code": "VERIFICATION_FAILED",
    "message": "A complete verified ranking could not be produced.",
    "retryable": true
  }
}
```

---

## 9. Error contract

All API errors must use this shape:

```json
{
  "error": {
    "code": "MACHINE_READABLE_CODE",
    "message": "Human-readable explanation.",
    "retryable": false,
    "details": {}
  }
}
```

Recommended HTTP status codes:

| HTTP status | Use |
|---|---|
| `400` | Invalid JSON or malformed request |
| `401` | Missing or invalid service authentication |
| `402` | Payment authorization required or rejected |
| `409` | Idempotency conflict or result not ready |
| `422` | Valid JSON with unsupported job parameters |
| `429` | Submission rate limit exceeded |
| `500` | Unexpected internal error |
| `503` | No compute capacity is currently available |

The connection app may automatically retry only when `retryable` is `true`. Retrying job submission must reuse the same idempotency key.

---

## 10. Verification requirement

The MVP must use computation that can be verified consistently across the worker Macs.

The ranking algorithm must pin:

- Embedding or scoring model name
- Exact model revision or artifact hash
- Input normalization
- Numeric precision
- Score calculation
- Tie-breaking behavior
- Allowed numeric tolerance

A recommended first policy is:

1. Workers score disjoint candidate shards.
2. JacMarket selects a deterministic sample from every shard.
3. A separate worker recomputes the sample.
4. Scores must match within the configured tolerance.
5. A mismatching shard is rejected and reassigned.
6. JacMarket merges only verified shards.

For the hackathon, JacMarket may instead redundantly compute every shard if the workload is small enough.

A hash alone proves that bytes did not change. It does not prove that the ranking calculation was correct.

---

## 11. Connection-app sequence

The connection app should implement this sequence:

```text
1. User asks to see a potential connection.
2. Supabase applies consent, block, eligibility, and availability filters.
3. The app selects up to the agreed maximum number of candidates.
4. The app creates opaque job-facing IDs.
5. The server submits one JacMarket ranking job.
6. The server stores request_id and job_id.
7. The server polls until the job reaches a terminal status.
8. On success, the server validates the result invariants.
9. The app maps the top candidate's opaque ID back to its Supabase record.
10. The app creates the viewer-specific connection card.
11. The app stores that the candidate was shown.
12. On failure, the app shows a retryable product state or uses an agreed fallback.
```

The browser must not call JacMarket directly. All calls go through the connection-app server.

---

## 12. MVP acceptance tests

Phong's platform and the connection app are compatible when all of these tests pass:

1. Submit two candidates and receive two globally ranked results.
2. Submit 30 candidates, distribute them across three workers, and receive all 30 in one ranking.
3. Disconnect a worker; its task is reassigned without duplicating results or payment.
4. Return an intentionally incorrect shard; verification rejects it and another worker recomputes it.
5. Repeat a submission with the same idempotency key; only one job and payment are created.
6. Submit duplicate candidate IDs; the request is rejected.
7. Request the result before completion; receive `RESULT_NOT_READY`.
8. Exhaust all retries; receive a terminal failed job rather than a partial ranking.
9. Confirm that raw profile text does not appear in normal platform logs.
10. Confirm that the result contains no phone number, Supabase token, private message, or worker secret.

---

## 13. Decisions the team must finalize

The contract intentionally leaves these deployment values open:

- JacMarket base URL
- Service authentication method and token issuance
- Exact ranking model and immutable revision
- Maximum candidates per job
- Maximum profile-text length
- Default timeout and retry limit
- Score precision and verification tolerance
- Verification sample size
- Price per job or task
- Testnet, stablecoin, and payment-authorization format
- Raw-input retention period
- Poll interval and rate limits
- Whether to add a completion webhook after polling works

Once agreed, these values should be recorded in a versioned configuration section without changing the `v1` payload semantics.

---

## 14. Out of scope for this contract

- Supabase schema design
- Phone authentication
- Private human chat
- User-facing card generation
- Dynamic worker bidding rules
- General arbitrary-code execution
- Full on-chain dispute resolution
- Multi-region deployment
- A public third-party API

This contract establishes one narrow, testable integration: the connection app submits a candidate-ranking job, and JacMarket returns a complete, verified, global ranking.
