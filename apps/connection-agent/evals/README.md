# Stage 1 evaluation

Run the deterministic, offline Stage 1 product evaluation with:

```bash
./apps/connection-agent/evals/check.sh
```

The scenario calls only the released `DemoApp` operation façade. It verifies
the reciprocal Alice/Bob journey, whole-pool embedding recombination, private
one-sided interest, idempotent matching and messaging, Carol's authorization
denials, and isolation between demo instances. Its report contains only stable
invariant names and safe fixture IDs.
