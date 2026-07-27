# JackSparrow

## Inspiration

Finding the right person is a complex matching problem. People may connect through shared interests, complementary skills, similar values, compatible working styles, or a specific problem they both care about. These dimensions are hard to reduce to filters or a single score.

Most matchmaking products optimize for a fixed goal, such as dating, hiring, or skill coverage. JackSparrow does not hard-code one definition of a good match. A user describes the connection they want in natural language, so the same system can help find teammates, collaborators, mentors, friends, or people with a shared interest.

A hackathon is one clear example: people need to form groups early, but often work with whoever they already know or happen to meet first. A participant might write: “I am building tools for education and want to meet someone interested in distributed systems, creative AI, or helping people learn.” Connection Agent can surface a designer who cares about accessible learning, a developer with distributed-systems experience, or an educator with firsthand knowledge of the problem. Instead of forming a group only through proximity or existing friendships, the participant gets a useful starting point for a conversation.

## What it does

A user writes a profile about their interests, skills, values, projects, and the kind of person they want to meet. Connection Agent searches 100 demo profiles and returns three suggestions with a clear reason for each one.

In the full product flow, a connection becomes a private chat only when both people independently choose to meet.

JacGrid, our distributed computing platform, divides the embedding work across connected computers. The embeddings are recombined and used to rank the complete profile pool. Then Jac's typed `by llm()` feature sends the user profile and the three selected profiles to an LLM, which produces a short grounded explanation for each suggestion.

**profile text → JacGrid distributed embeddings → ranked matches → LLM explanations**

Embeddings give us fast semantic retrieval across a large pool. The LLM adds qualitative analysis: it can explain shared or complementary themes in two free-form profiles. Together, this avoids forcing every kind of human connection into one predefined optimization function.

## How we built it

We built the browser interface, backend, typed models, matching flow, LLM call, embedding workload, JacGrid coordinator, worker logic, validation, and tests in Jac. JacGrid verifies results, retries failed tasks, and recombines the output before Connection Agent ranks the matches.

## Challenges

The main challenge was connecting the application to the distributed platform without mixing their responsibilities. We also had to ensure the full profile pool was recombined before ranking, and that the LLM explained the final matches without changing their order or inventing details.

## What we learned

We learned that Jac can cover the full stack: frontend, backend, typed LLM calls, testing, and distributed computing. Using one language across the product and JacGrid made it much easier to connect the user experience, matching logic, and shared computing infrastructure.

## How we use Jac and Jaseci tools

We use Jac across the full project. The Connection Agent browser interface, backend operations, typed data models, matching logic, tests, and OpenAI integration are written in Jac.

For matching, Jac runs the embedding workflow that turns free-form profiles into vectors. JacGrid, also built in Jac, distributes that embedding work across connected computers, verifies and recombines the results, and returns the complete ranked pool.

After retrieval, we use Jac's typed `by llm()` feature to send the user profile and the three selected profiles to an LLM. It returns a structured explanation of why each suggested connection may be relevant.

We also use Jac's graph-oriented model for people, suggestions, mutual interest, matches, and private conversations. This lets the product's frontend, backend, AI workflow, and distributed computing platform share one language and one set of typed contracts.
