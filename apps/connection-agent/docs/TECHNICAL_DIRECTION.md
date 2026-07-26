# Technical direction: AI Connection Agent

This document records the current hackathon architecture. It supersedes the
earlier Supabase-centered direction. Events are not a separate product entity
in the first version.

Authoritative companion decisions:

- [`JAC_NATIVE_ENGINEERING.md`](JAC_NATIVE_ENGINEERING.md)
- [`JAC_BACKEND_AND_JACHAMMER.md`](JAC_BACKEND_AND_JACHAMMER.md)
- [`specs/INTERNAL_CONTRACT_V1.md`](specs/INTERNAL_CONTRACT_V1.md)
- [`../../docs/specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md`](../../../docs/specs/CONNECTION_AGENT_JACGRID_BOUNDARIES.md)

## 1. One Jac product, two agent entry paths

Connection Agent has one identity, one canonical Markdown profile per person,
one matching system, and one set of application capabilities.

```text
Jac first-party client                   external agent host
        |                                      |
        | Jac server calls                     | product MCP
        +------------------+-------------------+
                           |
             shared typed operations and walkers
                           |
                  Jac application backend
               auth / roots / persistent graph
               cards / consent / chat / WebSocket
                           |
                 EmbeddingCompute boundary
                    |                 |
              MockJacGrid         LiveJacGrid
                    |                 |
            local workload        Phong's JacGrid
                                      |
                             Luke/Santhos sandbox
```

The first-party client invokes the same handlers used by the product MCP
adapter. Authentication, browser navigation, and human realtime delivery remain
ordinary application behavior rather than agent tools.

Jac's built-in `jac mcp` is different: it gives coding agents current Jac
documentation and compiler tools. Every development/review session uses it, but
it is not Connection Agent's user-facing MCP service.

## 2. Hackathon stack

| Concern | Current choice |
|---|---|
| Authored runtime language | Jac everywhere Jac can reasonably implement it |
| First-party interface | Jac client full-stack web/PWA |
| Server/API | Jac private/public functions and walkers through `jac start` |
| Agent/matching logic | Jac nodes, edges, walkers, and `by llm()` |
| Canonical product data | Jac persistent graph |
| Identity | Jac auth; fixture actors locally; username/email or SSO for hosted demo |
| Cross-user privacy | per-user roots plus explicit grants and typed views |
| Semantic retrieval | vectors on Jac projection nodes; complete-pool comparison for hackathon |
| Distributed compute | JacGrid executes our immutable Jac embedding workload |
| Direct chat | Jac persistent message nodes plus WebSocket/fallback refresh |
| Hosting | JacHammer free sandbox after the local product is green |
| Agent interoperability | thin product MCP adapter delegating to Jac handlers |

Supabase is not part of the hackathon architecture. SQL/RLS/pgvector/Realtime
work is removed from the current backlog rather than duplicated beside Jac.

## 3. Canonical Jac graph

The readable Markdown profile remains the semantic source of truth. Durable
product relationships are Jac nodes and typed edges:

```text
(User root)
    -> (Profile)
        -> (ProfileRevision)
            -> (EmbeddingProjection)

(Suggestion)-[VIEWER]->(User root)
            -[SUBJECT_REVISION]->(ProfileRevision)
            -[PAIR]->(CanonicalPair)

(CanonicalPair) -> (PairAssessment)
                -> (PrivateDecision per viewer)
                -> (Match) -> (PrivateThread) -> (Message)
```

Rules:

- A durable node must be reachable from the correct root or explicitly granted.
- Client operations return typed view objects, never raw nodes.
- Profile revisions and shown cards are immutable.
- Derived vectors, facets, and candidate topology carry exact source revision
  and workload identities and may be regenerated.
- `jobj()` is lookup, not authorization.
- A matched thread is granted only to its two participants.
- One-sided interest never appears in another user's view or error.

Jac uses SQLite under `.jac/data/` locally and may use MongoDB/Redis when scaled.
Schema changes use Jac alias/upgrade/quarantine tools rather than ad hoc SQL
migrations.

## 4. Matching and JacGrid boundary

The application team owns the immutable `connection-embedding` Jac workload.
JacGrid distributes that package, verifies its result, and returns one complete
embedding set. It does not own profiles, retrieval, ranking, pair assessment,
cards, consent, matches, threads, or messages.

Local development uses `MockJacGrid`, which invokes the exact same workload
package locally. `LiveJacGrid` maps the provider-neutral `EmbeddingCompute`
operation to the accepted external Job API. Product code never imports
Phong's `platform/` or Luke/Santhos's `sandbox/`.

For the hackathon population, the trusted Jac server may enumerate eligible
profiles across roots, compare every current vector, and keep a bounded
candidate neighborhood. That avoids adding a separate vector database. A
future index adapter can accelerate retrieval without moving canonical product
state out of Jac.

When a person asks “show me someone”:

1. Read their approved Markdown revision and explicit current request.
2. Ensure the revision has a verified projection, using local or live JacGrid.
3. Enumerate the complete eligible Jac profile set on the trusted server.
4. Apply self, block, system-eligibility, and lifecycle exclusions.
5. Rank vectors and keep a bounded neighborhood.
6. Materialize that neighborhood as Jac topology and traverse it for reciprocal
   assessment.
7. Produce one grounded, viewer-specific immutable card.
8. Record that exact card and suggestion under the viewer's authorized state.

Partitioning embedding work across machines never partitions the matching pool.

## 5. Why Jac is more than the syntax

Jac represents actual domain relationships and lets walkers carry the current
request through them:

```text
(Person)-[:CANDIDATE_FOR {score}]->(Person)
(Person)-[:INTEREST_DECISION]->(CanonicalPair)
(CanonicalPair)->(Match)->(PrivateThread)
```

Useful walkers/operations include:

- `UpdateProfile`
- `BuildCandidateGraph`
- `FindNextPerson`
- `ExplainPerson`
- `RecordInterest`
- `CreateMatch`
- `CoordinateMatch`

Typed `by llm()` outputs include `ProfileProposal`, `PairAssessment`,
`CardContent`, and `CoordinationSuggestion`. Trusted ordinary Jac code validates
grounding, authorization, lifecycle, and writes before data becomes durable.

All authored runtime code follows
[`JAC_NATIVE_ENGINEERING.md`](JAC_NATIVE_ENGINEERING.md). Foreign-language source
requires a recorded Jac-reviewer exception and contains no product logic.

## 6. Identity and cross-user access

Jac auth gives each authenticated person an isolated root. The hackathon can use
fixture actors locally and simple Jac username/email accounts or SSO when
hosted. Phone OTP is deferred unless a thin Jac-owned integration is added after
the core demo works.

Trusted matching can use `allroots()` to examine eligible profiles. Cross-user
product access uses explicit grants:

- a card view is granted only to its viewer;
- a thread is granted only to both matched roots;
- raw profile Markdown, vectors, assessments, traces, and pending decisions are
  never granted to clients merely because a pair was assessed;
- authenticated private endpoints are the default for user data;
- public endpoints never hold per-user state.

Authorization tests use Alice, Bob, and Carol: Alice and Bob can access their
matched thread; Carol cannot resolve it into a readable or writable view.

## 7. Direct human chat

Matches, threads, and messages are persistent Jac nodes. Only the two participant
roots receive access to the thread. Human messages remain distinct from agent
utterances and invited coordination suggestions.

Use Jac WebSocket function/walker endpoints for live delivery when the hosted
target supports them. Ordered refresh is a valid demo fallback. Idempotency keys
prevent duplicate messages across reconnect/retry.

## 8. Product MCP tools

Initial capabilities:

```text
get_my_profile()
propose_profile_update(markdown_or_patch)
save_approved_profile(proposal_id)
show_next_person(current_request?)
ask_about_person(card_id, question)
respond_to_card(card_id, open_or_pass)
open_match_chat(match_id)
help_coordinate(match_id, request)
```

Build the product MCP transport in Jac or through Jac interoperability. Every
tool delegates to the same typed application operation used by the first-party
client. A foreign-language transport wrapper is allowed only through the formal
exception process and cannot contain identity, matching, consent, or write
rules.

## 9. JacHammer release strategy

The local Stage 1 product remains the time-protected stopping point. After it is
green, deploy the consolidated full-stack Jac application through JacHammer's
free sandbox because the official JacHacks SF guidance strongly encourages it
and includes a separate Best JacHammer award.

Do not assume undocumented hosted behavior. Verify URL/cold-start behavior,
persistence, two-user isolation, grants, WebSockets or refresh fallback,
outbound JacGrid calls, and server-only secrets using the checklist in
[`JAC_BACKEND_AND_JACHAMMER.md`](JAC_BACKEND_AND_JACHAMMER.md).

If JacHammer has a day-of limitation, keep the application Jac-native and run
the same full-stack build through `jac start` locally. Do not reintroduce
Supabase during the hackathon.

## 10. Explicitly later

- Phone OTP and account recovery.
- Production-scale vector indexing.
- Event accounts, attendance verification, and organizer dashboards.
- Profile photos and appearance-first presentation.
- Voice and native mobile clients.
- Group matching, calendars, booking, and venue actions.
- Connected-agent management and revocation UI.
- Feedback-driven ranking and fairness systems.
- Production multi-region operations beyond the verified Jac hosting target.

## 11. Research basis

- [Jac MCP server](https://docs.jaseci.org/reference/mcp/)
- [Jac agent skills and MCP](https://docs.jaseci.org/reference/agent-skills-and-mcp/)
- [Jac server and scale](https://docs.jaseci.org/reference/plugins/jac-scale/)
- [Jac full-stack client](https://docs.jaseci.org/reference/plugins/jac-client/)
- [JacHacks SF hacker guide](https://jachacks.org/sf-guide/)
- [JacHacks SF Devpost](https://jachacks-sf.devpost.com/)
