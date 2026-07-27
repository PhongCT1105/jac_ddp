# JackSparrow

## Inspiration

At hackathons, people often form groups with whoever they already know or
happen to meet first. Someone with the perfect skills or idea may be in the same
room, but finding them early is difficult.

We built JackSparrow to help people discover who they should talk to and why.

## What it does

A user writes a short profile describing their interests, skills, and what they
want to build. The system searches 100 demo profiles and suggests three people.

The process is:

**profile text → distributed embeddings → ranked matches → LLM explanations**

Each result includes a simple explanation of why that person could be a useful
teammate or conversation partner.

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
