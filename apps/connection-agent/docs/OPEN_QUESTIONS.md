# Open questions: AI connection agent

This file contains only decisions that remain genuinely open after the product conversation. Settled decisions belong in the Product Book or Technical Direction.

## Decisions already made

- Each user has one canonical Markdown profile.
- People use their real full names; the first version relies on self-declaration rather than identity-document verification.
- Cards are dynamically created for one viewer and appear one at a time inside chat.
- A person can ask about the current card, express interest, pass, or request the next person.
- Both people must fit each other's relevant hard constraints before either is suggested.
- Mutual interest creates a match and opens a private human-to-human web chat.
- Romance is allowed, but the product is not designed as an appearance-first dating feed.
- No profile photos in V1; social-media links may live in Markdown.
- Phone OTP is the only V1 login and notification identity; no account recovery is built yet.
- The hackathon uses the ordinary app link. There is no event object, event verification, or special event function.
- The first-party agent and outside agents use one product MCP contract; the public integration is a parallel nice-to-have for the hackathon.
- Exact/Adjacent/Serendipitous are not V1 settings. Breadth is inferred and clarified through conversation.
- Everything saved in the Markdown profile is readable by Connection Agent's matching AI and may be selected when relevant to a card.
- Time-bounded facts can live in the same Markdown document in V1; no temporary-profile infrastructure is needed.
- Every signed-in profile is eligible for matching in the hackathon, subject only to relevant constraints expressed in the profiles or conversation.
- Event attendance is ordinary time-bounded context, not event membership or a separate matching feature.

## Questions that can wait

- Whether to add one restrained LinkedIn-like profile photo.
- Whether cards in external chat hosts should always use ASCII or adapt to each host's native formatting.
- Which external agent host should receive the first polished integration.
- Whether agents should maintain a lightweight current-events list for optional onboarding questions.
- Whether stale time-bounded profile passages should be removed, archived, or projected into a separate internal current-context record.
- Named-person search, including how speakers or public figures control availability.
- Groups rather than pairs.
- Connected-agent management and revocation UI.
- Account recovery after a phone number changes.
- Post-meeting feedback and fairness/popularity controls.
- The permanent product name; “Connection Agent” remains only a working descriptor.
