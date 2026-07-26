# Jac-native engineering policy

**Status:** Mandatory for Connection Agent specifications, implementation, and
review

## 1. Rule

Everything that Jac can reasonably implement must be implemented in Jac.

All authored application runtime logic belongs in Jac, including:

- server endpoints, walkers, and application orchestration;
- domain models, lifecycle rules, authorization decisions, and persistence;
- matching, retrieval, AI functions, and card generation;
- the application-owned distributed workload and JacGrid adapter;
- the first-party client using Jac client code;
- tests, evaluation scenarios, and demo runners where Jac supports the task.

Generated Python or JavaScript emitted by the Jac compiler is build output, not
authored foreign-language application code.

## 2. Native-format exceptions

Use a non-Jac file only when the artifact inherently belongs to another format:

- `jac.toml` and other required tool configuration;
- JSON/JSON Schema contracts and fixtures;
- GitHub Actions or other declarative YAML;
- CSS, images, fonts, and other presentation assets;
- minimal POSIX shell needed to enter the Jac toolchain or coordinate Git and
  operating-system commands.

Python, TypeScript, or JavaScript source is not an automatic exception. If an
external library cannot be used through Jac's Python/npm interoperability, keep
the foreign-language boundary minimal and free of product logic.

## 3. Exception test

Before adding authored Python, TypeScript, JavaScript, or another general-purpose
language, the implementation spec must record:

1. the exact capability Jac lacks or cannot reasonably provide;
2. which current Jac MCP resources/guides were checked;
3. why Jac interoperability does not solve it;
4. the smallest foreign-language surface required;
5. how tests prove no domain, authorization, AI, matching, or lifecycle rule
   leaked into that surface;
6. approval from the mandatory current-Jac reviewer.

Convenience, familiarity, or copying an existing framework example is not a
sufficient reason.

## 4. Jac MCP is required

Every implementation and review session must have the built-in Jac MCP server
available through Codex. On this development machine it is registered globally
as:

```bash
codex mcp add jac -- jac mcp
```

Before work, verify:

```bash
codex mcp list
jac --version
jac mcp --inspect
```

The implementing agent uses Jac MCP to load current grammar, guides, examples,
and compiler tools. At minimum it consults `jac-core-cheatsheet`, `jac-types`,
`jac-project-kinds`, `jac-testing`, and the guides appropriate to its lane.

The agent must still run repository commands such as `jac check`, `jac fmt`,
`jac test`, and the root quality gate. MCP assists and verifies development; it
does not replace reproducible repository checks.

The root quality gate rejects authored Python, TypeScript, and JavaScript in
application/workload source paths. A formally approved exception must also add
its exact repository-relative path to
`apps/connection-agent/scripts/jac-native-exceptions.txt`; approval of an
exception is never implied by merely editing that allowlist.

## 5. Mandatory Jac reviewer

Every spec-review and implementation-review panel includes a current-Jac
expert. That reviewer must:

- use the installed Jac MCP rather than memory alone;
- record `jac --version` and the MCP resources/guides consulted;
- look for a simpler or more idiomatic Jac-native design;
- review client/server codespace boundaries and Jac interoperability;
- reject unnecessary authored Python/TypeScript/JavaScript;
- validate representative Jac code with compiler-backed tools;
- give an explicit `ready` or `blocking` verdict.

The session chooses the other reviewers appropriate to the work. Examples:

| Lane | Additional expertise |
|---|---|
| Core | application architecture, lifecycle, authorization, idempotency |
| Data/backend | Jac persistence/auth/multi-user security, backend testing |
| Intelligence | AI, retrieval, grounding, privacy, evaluation |
| Product experience | Jac client, mobile UX, accessibility |
| Evaluation | Jac testing, isolation, privacy, end-to-end behavior |

Two agents may cover the three concerns when the non-Jac reviewer combines the
architecture/boundary and lane-specialist roles. The Jac role is never optional.

## 6. Handoff evidence

The implementation spec and final handoff report record:

- installed Jac version;
- confirmation that `jac` MCP was available;
- MCP resources/guides used;
- Jac reviewer identity/task and verdict;
- any approved non-Jac exception;
- Jac format, check, test, and lane-demo evidence.
