# Decision: Jac backend and JacHammer hosting

**Status:** Accepted hackathon direction; hosted capabilities must be verified
with a small deployment before relying on them

## 1. Decision

Connection Agent uses Jac's own full-stack server and persistent graph for the
application backend. JacGrid remains the separate distributed-compute provider
that runs the application-owned embedding workload.

```text
Jac client
    -> Jac server functions/walkers
    -> Jac authentication and per-user roots
    -> Jac persistent graph: profiles, suggestions, decisions, matches,
       threads, messages, projections
    -> Jac WebSocket/function endpoints for live product behavior
    -> EmbeddingCompute boundary
         -> MockJacGrid / local workload
         -> LiveJacGrid / Phong's distributed platform
```

Supabase is not the canonical hackathon backend and is not required by the
current plan. It remains only a possible future external adapter if a later
product requirement cannot be met cleanly by Jac.

## 2. Why this is technically credible

The installed Jac runtime provides:

- HTTP endpoints from public/private functions and walkers through `jac start`;
- built-in user registration/login, JWT sessions, roles, and SSO configuration;
- one isolated persistent `root` per authenticated user;
- cross-user access through explicit grants such as `allow_root`;
- `allroots()` for trusted server-side matching across eligible profiles;
- persistent graph data with SQLite locally and MongoDB for scaled deployments;
- schema aliases, upgrades, quarantine, and recovery tooling;
- WebSocket walkers/functions for realtime interactions;
- deployment and scaling through the built-in `scale` subsystem.

This lets Jac own the product state instead of using Jac only as a matching
layer over another backend.

## 3. Product-state mapping

The durable model should be expressed as Jac nodes and typed edges, with view
objects returned to clients rather than raw nodes:

```text
(User root) -> (Profile) -> (ProfileRevision) -> (EmbeddingProjection)
                    |
                    +-> (Suggestion)-[ABOUT]->(ProfileRevision)

(CanonicalPair) -> (PrivateDecision per viewer)
                -> (PairAssessment)
                -> (Match) -> (PrivateThread) -> (Message)
```

- Profiles and private decisions begin under their owner's root.
- Recipient-specific cards expose only their immutable view objects.
- A matched thread is granted only to its two participant roots.
- Matching may enumerate eligible roots on the trusted server, but client
  endpoints never expose another person's raw profile, vector, assessment, or
  one-sided decision.
- `jobj()` resolves identity but does not authorize; every read/write still
  checks grants and product rules.
- For the hackathon-sized population, vectors may live on projection nodes and
  retrieval may compare the complete eligible pool. A future vector-index
  adapter can optimize retrieval without moving canonical product state.

## 4. Authentication choice

Jac's built-in authentication natively supports username/email credentials and
configured SSO. The hosted hackathon demo may use fixture actors or simple Jac
accounts. Phone OTP is not allowed to delay the working product and is deferred
unless a thin Jac-owned integration can be added safely after the demo is green.

Authenticated endpoints are private by default and run against the caller's
root. User data must never be moved to a public endpoint merely to bypass an
authentication error.

## 5. JacHammer conference deployment

JacHammer is the preferred conference host for the integrated application. The
official JacHacks SF guide:

- highly encourages hosting the project on `jachammer.ai` so judges can access
  it easily;
- says its sandbox can host the application for free;
- includes a separate Best JacHammer award;
- rewards deep use of Jac/Jaseci rather than a superficial wrapper.

References:

- [JacHacks SF hacker guide](https://jachacks.org/sf-guide/)
- [JacHacks SF Devpost rules and judging](https://jachacks-sf.devpost.com/)
- [Jac server/scale reference](https://docs.jaseci.org/reference/plugins/jac-scale/)
- [Jac agent skills and MCP](https://docs.jaseci.org/reference/agent-skills-and-mcp/)

## 6. Verification before we depend on hosted behavior

The public event guide confirms free sandbox hosting, but it does not fully
specify every runtime guarantee we need. Before the final demo, deploy the
smallest integrated build and verify with evidence:

1. full-stack Jac client and server start from the repository;
2. the hosted URL survives refresh and a cold start;
3. server-side state persists for the required demo duration;
4. two separate sessions remain isolated;
5. private endpoints and thread grants reject a third user;
6. WebSocket or fallback message refresh works;
7. outbound server requests can reach the configured JacGrid endpoint;
8. secrets remain server-only;
9. reset/test controls cannot affect non-demo data.

If a hosted feature is unavailable, keep the product in Jac and use the
smallest compatible Jac fallback. Do not reintroduce Supabase during the
hackathon merely because a JacHammer deployment detail needs adjustment.

## 7. Stage relationship

- **Stage 1 local product:** remains the time-protected stopping point and works
  without external credentials.
- **Conference release gate:** run the consolidated full-stack Jac application
  on JacHammer and prove the checks above.
- **Live distributed enhancement:** switch `MockJacGrid` to `LiveJacGrid`
  without changing the Jac product backend.

The local product is never made incomplete to chase hosting. Once it is green,
JacHammer is the first deployment target because it improves judge access and
demonstrates the intended Jac stack.
