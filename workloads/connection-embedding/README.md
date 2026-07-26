# connection-embedding

This is the versioned computation supplied by Connection Agent and executed through local, JacGrid, or future compatible compute adapters.

Version `0.1.0` is a deterministic, dependency-free fixture model for the foundation walking skeleton. It proves packaging, schemas, invocation, completeness, normalization, and provider parity. The Intelligence and Workload objective will release a new version with the selected production embedding model; it must not silently change `0.1.0`.

## Run locally

From this directory:

```bash
printf '%s\n' '{"contract_version":1,"items":[{"id":"profile_revision_01","text":"builder climbing distributed systems"}]}' | jac run src/main.jac
jac test -d tests
```

The command accepts one JSON document on standard input and writes one JSON document on standard output. Logs, if later added, belong on standard error and must not contain profile text or vectors by default.

The package contains no application persistence, worker scheduling, payment, candidate ranking, pair assessment, consent, match, thread, message, or UI logic.
