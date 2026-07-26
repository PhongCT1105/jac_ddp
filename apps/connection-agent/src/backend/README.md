# Jac backend

This folder is reserved for Jac-native server endpoints, persistent graph
models, authentication/multi-user access, and realtime behavior owned by the
Data and Integrations objective.

Application lifecycle rules remain in `src/core/`. External service adapters,
including `LiveJacGrid`, remain in `src/adapters/`. Auth, persistence, and
realtime product logic must not be implemented in Python, TypeScript, or a
Supabase client.
