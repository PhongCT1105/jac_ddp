# Stage 1.5 — Bring Your Own Profile

**Status:** Accepted after one-pass Jac, product/privacy, and data-quality review
**Owner:** Connection Agent application team
**Milestone:** A showable browser product that matches one visitor against 100 fictional people
**Runtime:** Jac-first; no authored non-Jac application runtime

## 1. User outcome

A visitor opens Connection Agent and sees one simple form:

1. Enter a name.
2. Paste or write a free-form personal profile.
3. Select **Find my connections**.
4. See an honest indeterminate loading state while the profile and complete fictional pool are embedded.
5. See three ranked fictional demo profiles, with names, excerpts, text-similarity scores, and grounded reasons to talk.

The visitor does not need an account. The application does not intentionally persist the submitted name or profile to its repository, browser storage, graph/database, logs, or fictional corpus; it keeps request data in memory only while processing and releases it when the request finishes. The form warns visitors not to submit secrets or sensitive personal information. A future live provider may receive profile text and must disclose and satisfy its own retention policy before it is enabled.

## 2. Profile corpus

The repository contains exactly 100 fictional Markdown files under:

```text
apps/connection-agent/data/demo-profiles/
```

Every file is a regular UTF-8 `.md` file and has only this required frontmatter:

```yaml
---
id: unique-stable-id
name: Fictional Name
---
```

Everything after the frontmatter is the person's free-form profile. The writing should feel independently authored: some profiles may be one paragraph, others several sections or roughly one page; voices, interests, professions, ages, locations, goals, and formatting should vary. Profiles must be clearly fictional, safe for a public demo, and useful for human connection matching. Do not add rigid skill/tag schemas.

The parser accepts an exact opening and closing `---`, exactly one `id` and one `name`, no extra or duplicate frontmatter keys, and a nonblank body. IDs match `[a-z0-9]+(?:-[a-z0-9]+)*`. Normalize CRLF to LF, trim outer whitespace from names/bodies, sort records by ID rather than filesystem order, and compute a deterministic SHA-256 corpus revision over their canonical UTF-8 representation. The running app accepts a growing development corpus of 3–100 valid profiles and always reports and ranks the complete count present. It fails clearly on duplicate IDs or names, duplicate normalized bodies, malformed files, fewer than 3 files, or more than 100 files. Exactly 100 remains the final corpus release gate.

Corpus QA requires 100 unique bodies with no placeholders: at least 20 paragraph-only profiles, 20 profiles with headings, 20 with lists, 20 bodies from 250–699 characters, 20 from 700–1,499 characters, and 10 at 1,500 characters or longer; categories may overlap. The corpus handoff records an agent review for fictional safety, visibly differentiated voice, and non-duplicative content.

## 3. Application flow

Add a server-only typed `def:pub find_profile_matches(name: str, profile_markdown: str) -> ProfileMatchResponse` for this milestone. Because it does not traverse the graph, it is a function, not a walker. `main.jac` imports it so Jac registers the endpoint. The client uses a typed `sv import`, calls it positionally with `await`, and receives a safe response envelope rather than arbitrary exceptions. The response contains:

- submitted and recombined item counts;
- terminal compute states;
- provider mode, workload version, runtime tag (primary or deterministic fallback), result identity, and corpus revision;
- exactly three ranked match cards when at least three candidates exist;
- for each card: stable fictional profile ID, name, score, short excerpt, and one or more reasons supported by the submitted profile and/or the candidate's source text.

Validation errors are safe, actionable, and do not echo the full submitted profile. Reject blank names, blank profiles, names over 100 characters, and profiles over 12,000 characters. Disable duplicate submission while work is running. A failure preserves the form so the visitor can retry.

## 4. Compute and ownership boundary

The Connection Agent owns:

- corpus parsing and validation;
- construction of embedding items;
- the matching/ranking algorithm;
- explanations and result-card shaping;
- the Jac server operation and browser experience.

The compute provider owns only distributed execution, verification, failure recovery, and returning the complete workload result. Application code introduces one small application-owned embedding-provider interface with dependency injection. Its mock implementation invokes the existing application-owned `connection-embedding` workload through `MockJacGrid`, returns complete submitted/recombined evidence and runtime identity, and supports deterministic failure tests. Ranking, endpoint, and client code must not implement embeddings. It must not import or modify JacGrid coordinator/worker internals or Luke/Santhos sandbox code.

Stage 1.5 is synchronous and mock-first: the browser shows indeterminate loading and terminal evidence, not live progress. Local development and deterministic tests use `MockJacGrid`. The interface permits a future Contract A live adapter without changing the UI contract or ranking code, but enabling that adapter is a follow-on until its retention/disclosure behavior is verified. This milestone does not claim that a local mock job ran on multiple physical computers.

All `N+1` items (the visitor plus every currently available fictional profile) belong to one logical embedding request/result. Chunking may distribute execution, but ranking occurs only after complete recombination and always considers all `N` candidates. Return observable counts proving this. At final corpus release, `N=100` and the result is 101 submitted/recombined items.

## 5. Matching and explanations

- Require exact equality between the expected and returned 101-item ID sets before ranking. Reject incomplete, duplicate, non-finite, or dimensionally invalid results.
- Rank all 100 fictional profiles using cosine similarity over verified vectors; do not rank independently inside chunks. Quantize canonical scores to 12 decimal places, sort descending by that score then ascending profile ID, and round separately for display.
- Return the deterministic top three. Exact repeatability is required for the same corpus revision, workload/runtime identity, and deterministic fallback result.
- The response exposes the runtime tag. Pinned MiniLM results may be labeled semantic similarity. Deterministic fallback is acceptable for offline/demo plumbing but the UI labels it **deterministic demo ranking**, not semantic AI or compatibility.
- The showable ranking journey selects the pinned MiniLM primary runtime when the model is available; the deterministic fallback is the explicit offline/test/degraded path.
- Scores are text-similarity presentation values, not compatibility guarantees or probabilities.
- Reasons must be conservative and traceable to source text. Do not invent biography, identity, availability, intent, or shared interests.
- Every excerpt is a deterministic, length-bounded exact substring of the normalized candidate body. A specific reason carries exact supporting candidate text and, when claiming something shared, exact supporting visitor text. Otherwise use an allowlisted neutral runtime-appropriate template. Candidate IDs and names come from the parsed corpus record. Never fabricate specificity merely to make the card sound intelligent.

## 6. Browser experience

The default browser screen for this milestone contains:

- product title and one-sentence explanation;
- visible wording that the pool contains fictional, non-contactable demo profiles;
- labeled name input;
- labeled large profile textarea with a short example prompt and character count;
- primary **Find my connections** action;
- accessible validation, loading, retry, and result states;
- three readable result cards;
- **Edit my profile** / start-over action.

The current reciprocal Alice/Bob fixture remains supported by its existing tests and code, but it does not need to remain the default screen. The form and results explicitly say these are fictional demo profiles. No real-person match, consent, contactability, compatibility, or private-chat claim is made for these ranked suggestions.

All visitor text, corpus text, excerpts, and reasons render as escaped text; raw Markdown HTML, scripts, and URLs are never executed. Labels and instructions are programmatically associated, the flow is keyboard-operable, loading and errors are announced, focus moves to the first validation error or results heading, and meaning never depends on color alone.

## 7. Acceptance criteria

1. The repository has exactly 100 valid, varied fictional Markdown profiles.
2. A new visitor can enter a name and free-form profile in the browser and receive three ranked results without editing code or seed data.
3. The result proves exact 101-item submission/recombination and 100-candidate ranking and exposes corpus/workload/runtime identity.
4. Repeating the same input against the same corpus revision and deterministic fallback result yields the same ordered results.
5. Blank/oversized input and provider failure have accessible, retryable UI states.
6. Tests demonstrate the application does not persist or log the submitted profile; the UI displays the sensitive-information warning.
7. Existing Stage 1 reciprocal/privacy tests still pass.
8. Known-vector tests prove complete-set ranking, stable ties, top-three order, and rejection of incomplete/duplicate/non-finite output, including a best candidate beyond the first chunk.
9. A small versioned golden-query smoke over the real corpus and primary MiniLM records hand-justified acceptable top-three candidates; it is a release-quality check when the primary model is installed, while fallback runs validate structure only.
10. Browser tests verify fictional/fallback framing, safe rendering, focus, announcements, retry, and three results.
11. Jac formatting, checking, unit/integration tests, web build, browser smoke, source-policy, and boundary checks pass through the repository quality gate.

## 8. Fast implementation lanes

After this spec receives one parallel review, implementation may proceed in two disjoint lanes:

- **Corpus lane:** create and validate the 100 Markdown fixtures only.
- **Application lane:** implement the Jac loader, matching operation, UI, and focused tests against a small test corpus or generated test fixtures.

The lanes integrate once. Run the complete repository gate and one final browser journey after integration; address only actual failures or release-blocking review findings.

## 9. Out of scope

- Accounts, durable visitor profiles, production authentication, or Supabase migration.
- Contacting a suggested person, reciprocal consent, or chat from this new flow.
- Changes to JacGrid coordinator/worker, payment, reputation, or sandbox behavior.
- Live distributed execution or retention guarantees; those are enabled after a Contract A adapter and disclosure are verified.
- LLM calls. Stage 1.5 matching uses the pinned embedding workload and does not consume OpenAI tokens.
