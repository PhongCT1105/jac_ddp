# Web experience

This directory contains the Stage 1.5 Jac first-party browser experience. A
visitor enters a name or nickname and a free-form profile, then receives three
fictional profiles with concise, grounded explanations of why a conversation
might be worthwhile. Profile excerpts and technical evidence stay collapsed by
default so the result remains easy to scan.

## Local demo

From the repository root, run:

```bash
./apps/connection-agent/web/start.sh
```

Live explanations use the server-side `OPENAI_API_KEY`; the key is never sent to
the browser. To run a token-free deterministic presentation using the recorded
test explanations, use:

```bash
CONNECTION_EXPLANATIONS_MODE=recorded ./apps/connection-agent/web/start.sh
```

The start script prefers the pinned MiniLM embedding model when it is installed.
The visitor profile and the three retrieved fictional profiles are processed by
the server-side explanation provider. The application does not intentionally
persist the visitor profile. Do not enter sensitive information in the public
demo.

The earlier reciprocal Alice/Bob Stage 1 fixture remains in `fixture.jac` and
continues to be covered by its semantic tests; it is no longer the default UI.
