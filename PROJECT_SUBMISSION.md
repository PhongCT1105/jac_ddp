# JackSparrow

## Inspiration

Finding the right person is a complex matching problem. People may connect
through shared interests, complementary skills, similar values, compatible
working styles, or a specific problem they both care about. These dimensions
are difficult to represent with filters or a single similarity score.

We built JackSparrow to combine fast semantic search with qualitative LLM
analysis. A hackathon is one useful example: participants need to form groups
early, but often join whoever they already know or happen to meet first. The
right teammate may be in the same room and still remain undiscovered.

## What it does

A user writes a profile describing their interests, skills, values, projects,
and the kind of person they want to meet. The system searches 100 demo profiles
and suggests three people.

The process is:

**profile text → distributed embeddings → ranked matches → LLM explanations**

Embeddings make it practical to retrieve the strongest candidates from the
complete pool. An LLM then compares the richer meaning in both profiles and
writes a grounded explanation of the shared or complementary dimensions. This
combines quantitative retrieval with qualitative analysis instead of treating
human connection as one score.

## How we built it

We built the entire project in Jac:

- The browser interface and backend
- Typed data models and matching logic
- Embedding generation distributed across computers with JacGrid
- Result verification, retries, and recombination
- LLM explanations using Jac's typed `by llm()` feature
- Automated tests

JacGrid divides the embedding workload between available computers and combines
the results before ranking the profiles.

## Challenges

The main challenge was keeping responsibilities clear between the application
and the distributed platform. We also had to make sure every profile was
recombined before ranking and that the LLM explained the selected matches
without changing their order or inventing details.

## What we learned

We learned that Jac can support much more than AI agents. We used it for the
frontend, backend, typed LLM calls, testing, and a distributed computing
platform.

Having the complete system in one language made it easier to connect the user
experience, AI workflow, and shared computing infrastructure.
