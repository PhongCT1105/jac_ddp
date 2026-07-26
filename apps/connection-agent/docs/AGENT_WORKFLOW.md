# Connection Agent implementation workflow

**Status:** Mandatory for every Stage 1 implementation session

This workflow makes each handoff executable with a short prompt while keeping
parallel sessions inside their assigned boundaries. The handoff document defines
the outcome; this document defines how the session reaches it.

## 1. Authority and stopping point

An implementation session is authorized to complete its assigned Stage 1
handoff end to end inside the handoff's writable paths. It may create tests,
lane-local documentation, and focused implementation files needed for that
outcome. It must not edit another lane, Phong's `platform/`, or Luke/Santhos's
`sandbox/`.

The session stops after it has reviewed, implemented, tested, committed, and
pushed its assigned branch. It never merges to `main`, force-pushes, rebases,
deploys, changes a shared contract outside its authority, or begins a Stage 2
item unless the orchestration session explicitly asks.

## 2. Verify the workspace before work

Before drafting or editing anything:

1. Confirm `pwd` exactly matches the handoff's worktree.
2. Confirm `git branch --show-current` exactly matches its assigned branch.
3. Confirm `git status --short` is clean. Preserve and report unexpected work;
   do not overwrite it.
4. Record `git rev-parse HEAD` as `BASELINE_SHA` in the implementation spec and
   confirm the Stage 1 documents are present at that baseline.
5. Read the complete handoff and every document in its **Required reading**
   section.

Do not create, rename, or switch branches. Do not merge or rebase from `main`
during the assignment unless the orchestration session instructs it.

## 3. One Stage 1 spec per session

Each handoff is one coherent Stage 1 outcome, not a request to complete the
lane's entire long-term objective packet. Before implementation, copy
[`templates/IMPLEMENTATION_SPEC.md`](templates/IMPLEMENTATION_SPEC.md) to the
exact lane-owned spec path named by the handoff and fill it in.

The implementation spec translates the accepted outcome into concrete files,
interfaces, tests, internal tasks, risks, and a demo. It may contain several
small implementation tasks and commits, but it must not expand the product
scope. Existing C/D/I/U/E objective briefs are the Stage 2/3 backlog.

## 4. Spec review panel

Before code, use parallel read-only reviewer agents when the Codex session
supports subagents. The panel must cover three independent roles:

1. **Current-Jac expert — mandatory.** Verify the design against the installed
   Jac version and current local/official Jac guidance. Check Jac syntax,
   compiler/client behavior, package interoperability, testing, and whether a
   simpler Jac-native design exists. Do not rely on remembered or old Jac
   syntax.
2. **Architecture and boundary reviewer — mandatory.** Check internal contracts,
   directory ownership, provider neutrality, privacy, idempotency, and
   integration impact.
3. **Lane specialist — mandatory.** Use the specialist named by the handoff to
   examine the lane's domain and acceptance tests.

Two reviewer agents are sufficient when one reviewer explicitly covers both the
architecture/boundary and lane-specialist roles. Use more only when the spec is
genuinely high-risk; review overhead must not eclipse the small Stage 1 scope.

Reviewers are advisory and read-only: they do not edit files. Give each reviewer
the handoff, draft spec, shared contract, and relevant source. Ask for findings
ranked as blocking, important, or optional, with exact evidence and a proposed
correction.

Record every material finding and its resolution in the implementation spec.
The spec is ready when all blocking findings are resolved and all three roles
agree that its acceptance evidence is sufficient. This is agent-panel review,
not a claim of human approval.

If reviewer subagents are unavailable, do not silently skip review. Record that
fact in the handoff report and ask the operator to open enough review sessions
to cover the three roles before implementation continues.

## 5. Implement the reviewed scope

- Reuse the released contracts, fake adapters, and walking skeleton.
- Keep product rules in the shared application core; adapters and clients do not
  invent competing lifecycle behavior.
- Use current Jac guidance and compile/check after small changes.
- Add deterministic tests with each behavior. Unit tests do not make live LLM or
  external-service calls.
- Treat unexpected contract needs as a proposal. A non-core lane records the
  smallest required contract change and continues with a compatible local fake
  only when the released contract permits it.
- Keep secrets and real personal data out of code, fixtures, logs, and commits.

Commit coherent increments when helpful. The final branch must represent one
complete Stage 1 handoff, not unrelated cleanup.

## 6. Implementation review panel

After the implementation and lane checks pass, run a second read-only review.
Use the same three roles and provide the final diff, implementation spec, test
output, and demo instructions.

The reviewers check that:

- the code implements the reviewed spec without scope growth;
- Jac usage is current and compiles cleanly;
- product and repository boundaries remain intact;
- negative paths and acceptance criteria are tested;
- no hidden dependency makes another lane or live service a Stage 1 blocker.

Resolve every blocking finding and either resolve or explicitly disposition each
important finding. Rerun the affected checks after corrections and record the
review in the implementation spec and handoff report.

## 7. Required validation

Every session runs:

```bash
./apps/connection-agent/scripts/check.sh
```

It also runs every lane-specific command named in its handoff. Before pushing,
inspect the full branch diff and confirm that every changed path belongs to the
handoff's writable list:

```bash
git status --short
git diff --check
git diff --stat "${BASELINE_SHA}..HEAD"
git diff --name-only "${BASELINE_SHA}..HEAD"
```

Use the immutable baseline recorded at startup, not the moving `origin/main`
reference. Do not merge or rebase merely because `main` changed after the
session began.

## 8. Commit, push, and handoff

Use clear commits scoped to the Stage 1 handoff. Then push only the assigned
branch:

```bash
git push -u origin HEAD
```

Never force-push and never merge to `main`. Copy
[`templates/HANDOFF_REPORT.md`](templates/HANDOFF_REPORT.md) to the exact
lane-owned report path named in the handoff, complete it, commit it, rerun the
applicable checks, and push the final commit.

The final response to the operator must include:

- assigned branch, recorded baseline SHA, and final commit SHA;
- concise delivered behavior and demo command;
- checks run and their results;
- spec-review and implementation-review evidence;
- changed-path summary;
- contract requests, known limitations, and integration notes;
- confirmation that the branch was pushed and `main` was not changed.

## 9. Consolidation belongs to orchestration

The primary checkout `/Users/sebastian/dev/jac_ddp` remains on `main` and is
reserved for consolidation. After the operator reports that the sessions are
done, the orchestration agent reviews branch scope and evidence, integrates in
dependency order, resolves shared failures, runs the complete demo and quality
gate with `./apps/connection-agent/scripts/check.sh --stage-1-integrated`, and
pushes the consolidated `main` only when green.
