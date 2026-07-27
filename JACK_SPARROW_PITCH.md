# JackSparrow

JackSparrow helps people find someone worth talking to.

A user writes a short profile about who they are, what they are working on, and
who they would like to meet. Connection Agent compares it with the available
profiles and returns three people with a clear reason for each suggestion.

## How it works

1. Connection Agent sends the user profile and the profile pool to JacGrid.
2. JacGrid distributes the embedding work across connected computers.
3. The completed embeddings are recombined and used to rank the full pool.
4. The user profile and the three highest-ranked profiles go to an LLM through
   Jac's typed `by llm()` feature.
5. The LLM writes a short, grounded explanation for each result.

The demo uses 100 fictional profiles. The next version uses real, opted-in
profiles and creates a private conversation only after both people independently
choose to meet.

## JacGrid

JacGrid is the distributed system underneath Connection Agent. It divides work
between computers, verifies results, retries failed tasks, and recombines the
output. Connection Agent is its first application, but JacGrid can run workloads
for other applications too.

## Built in Jac

The browser interface, server, typed models, matching flow, LLM call, embedding
workload, distributed coordinator, worker logic, validation, and tests are all
built in Jac.

The full path is:

**profile text → distributed embeddings → ranked matches → LLM explanations**
