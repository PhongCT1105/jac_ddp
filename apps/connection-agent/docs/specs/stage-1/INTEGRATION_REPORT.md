# Stage 1 consolidation report

**Status:** Integrated and verified

## Consolidated lanes

- Core operation façade and privacy/idempotency follow-up.
- Fixture data and compute-provider adapter.
- Whole-pool retrieval, grounded assessments, and viewer-specific cards.
- Jac web product journey and browser automation.
- Reproducible offline Evaluation and Quality scenario.

No coordinator, worker, sandbox, payment, or reputation behavior was moved
into the application during consolidation.

## Integration decisions

### One workload contract

The application lanes were developed against the foundation
`connection-embedding` `0.1.0` contract. The accepted JacGrid integration then
released the application-owned `1.0.0` package used by the live sandbox:
file-I/O invocation, a pinned MiniLM revision, 384-dimensional normalized
vectors, and separately tagged primary/fallback runtimes.

The initial combined tree failed because `MockJacGrid` still validated and
invoked `0.1.0`. Consolidation did not restore a competing old workload. The
application adapter now invokes `src/embed.jac`, validates the approved runtime
tag and complete ordered 384-dimensional results, and propagates the `1.0.0`
artifact identity into Intelligence. Offline tests select the workload's own
declared deterministic fallback; live workers select the pinned model when it
is installed. Both paths execute the same versioned package.

### Web and live API project configuration

The Jac project configuration preserves the live API dependency/serve settings
and adds the Jac web entrypoint plus its pinned client dependencies. The web
demo and the explicit live API launch remain separate commands in Stage 1.

### Product wording

Product Experience was implemented against the earlier static card wording.
The integrated Intelligence lane supplies grounded headlines and reasons. The
browser smoke assertions now verify that released grounded wording while
retaining the complete Alice → Bob → reciprocal match → private thread flow.

## Verification

The authoritative gate is:

```bash
./apps/connection-agent/scripts/check.sh --stage-1-integrated
```

It runs workload formatting/checks/tests, all application tests, browser build
and automation, the deterministic evaluation scenario, Jac-native source
policy, and provider-boundary checks.
