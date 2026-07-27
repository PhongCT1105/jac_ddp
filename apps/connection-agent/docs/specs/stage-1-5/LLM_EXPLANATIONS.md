# Stage 1.5 amendment — grounded LLM explanations

**Status:** Accepted focused product correction

## Outcome

Embedding retrieval still selects the same top three candidates from the full
corpus. After retrieval, one server-side OpenAI call receives only the visitor
profile and those three candidate profiles and returns one short explanation
per candidate in clear language.

Each explanation answers **why this person may be worth a conversation**. It
may describe specific shared interests, complementary experience, or a useful
conversation direction, but must use only facts present in the two supplied
profiles. It must not claim compatibility, consent, availability, or knowledge
of either person beyond their text.

## Contract

- The API key remains server-side and is read from `OPENAI_API_KEY`.
- The model is configurable and defaults to the current balanced OpenAI tier.
- The three explanations are generated in one request with a typed structured
  result.
- Returned IDs must exactly match the retrieved candidates; malformed,
  duplicate, missing, blank, or oversized explanations are rejected.
- Tests inject recorded explanations and never call or bill OpenAI.
- A live explanation failure returns a safe retryable error; it must not expose
  the key, provider response, prompt, or either complete profile.

## Results UI

The visible results screen contains only:

1. a short `Your top connections` heading;
2. one unobtrusive fictional-demo note;
3. three cards with name and `Why you might connect` explanation;
4. an optional collapsed profile excerpt;
5. edit/start-over actions.

Scores, IDs, embedding counts, runtime provenance, and workload identity move
to one collapsed technical-details section. Long disclaimers, repeated badges,
and generic embedding explanations are removed.

## Acceptance

- Retrieval order is unchanged by the LLM.
- Exactly three grounded explanations render with the correct candidates.
- The browser never receives the OpenAI key or raw provider response.
- Missing key, rate limit, malformed output, and model failure are safe and
  retryable.
- Jac checks, token-free tests, client build, and browser smoke pass.
