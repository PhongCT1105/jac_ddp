# Technical direction: AI connection agent

This document records technical decisions for the hackathon build. Events are not a separate type of object in the first version.

## 1. One product, two agent entry paths

Connection Agent has one account, one Markdown profile per person, one matching system, and one set of agent capabilities.

```text
Connection Agent web chat                    ChatGPT / Claude / Codex / another host
      |                                          |
Connection Agent agent harness                         external agent
      | in-process tools              | remote MCP
      +---------------+---------------+
                      |
        shared capability contract and handlers
                      |
               Jac matching service
                 |              |
       Supabase auth, data,      +-- JacGrid compute adapter
       vectors, decisions, chat          |
                                  distributed workers safely run
                                  our immutable embedding workload
```

The person using Connection Agent's own web chat never sees tool or MCP setup. The harness is already connected to the shared capabilities. A person using an external agent authorizes that agent to use the same Connection Agent account and capability definitions through remote MCP.

### Recommendation: share the capability contract and handlers

Use the same tool definitions, typed contract, application handlers, and Jac walkers in both paths. For the hackathon, the first-party harness may invoke them in-process so remote MCP hosting and authorization cannot block the core demo. The public MCP server is a thin transport over those exact handlers, not another implementation of the product.

The ordinary web application does not need to send everything through MCP. Phone authentication, loading persistent messages, and realtime human chat can use Supabase directly. MCP is the agent capability boundary, not a replacement for every application API.

There is also a naming trap: Jac's built-in `jac mcp` command exposes the Jac compiler and documentation to coding assistants. It is useful while developing Connection Agent, but it is not Connection Agent's product MCP server. Connection Agent needs its own custom MCP server with tools such as `update_profile` and `show_next_person`.

## 2. Proposed hackathon stack

```text
First-party interface       Jac client/PWA: minimal chat shell and ASCII cards
Agent and matching logic    Jac nodes, edges, walkers, and byLLM
Canonical data              Supabase Postgres
Phone identity              Supabase Auth with SMS OTP
Semantic retrieval          embeddings in Supabase pgvector
Distributed computation     JacGrid executes our versioned embedding workload
Human direct chat           Supabase tables + RLS + Realtime
Agent interoperability      custom remote MCP server
Notifications               SMS for OTP and high-value match/message alerts
```

Using Jac's client compiler for the small first-party interface is recommended because it demonstrates Jac across client, server, graph, and AI without requiring a large conventional React application. If client integration becomes the critical hackathon blocker, the UI can remain a very thin web client while the distinctive product logic stays in Jac.

## 3. Canonical Markdown profile and derived search data

Each user has one Markdown profile as the human-readable source of truth.

```text
profiles
  user_id             Supabase Auth user UUID
  full_name           required real name
  markdown            canonical profile document
  updated_at

profile_search
  user_id
  embedding           vector derived from current Markdown
  facets              optional free-form JSON/text generated from Markdown
  index_version
```

The profile may contain social links and plain-language sharing instructions. No photo is needed in the first version.

Everything in the Markdown is readable by the matching AI and eligible for relevant card selection. V1 does not implement field-level secrecy or progressive disclosure. Connection Agent still presents only a relevant subset rather than exposing the entire document automatically.

Embeddings and facets are disposable projections. Whenever the Markdown meaningfully changes, regenerate them. They exist only to find a plausible short list; the LLM reads the original Markdown before deciding what card to show.

Embedding generation crosses a replaceable compute boundary. The connection-app team owns `connection-embedding`, including its immutable model artifact, normalization, schemas, fixtures, and verification tolerance. A server-side JacGrid adapter submits approved profile text, polls the job, validates the complete result, and stores the vector in Supabase. Phong's platform schedules and verifies executions; the Luke/Santhos sandbox invokes the package safely. Neither infrastructure workstream owns our embedding algorithm.

Local development uses `MockJacGrid`, which invokes the exact same workload package locally and emits fixture task-progress states. There is no separate mock embedding implementation.

Time-bounded facts remain ordinary Markdown in V1 and should be written with explicit natural dates or durations. The current chat message can also constrain the card request without first creating a separate database object. A future derived `current_context` projection may make expiration and asynchronous matching easier, but the hackathon does not need it.

For the tiny hackathon population, the system could compare every profile. Implementing the retrieval projection early is still recommended because Supabase already supports `pgvector`, and it prevents the first implementation from depending on an all-pairs LLM call.

## 4. Why Jac makes sense here

Calling an LLM through `by llm()` is convenient but is not, by itself, enough reason to choose Jac. Connection Agent becomes Jac-shaped when matching is represented as a topology and the matching operation becomes a walker.

### 4.1 The graph has real domain meaning

Conceptually, the current request travels with the walker rather than becoming a separate persistent `Intent` object:

```text
(Person) --CANDIDATE_FOR {semantic_score, constraints_ok}--> (Person)
    |
    +--INTERESTED_IN----------------------------------------> (Person)
    +--MATCHED_WITH-----------------------------------------> (Person)

(Match) --> (PrivateThread)
```

The exact persistence split may evolve, but these are genuine relationships rather than tables being forced into a graph for presentation. Jac edges can carry the facts that explain why a relationship exists, while walkers carry the current user's request through the candidate topology.

### 4.2 Walkers model the work

Recommended walkers or equivalent application operations:

- `UpdateProfile`: save approved Markdown and refresh its derived search projection.
- `BuildCandidateGraph`: retrieve top candidates, apply mutual hard constraints, and connect eligible candidate nodes.
- `FindNextPerson`: walk the candidate graph and use LLM-guided traversal or typed pair assessment to select a strong unseen candidate.
- `ExplainPerson`: revisit the selected pair and answer a question using the candidate's Markdown, selecting only facts relevant to the viewer's question.
- `RecordInterest`: record “I’d be open” or pass.
- `CreateMatch`: detect reciprocal interest and create the private thread.
- `CoordinateMatch`: help two matched people find the next logistical step when explicitly invited.

Jac's LLM-guided traversal can select a limited number of successor nodes while considering node and edge semantics. That is unusually close to Connection Agent's actual operation: deterministic retrieval creates the neighborhood; the model reasons over that neighborhood; the walker reports the chosen card.

### 4.3 Typed AI boundaries

Use `by llm()` for outputs whose shapes the rest of the application must trust, for example:

```text
ProfileProposal
PairAssessment
CardContent
CoordinationSuggestion
```

The model can return structured objects with reasons, uncertainty, relevant facts, and a recommendation. Ordinary code then enforces constraints and performs writes. Card ASCII is generated only after the content has been selected, keeping content reasoning separate from presentation.

### 4.4 Jac serving and full-stack support

Public or private walkers can become HTTP endpoints through `jac start`, and Jac's client layer can call walkers without manually maintaining a second route/schema definition. This is useful for the first-party chat. Jac can also import Python and npm packages, so Supabase and an MCP SDK do not require abandoning the language.

### 4.5 What not to force into Jac's graph

Do not duplicate Supabase's reliable phone auth, realtime message transport, or vector index merely to claim that everything is graph-native. For the hackathon:

- Supabase remains canonical for identity, Markdown profiles, match decisions, threads, messages, and embeddings.
- JacGrid is execution infrastructure, not a source of profile, suggestion, decision, match, or message truth.
- Jac materializes the candidate topology used for reasoning and controls the matching workflow.
- If Jac's persistent graph proves valuable in practice, more relationship state can move there later without changing the product experience.

This is a deliberate compromise: it uses Jac's distinctive traversal and AI abstractions while avoiding two competing sources of truth.

## 5. Scalable matching path

When a user asks “show me someone”:

1. Read the user's Markdown profile and the current conversational request, if any.
2. Ensure the current approved profile revision has a ready embedding. If missing, submit our versioned workload through the JacGrid compute abstraction and validate the result.
3. Apply mutual hard constraints that can be evaluated deterministically.
4. Query the Supabase embedding index for a short list, perhaps 20–50 candidates.
5. Materialize those candidates and retrieval signals as a Jac candidate graph.
6. Have our Jac walker assess and rank only that graph, using original Markdown as the semantic source.
7. Produce one tailored `CardContent` object for the current viewer.
8. Render it as compact mobile-safe ASCII inside the chat.
9. Remember that the card was shown so “show me someone else” advances rather than repeats.

Embeddings answer “who might be worth examining?” The Jac/LLM layer answers “is there a believable reason these two people might want to meet, and how should that be explained to this viewer?” Neither step claims mutual interest.

For a tiny pool, step 4 can temporarily return everyone. The rest of the pipeline remains the same.

## 6. Chat-native cards

Cards are messages, not a separate swipe interface.

```text
user: show me someone
agent: [dynamic ASCII card for Maya]
user: tell me more about why you chose her
agent: [ordinary conversational answer]
user: I’d be open
agent: noted — I’ll tell you if it becomes a match
user: show me someone else
agent: [next dynamic ASCII card]
```

The card renderer receives selected content and a mobile-safe presentation instruction. Initially, prefer short lines and horizontal separators; avoid vertical borders that can wrap badly in host chat windows. Viewport-specific rendering can wait because external chat hosts constrain layout anyway.

When both people independently say they would be open, the state becomes a match and Connection Agent creates a private human-to-human web thread. The card remains above the thread as context.

## 7. Phone-only identity across clients

The account is identified internally by the Supabase Auth UUID and accessed through a verified phone number. Email is not required.

### First-party web

1. Enter phone number.
2. Receive SMS OTP.
3. Verify and receive a Supabase session.
4. Open the same canonical profile, cards, matches, and chats on every first-party device.

### External agent

1. The external host connects to Connection Agent's product MCP server.
2. Connection Agent opens its authorization page.
3. The person verifies the same phone number or reuses an existing Connection Agent session.
4. Connection Agent issues a scoped token bound to the same Supabase user UUID.

There is no recovery process for a lost or changed phone number in the hackathon version. Supporting several agent grants and a revocation screen is a later operational feature; the data model should not artificially prohibit multiple clients.

## 8. Product MCP tools

Initial conceptual tools:

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

`current_request` is call context, not a separately persisted intent record. If a person wants a time-bounded request to remain available for later or asynchronous matching, the agent proposes adding a dated statement to the same Markdown profile.

Tool descriptions should include Connection Agent's conversational guidance: brief and non-invasive, no questionnaire, interpretations are editable, and profile additions are shown before first save. The MCP server enforces identity, access, mutual constraints, and write rules; it does not rely on every host model following prose perfectly.

Implementation recommendation: build a small product-specific `mcp_server.jac` using Jac's Python interoperability with an MCP SDK, and have every tool delegate to the same Jac application handlers/walkers. If an SDK compatibility issue makes a thin Python transport wrapper faster, keep that wrapper free of product logic. Do not modify or confuse this with the built-in `jac mcp` compiler-assistance server.

The first-party Jac harness loads the same tool definitions into its `by llm()` agent and may call their handlers in-process. External MCP hosts use the remote endpoint. Transport-level contract tests verify that in-process and MCP calls have the same inputs, outputs, authorization semantics, and product behavior.

## 9. Private human chat

Matches and messages live in Supabase so its RLS and Realtime features can protect and deliver them.

```text
matches
  id
  user_a
  user_b
  created_at

threads
  id
  match_id

messages
  id
  thread_id
  sender_id
  body
  created_at
```

Only the two matched users can read or write their thread. The agent does not impersonate either person. It can be explicitly called to help coordinate. SMS can notify someone of a match or new message and deep-link to the thread; a browser without a valid session verifies the phone number before private content is shown.

## 10. Recommendations on earlier assistant proposals

| Proposal | Recommendation |
|---|---|
| Ask exactly one question at a time | Keep as a soft conversational preference, not a rule. |
| Elaborate no-match workflow | Keep only an honest short response; defer broadening machinery. |
| Approve every profile rewrite | Confirm new meaning before first save; do not repeatedly confirm cosmetic rewrites. |
| Exact/Adjacent/Serendipitous setting | Remove from V1. Let the AI infer and clarify breadth conversationally. |
| React as a separate frontend | Prefer Jac client for the small interface; use a thin fallback only if necessary. |
| Only one external-agent connection per person | Do not impose this product restriction. Avoid building connection management for the hackathon. |
| Post-meeting feedback loop | Defer. The first proof is whether people actually match and chat. |
| Formal event verification or event objects | Defer. The hackathon distributes the ordinary app link. |
| Full safety/organizer operations system | Defer. Preserve basic ability to leave a chat; do not build event administration. |

## 11. Explicitly later

- Event accounts, event participant pools, and organizer dashboards. Shared event attendance can remain an ordinary time-bounded profile signal unless a future use case genuinely requires more.
- Profile photos or appearance-first presentation.
- Account recovery for lost phone numbers.
- Voice as a first-class client.
- Group matching.
- Calendar integrations and automatic booking.
- Connected-agent management and revocation UI.
- Feedback-driven ranking and popularity/fairness systems.
- Native mobile applications beyond a web/PWA experience.

## 12. Research basis

- [Jac core concepts: persistent topology, walkers, and codespaces](https://docs.jaseci.org/quick-guide/what-makes-jac-different/)
- [Jac Object-Spatial Programming reference](https://docs.jaseci.org/reference/language/osp/)
- [byLLM typed outputs, agents, MCP clients, and LLM-guided traversal](https://docs.jaseci.org/reference/plugins/byllm/)
- [Jac server and deployment capabilities](https://docs.jaseci.org/reference/plugins/jac-scale/)
- [Jac full-stack backend integration](https://docs.jaseci.org/tutorials/fullstack/backend/)
- [Supabase semantic retrieval with pgvector](https://supabase.com/docs/guides/ai/semantic-search)
- [Supabase phone OTP login](https://supabase.com/docs/guides/auth/phone-login)
- [Supabase Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast)
