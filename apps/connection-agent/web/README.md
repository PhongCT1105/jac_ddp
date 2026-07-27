# Web experience

This directory contains the Stage 1.5 Jac first-party browser experience. A
visitor enters a name or nickname and a free-form profile, then receives three
ranked fictional profiles from the complete demo corpus currently available.

## Local demo

From the repository root, run:

```bash
./apps/connection-agent/web/start.sh
```

No credentials or secrets are required. The start script prefers the pinned
MiniLM embedding model when it is installed; otherwise the UI clearly labels
the deterministic fallback. The visitor profile is not intentionally persisted.
Do not enter sensitive information in the public demo.

The earlier reciprocal Alice/Bob Stage 1 fixture remains in `fixture.jac` and
continues to be covered by its semantic tests; it is no longer the default UI.
