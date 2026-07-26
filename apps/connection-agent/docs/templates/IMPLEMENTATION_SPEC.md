# Stage 1 implementation spec: <lane>

**Handoff:** `<handoff path>`

**Branch:** `<assigned branch>`

**Baseline SHA:** `<git rev-parse HEAD before work>`

**Status:** Draft | Panel reviewed | Implemented

## Outcome and demo

State the observable Stage 1 outcome and the exact demo command.

## Existing code to reuse

List the released contracts, fakes, fixtures, and walking-skeleton components
that will be extended rather than duplicated.

## Design and files

List concrete files, interfaces, state ownership, data flow, and error behavior.
Explain how this design remains compatible with the real Stage 2 adapters.

## Internal implementation tasks

Use the smallest sensible tasks. These are implementation steps inside one
Stage 1 spec, not additional product specs.

## Tests and acceptance evidence

Map every handoff acceptance criterion to a deterministic test or demo check.
Include negative and authorization behavior where applicable.

## Risks and explicit non-goals

Record likely failure modes, mitigations, and everything deliberately deferred.

## Spec review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|

All blocking findings must be resolved before implementation.

### Spec review verdict

Record each reviewer/task identifier, material reviewed, `jac --version`, Jac
guide topics used by the Jac reviewer, and a final `ready` or `blocking` verdict.

## Implementation review record

| Reviewer role | Reviewer/task | Finding | Severity | Resolution |
|---|---|---|---|---|

Record final diff review and the checks rerun after corrections.

### Implementation review verdict

Record each reviewer/task identifier, material reviewed, and final `ready` or
`blocking` verdict.
