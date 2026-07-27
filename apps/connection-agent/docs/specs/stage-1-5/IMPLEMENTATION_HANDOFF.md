# Stage 1.5 implementation handoff

**Status:** Implemented and integrated
**Feature:** Bring Your Own Profile
**Specification:** `BRING_YOUR_OWN_PROFILE.md`

## Delivered experience

The default Jac browser app now lets a visitor:

1. enter a name or nickname;
2. write or paste a free-form personal profile;
3. compare it with the complete fictional corpus currently present;
4. receive three ranked fictional profile cards;
5. inspect submitted, recombined, and ranked counts plus workload/runtime evidence;
6. edit and rerun the same profile or clear it and start over.

The UI identifies the corpus as fictional and non-contactable, distinguishes
pinned-model semantic similarity from deterministic fallback ranking, warns
against sensitive input, and makes no compatibility, consent, or real-person
match claim.

## Implementation

- `src/stage15/corpus.jac` strictly parses, canonicalizes, sorts, and hashes a
  growing 3–100 profile Markdown corpus. `expected_count=100` provides the
  strict final-release gate.
- `src/stage15/provider.jac` supplies the application-owned injectable compute
  boundary and invokes the released `connection-embedding` workload through
  `MockJacGrid`.
- `src/stage15/profile_match.jac` exposes the typed public
  `find_profile_matches` server function, validates the complete `N+1` result,
  ranks all N profiles only after recombination, and returns three deterministic
  cards with exact source excerpts and conservative reasons.
- `web/main.jac` supplies the accessible form, loading, error, result, edit,
  and clear states. The earlier Stage 1 reciprocal fixture remains intact and
  covered by its existing tests.
- The default local start script prefers the pinned MiniLM runtime when it is
  installed. The browser smoke uses the explicitly labeled deterministic
  fallback for speed and reproducibility.

No platform coordinator/worker, Luke/Santhos sandbox, payment, reputation, or
legacy live API code was changed.

## Corpus QA snapshot

The integrated corpus contains 100 UTF-8 Markdown files:

- 100 unique IDs;
- 100 unique names;
- 100 unique normalized bodies;
- 48 paragraph-only profiles;
- 20 profiles with headings;
- 32 profiles with lists;
- 30 bodies at 250–699 characters;
- 49 bodies at 700–1,499 characters;
- 21 bodies at 1,500 characters or longer;
- no frontmatter, ID/filename, blank-content, or placeholder violations found.

## Verification

The Stage 1.5 implementation adds ten server/matching tests covering dynamic
and final corpus sizes, parser failures, known-vector complete-pool ranking,
stable ties, deterministic output, input nondisclosure, safe provider failure,
malformed result rejection, actual runtime provenance, and forced failure.

The browser smoke covers validation/focus, free-form submission, full-corpus
completion, three fictional results, honest fallback framing, edit/rerun,
clear/start-over, and mobile/desktop layouts.

Run the complete gate from the repository root:

```bash
./apps/connection-agent/scripts/check.sh --stage-1-integrated
```

Run the app:

```bash
./apps/connection-agent/web/start.sh
```

The served URL is printed by Jac. No OpenAI key or OpenAI tokens are used by
this milestone.
