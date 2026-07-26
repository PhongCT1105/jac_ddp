# Hackathon demo: AI connection agent

> **Target-stage note:** This document describes the final live hackathon
> presentation. The earlier, time-protected local showcase is defined in
> [`STAGE_1_PRODUCT.md`](STAGE_1_PRODUCT.md). Phone OTP, production persistence,
> live messaging, and coordination remain final-demo goals but are deliberately
> not Stage 1 blockers.

## Goal

Demonstrate one complete loop of the normal Connection Agent product: a person creates a profile, asks to meet someone, explores a suggested person in chat, and enters a private chat after mutual interest.

The demo should make people feel that AI is helping them leave the screen, not asking them to live inside another feed.

## Audience and setting

The initial setting is a San Francisco Jac hackathon. The presenter shares the ordinary app link as a QR code. The application does not model the hackathon as an event or verify attendance; the room simply gives the product a concentrated first population.

## The attendee story

### 1. Join

The attendee scans the QR code and arrives at a minimal mobile web page:

```text
Connection Agent
Find one conversation worth having today.

[ Start talking ]
```

The complete path works in Connection Agent without external-agent setup. If the MCP integration is ready, a person may instead use an external agent that is already connected to the same Connection Agent tools; this is a parallel nice-to-have rather than a separate event entry flow.

### 2. Articulate a current desire

The Connection Agent agent begins conversationally. A new person can describe themselves, ask their existing personal AI for help, or simply state what they want now:

```text
Tell me a little about yourself, or tell me who you would like to meet.
```

The attendee can answer naturally. They may mention that they heard about Connection Agent at the Jac hackathon; this becomes ordinary time-bounded profile context, not event membership. The agent reflects a likely interpretation and asks only the next useful question. It may offer a few options, but the options are invitations to clarify—not a survey.

### 3. Build the Markdown profile

The conversation creates or updates one readable Markdown profile. Before first saving new personal information, the agent shows a concise draft:

```text
# Sebastian

I work in education and am especially interested in AI, technology,
and products that help people connect in real life.

Right now I would enjoy meeting thoughtful technical people in
San Francisco for a coffee, walk, or conversation.

I am at the Jac hackathon today and would be especially glad
to meet someone else who is here.

[ Save to my profile ] [ Edit ]
```

The person may later ask to see the complete Markdown document or edit it directly. Everything in this profile is readable by Connection Agent's matching AI, which selects only what is relevant for a particular card.

### 4. See a suggested-person card

The user asks “show me someone.” Connection Agent retrieves a short candidate list, reasons over the original profiles, and inserts one card into the chat. It does not claim that the other person has already seen the card, wants to meet, or is a match.

```text
--------------------------------
MAYA CHEN

Community science · learning · AI

You both seem interested in using technology
to make learning and community more human.

Maya would like to meet people thinking about
AI beyond individual productivity.
--------------------------------

You can ask me more, say “I’d be open,”
or ask to see someone else.
```

The card uses short, mobile-safe lines and avoids vertical borders. It stays in the chat history. If the user says “tell me more about Maya,” ordinary chat continues below it using relevant information from Maya's Markdown profile. “Show me someone else” produces the next dynamic card.

### 5. Match

Maya receives an equivalent, independently tailored card. If both select “I’d be open,” Connection Agent says:

```text
It’s a match — you and Maya are both open to meeting.

I opened a private chat for both of you.

[ Open chat ]
```

### 6. Direct human chat

The private Connection Agent thread is a normal two-person chat. The card remains available above the conversation, but the agent steps back.

```text
You + Maya
Introduced around: humane technology and learning

Maya: Hi Sebastian — I liked the phrase “AI beyond productivity.”
You: Same. I’d love to hear what you’re building.

                     [ Ask Connection Agent to help coordinate ]
```

Connection Agent does not speak for either person. It can be summoned to help with logistics.

### 7. Coordinate a real encounter

If asked, Connection Agent requests the smallest useful information. For example, it may first ask one person whether they are free before asking the other for a complete schedule.

```text
Connection Agent: Maya is free for a short coffee after the next session.
Does 4:30 work for you?

[ Yes ] [ Suggest another time ]
```

Once both agree, Connection Agent may propose a nearby venue. A sponsored venue is clearly labeled and never affects the introduction itself.

### 8. If there is no credible card yet

Connection Agent does not invent one. It says so directly and offers a low-pressure next move:

```text
I don’t have a strong suggestion for that yet.
You can tell me more about what matters, ask for
something different, or try again after more people join.
```

This honest fallback is recommended; the more elaborate broadening workflow can wait.

## The own-AI path

If Connection Agent's public MCP connection is ready, someone may use ChatGPT, Claude, Codex, or another compatible assistant instead of Connection Agent's own agent. A starter instruction could be:

> Help me create or improve my Connection Agent profile. Use what you know about me and any public information I ask you to research, but show me proposed new information before saving it. Then help me find one person I might genuinely want to meet.

When the attendee has connected Connection Agent to their chosen agent, that agent can submit the approved draft and retrieve curated introductions using Connection Agent's capability layer. The accepted private thread still lives in Connection Agent web, so two people do not need to use the same agent host.

## What must be real in the demo

- Phone-number sign-in.
- Several real users who opened the same ordinary app link.
- Canonical Markdown profiles with full names.
- Conversational profile creation and current intent.
- Retrieval of a short candidate list.
- At least one credible introduction path.
- Independent “I’d be open” choices on both sides.
- A persistent two-person private chat.
- Live message delivery or a clear refresh experience.
- A minimal coordination suggestion.

## What can be deliberately constrained

- Matching may run on demand or in short batches.
- Only a few curated introductions are available.
- The venue list may be manual.
- SMS can be limited to OTP and an accepted-introduction notification.
- The public MCP integration may be implemented in parallel and omitted from the live demo if it is not ready.
- Event accounts, participant pools, and attendance verification do not exist.

## Demo success

The strongest evidence is not a model benchmark. It is hearing participants say: “I would not have met that person otherwise,” followed by an actual conversation during the event.
