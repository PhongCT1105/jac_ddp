# Product book: AI connection agent

AI connection agent is a consent-based network that helps people and their personal AIs arrange useful real-world meetings.

## 1. The premise

AI is often framed as something that keeps people in front of a screen. Connection Agent takes the opposite bet: AI can be social infrastructure. It can help a person articulate what they are looking for, notice a promising connection that conventional filters would miss, and lower the small logistical and emotional barriers that stop two people from meeting.

The intended success metric is not time spent swiping or chatting with an assistant. It is whether people have a conversation, a walk, a coffee, a collaboration, a study session, a language exchange, or a recurring local ritual that would otherwise not have happened.

## 2. The problem

After university, meeting new people becomes unusually hard. Most systems either require a large, pre-existing crowd around a fixed activity, or reduce people to a questionnaire, a directory, or a swipe feed.

That fails because the stated activity is often not the real need. Someone may say they want to learn watercolor, but what they really want is a gentle recurring reason to meet interesting people on Thursday afternoons. Someone attending a Jac hackathon may be interested in Jac, but their deeper goal may be to meet technically curious people in San Francisco.

Human friends make introductions differently. They carry many soft signals: what someone cares about intensely, what they are merely open to, their temperament, their current chapter, their constraints, and the intuition that two people might enjoy a particular conversation. Connection Agent tries to make a small, accountable version of that capability possible without asking people to become public, standardized profiles.

## 3. Product thesis

Connection Agent has two complementary kinds of intelligence:

1. A person's own AI can know them over time. It may have conversation context, memories, or access to public information the person asks it to review.
2. Connection Agent knows the shared, permissioned social network: which people have joined, what their profiles say, which introductions are reciprocal, and how to coordinate a safe next step.

The dividing line is simple:

> Your AI helps you represent yourself. Connection Agent helps people encounter one another.

Connection Agent should receive only the context a person deliberately places in their Connection Agent profile. Once it is there, the matching AI may read it and select relevant parts for a card. Connection Agent should never need a person's full AI history, browser history, or private notes to make a good introduction.

## 4. What Connection Agent is — and is not

Connection Agent is:

- A living, intent-aware connection layer.
- A way to create thoughtful suggested-person cards and mutual matches around a current desire to meet, learn, make, explore, or talk.
- A product that can work through Connection Agent's own conversational experience or a person's chosen AI.
- A product whose default outcome is an interaction between people, not an extended interaction with a model.
- A real-identity network: people use their full names and stand behind the profile they create.

Connection Agent is not:

- A public social directory.
- A dating swipe feed.
- A platform that ranks people by appearance.
- A rigid questionnaire or a deterministic interest-tag matcher.
- A persuasion engine that tries to convince users to meet people for the platform's benefit.
- A replacement for the personal AI someone already trusts.

Romance, professional collaboration, friendship, learning, and serendipity may all be valid intentions. Connection Agent should not become only a dating product, but it should not prohibit people from using it to seek romance. In the first version, there are no profile photos or appearance-first cards. A person may place social-media links in their profile and choose to share them as part of the normal matching or chat experience. Whether Connection Agent later adopts a restrained LinkedIn-like profile photo is intentionally unresolved.

## 5. The canonical Markdown profile

Each person has one canonical Markdown document. It is readable by the person, editable directly if desired, and normally maintained through conversation with an agent. It can hold a full name, interests, current intentions, stories, constraints, social links, and plain-language instructions about when something should be shared.

Everything saved in this Markdown document is readable by Connection Agent's matching AI and may be selected when presenting the person to someone else. The AI chooses the relevant subset; it does not dump the whole document into a card. More elaborate progressive-disclosure controls may be considered in the future, but they are not part of the initial model.

The Markdown document is the human-readable source of truth. It is not the card shown to everyone. For each viewer and current request, Connection Agent selects relevant material from that document and creates a different presentation.

```text
one canonical Markdown profile
             |
             +-- derived search representation: embedding, facets, signals
             +-- card for viewer A: emphasizes one possible connection
             +-- card for viewer B: emphasizes another possible connection
```

Derived data may include embeddings, free-form facets or tags, and other search signals. These exist to retrieve a short candidate list efficiently; they do not replace the Markdown profile and are not themselves the user's public identity.

The application team owns the versioned computation that creates embeddings. In the hackathon integration, JacGrid distributes that workload across workers and returns verified vectors, while Supabase remains the durable store for the current projection. JacGrid does not rank people or own profiles, consent, suggestions, matches, or messages.

A person's private ChatGPT, Claude, or other agent context stays outside Connection Agent. Their agent may use that context or public web research to propose additions, but the person decides what enters the Connection Agent Markdown profile.

### Time-bounded information

The same Markdown document may contain facts that are true only for a while: “I want someone to ride bikes with this weekend,” “I am in San Francisco through Tuesday,” or “I am attending a technology conference today.” These statements should include their natural time boundary so the AI can interpret them correctly.

For the hackathon, no separate temporary-profile system is needed. The agent can use the current conversation immediately and save useful time-bounded information in the Markdown profile. Later, Connection Agent may clean up stale passages, maintain a separate internal current-context projection, or ask whether something is still true. Those are storage and maintenance refinements, not a different user experience.

## 6. Conversation-first joining

Joining should feel like talking with a thoughtful host, not completing a form.

A person may say: “I want to meet someone at the hackathon,” “I want an excuse to learn something hands-on with another person,” or “I am travelling next week and would enjoy a local conversation about literature.” The agent reflects an interpretation and offers a small number of editable possibilities rather than forcing them into fields.

Recommended behavior:

- Usually ask one useful question at a time, without turning that into a rigid protocol.
- Start with the person's current hope, not demographics.
- Offer interpretations: “It sounds as if the activity matters less than finding a recurring social ritual — is that right?”
- Let the person type anything rather than only choosing presets.
- Ask only for information that could improve this kind of introduction.
- Treat remembered or web-found information as a draft, never as something automatically added to the Connection Agent profile.
- Before first saving new personal information, make the proposed profile change understandable and let the person approve or edit it. Pure rewrites that preserve meaning need not create approval fatigue.

The agent should not turn a living conversation into a disguised questionnaire.

## 7. Matching philosophy

### 7.1 Mutual eligibility before suggestion

A person may be shown only when both people fit each other's relevant hard constraints. That does not mean the other person has already seen the card or expressed interest. The system must not imply mutual interest until both people independently choose that they would be open to meeting.

### 7.2 Activity as a social container

Matching should distinguish the stated activity from its underlying role. Watercolor and knitting may be compatible not because they are the same skill, but because both people want a gentle, hands-on, local way to meet someone interesting. Dogs and biology may be compatible when one person's curiosity about dogs is a path into the other's enthusiasm for living systems.

### 7.3 Let breadth emerge through conversation

The first product should not force people to select categories such as Exact, Adjacent, or Serendipitous. The AI can infer how narrowly or broadly someone means an interest, offer an interpretation, and ask for clarification only when it matters. A user-facing breadth control may be considered later if real behavior shows it is useful.

### 7.4 Inform, do not persuade

The introduction explanation is on the person's side. It should say why the connection may be worthwhile, what is uncertain, and what a low-pressure first encounter could be. It should never optimize for acceptance at all costs.

## 8. How matching can scale

Connection Agent should not send every full profile to an LLM against every other full profile. The network grows quadratically if every pair is considered.

The recommended scalable matching path is a hybrid:

1. Deterministic eligibility checks: blocks, basic safety rules, and hard boundaries explicitly stated by either person.
2. Semantic retrieval: find a manageable candidate set whose Markdown profiles and current requests are plausibly related.
3. Relationship and graph signals where they genuinely add information, such as prior suggestions, previous matches, or shared time-bounded context.
4. Deep LLM reasoning: assess only the best candidates for a reciprocal match hypothesis.
5. Mutual consent: reveal only what each person approved, then create a private thread if both choose to proceed.

For a very small hackathon population, comparing the available Markdown profiles directly would work. Implementing semantic retrieval early is still worthwhile because it establishes the correct scalable shape: an embedding finds a short candidate list, then the LLM reads the original Markdown profiles and reasons carefully about those candidates.

## 9. Trust, consent, and safety

Trust is not a policy page added at the end. It is the product.

Non-negotiable principles:

- A person's phone number is never exposed to another member.
- No one receives a private profile merely because they ask an agent to find people.
- Suggested cards never claim mutual interest before both people opt in.
- The agent never sends messages, discloses contact information, or books a venue without the relevant confirmation.
- Cards use real full names. Other details, including social links, are shown according to what the person placed in their profile and the sharing instructions expressed there.
- Photos are not part of first-version cards. A person can include social-media links in their Markdown profile.
- Hard safety rules, blocks, age/eligibility constraints where relevant, and permissions are deterministic system rules—not LLM judgment calls.
- The model should state uncertainty rather than inventing certainty about compatibility.

## 10. The core experience

The product is chat-first, with several moments:

1. **Enter:** open the ordinary product link, wherever it was shared.
2. **Articulate:** talk to Connection Agent's agent or a personal AI about what you hope for.
3. **Approve:** review what will be added to the Connection Agent Markdown profile.
4. **Discover:** receive a small number of thoughtful suggested-person cards rather than an infinite feed.
5. **Explore:** ask why this person might be interesting or ask what else in their profile is relevant.
6. **Accept or pass:** each person independently chooses whether they would be open to a conversation.
7. **Match and meet:** when both choose yes, Connection Agent opens a direct two-person private chat and, when invited, helps coordinate a time or venue.
8. **Close the loop:** participants can say whether they met, which improves the system only in ways they understand and approve.

### Cards live inside the conversation

Discovery is not a separate swipe screen. The user asks the agent to show someone, and the agent inserts one dynamic card into the chat. The card remains above as conversation history. The user can then say “tell me more about this person,” “why do you think we might connect?”, “I’d be open,” “pass,” or “show me someone else.”

The first-party card should be generated as mobile-safe ASCII. It should avoid fragile box drawing—especially vertical borders that wrap badly—and prefer short lines, whitespace, and horizontal separators. After the card, ordinary conversation resumes. In an external chatbot, the same content may be presented in the host's natural text format, but the one-person-at-a-time conversational behavior remains.

## 11. Agent-native, not agent-only

Connection Agent should have two entry paths.

### First-party conversational agent

The ready-to-use first-party conversation and mobile web experience. It gives people a frictionless join flow, predictable interaction quality, notifications, private direct chat, and a shared space when two participants use different personal AIs.

### External-agent connection

The same social capabilities exposed to the person's chosen AI through an MCP/API connection. Their agent can use its own context and, if the person asks, public web research to draft an approved Connection Agent contribution.

These are not two backends or two networks. They are two clients of one permissioned Connection Agent core.

## 12. Events as contextual signals

Hackathons and conferences are strong matching signals because people are co-located, share temporary context, and are already open to conversation.

Connection Agent does not need a separate event product or event-specific matching function. “I am attending the Jac hackathon today” can be handled exactly like “I want to ride bikes this weekend”: it is time-bounded context in a person's conversation and profile. When two people mention the same event, the matching system may weigh that shared context strongly.

At the hackathon, the presenter simply shares the ordinary app link or QR code. A person may naturally say how they heard about the product or that they are currently at the hackathon.

In the future, agents could maintain a lightweight list of events they have recently encountered and ask a relevant onboarding question such as “Are you joining from one of these events?” That would help normalize the shared signal without creating event accounts, registration verification, or a separate event workflow.

The event promise remains useful:

> “Tell Connection Agent what kind of conversation you would be glad to have today. It will try to find one person for whom that is reciprocally true.”

Events are also a plausible buyer. The organizer pays for a better attendee experience and more meaningful interaction, not for an addictive feed. Nearby venues can later be partners: only after a match, Connection Agent may offer a clearly labeled, relevant coffee-shop or activity suggestion. Sponsorship must never influence who is presented as a good match.

The first-party Connection Agent experience must stand on its own. Personal-AI connection is an unusually powerful enhancement, not a condition for receiving a good suggestion.

## 13. Business model principles

Potential revenue paths include:

- Event and conference licenses.
- Community or membership organization plans.
- Clearly labeled sponsored venues or activities after mutual interest.
- Optional paid coordination or premium organizational features.

Avoid revenue mechanisms that conflict with the social promise: paid visibility, phantom matches, pressure to keep swiping, or hiding likely reciprocity behind a paywall.

## 14. Hackathon MVP

The hackathon uses the normal product in a concentrated room. It should prove this narrative:

1. A person opens the ordinary product link shared at the hackathon.
2. In chat, they create or improve their Markdown profile and describe what they want now.
3. Connection Agent saves the profile information they approve.
4. Connection Agent shows each person a genuinely plausible suggested-person card.
5. Both people independently choose that they would be open to meeting.
6. Connection Agent creates a match and opens a simple private chat, then proposes a nearby time or coffee location if asked.
7. They meet.

If that works for even a small number of people, it demonstrates the heart of the product.

### An honest no-match path

Connection Agent must not manufacture a connection to preserve the promise. If there is no credible suggested-person card yet, it should say so plainly and invite the person to revise or broaden what they are looking for if they wish. “Not yet” is better than a hollow card.

## 15. Product principles

1. Optimize for a worthwhile encounter, not engagement.
2. The person owns their context and decides what enters their Connection Agent profile.
3. The system is user-aligned: explain, do not persuade.
4. Mutual eligibility precedes a card; mutual interest creates a match.
5. Use rich language before forcing people into a schema.
6. Keep hard boundaries deterministic and inspectable.
7. The activity may be an excuse; understand the underlying social desire.
8. Personal AI context is powerful, but sharing is always deliberate.
9. An external agent is a client, not the owner of the social graph.
10. The best outcome happens away from the app.

## 16. Longer-term possibilities

Connection Agent may eventually support travel conversations, local recurring groups, language practice, learning partners, creative rituals, older adults or people with mobility constraints who prefer online encounters, conference speaker introductions, and small group formation.

The core remains the same: help people articulate a current desire, find reciprocal compatibility among allowed possibilities, and make an encounter easier.
