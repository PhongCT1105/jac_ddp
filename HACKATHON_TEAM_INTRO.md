# AI connection agent

AI connection agent is an AI matchmaker for real-world human connection.

People talk to the agent about themselves and who they would like to meet. Someone might want to discuss science, ride bikes, practice a language, find other people working in technology, or simply have an interesting conversation.

The agent saves the information that the person approves in a Markdown profile. The profile can include long-term interests and short-term requests. Sebastian's profile might include:

```text
I work in education and care about science and technology.

I am at the Jac hackathon today. I would like to meet someone
who is thinking about unusual uses of AI.
```

When the person asks to see someone, the system searches the other profiles and chooses one possible connection. The two people do not need to describe the same job or interest. Sebastian works on live small-group learning, while Phong works on applied AI and teaches AI and machine learning. Luke develops a hospitality product and produces marketing content, while Santhos tests wireless products. The LLM reads the profiles and works out whether there is a useful reason for each pair to talk.

The agent shows one person at a time in the chat. The card explains why this person was selected. The user can ask for more information, pass, say they are open to meeting, or ask to see someone else.

Here are two cards made from the public professional information of the hackathon team.

### Card 1: Phong shown to Sebastian

```text
--------------------------------
PHONG CAO

Applied AI and machine learning
LLM agents, MCP, RAG
Teaching assistant in AI and ML

Why I selected Phong

You build live group learning
products. Phong teaches AI
and machine learning and has
tested AI tools for students.

You could compare when an AI
agent should help a group and
when the group should work
without it.

A possible question

What should an AI agent do
before and after a live class?
--------------------------------

Ask about Phong, say you are
open, pass, or ask for someone
else.
```

### Card 2: Santhos shown to Luke

```text
--------------------------------
SANTHOS SELVI KRISHNA KUMAR

Senior QA engineer at Aruba
Wireless systems and QA

Why I selected Santhos

You develop products for hotels
and make content about places
people visit in person.

Santhos tests wireless systems
for connectivity, security,
performance, and user problems.

You could compare how a digital
product is built, tested, and
explained to its users.

A possible question

Which failures matter most when
guests use a digital product at
a real venue?
--------------------------------

Ask about Santhos, say you are
open, pass, or ask for someone
else.
```

The examples use public information from [Sebastian Marambio](https://www.linkedin.com/in/smarambio/), [Phong Cao](https://www.linkedin.com/in/phong-cao/), [Luke Lacey](https://www.linkedin.com/in/luke-lacey-1b9563164/), and [Santhos Selvi Krishna Kumar](https://www.linkedin.com/in/santhos-selvi-krishna-kumar-8617445b/). The cards show possible reasons to talk. They do not claim that either person has already expressed interest.

The other person gets a separate card written for them. They are not told that the first person expressed interest. If both people independently say they are open to meeting, the system creates a match and opens a private chat. The agent can help them find a time to meet if they ask.

## Basic flow

```text
Talk to the agent
        ↓
Approve a Markdown profile
        ↓
Ask to see someone
        ↓
Receive one suggested person in the chat
        ↓
Ask questions, pass, or express interest
        ↓
Both people express interest
        ↓
Private human chat
        ↓
Meet in person or online
```

# Annex: What Jac is good for

Jac is designed for programs that work with connected data. Its main graph concepts are nodes, edges, and walkers.

- A node is a thing, such as a person or a private chat.
- An edge is a relationship between two things.
- A walker is an operation that moves through nodes and edges and does work along the way.

Jac also has `by llm()`, which lets an LLM produce a typed result for part of a program. The program can ask for a pair assessment or card description instead of accepting an arbitrary block of model-generated text.

## The graph in this app

People, matches, and private chats can be represented as nodes. Candidate relationships, interest, and matches can be represented as edges.

```text
Person ── candidate for ──> Person
Person ── open to meeting ──> Person
Person ── matched with ──> Person
Match ── has thread ──> Private chat
```

Some edges exist only while the system is searching. Suppose semantic search finds 30 profiles that might be relevant to Sebastian. Jac can create a small candidate graph:

```text
Sebastian ── candidate ──> Phong
Sebastian ── candidate ──> Luke
Sebastian ── candidate ──> Santhos
```

Each candidate edge can store information such as:

- The semantic search score.
- The profile revisions used.
- Whether either person blocked the other.
- Whether this person was already shown.
- Evidence that may explain the connection.

Other edges record decisions that need to last:

```text
Sebastian ── open to meeting ──> Phong
Phong ── open to meeting ──> Sebastian
```

When both edges exist for the same pair, the application creates one match and one private chat.

## What the walker does

Semantic search first reduces the number of profiles that need close analysis. A Jac walker then moves through that smaller candidate graph.

```text
Start with the current person
        ↓
Visit the candidate nodes
        ↓
Remove blocked or invalid candidates
        ↓
Read the profiles and retrieval evidence
        ↓
Ask the LLM to assess the best pairs
        ↓
Return one person or return no suggestion
```

The walker carries the current request while it visits candidates. For example:

```text
I want to meet someone at the hackathon who works on applied AI.
```

The request does not need its own permanent database object. It can be part of the current matching operation. If the user wants it saved for later, the agent adds a dated sentence to the Markdown profile.

## What the LLM does

Code handles rules that have an exact answer:

- Do not suggest the current user to themselves.
- Exclude people who blocked each other.
- Do not create a match after one person says yes.
- Do not create two chats for the same match.

The LLM handles questions that require interpretation:

- Why might these two people want to talk?
- Are their interests related even if the words are different?
- Which profile details matter to this viewer?
- Is the connection strong enough to show?
- How should the card explain the connection?

The LLM returns structured results such as:

```text
Pair assessment
- should this person be shown?
- reasons
- supporting facts from both profiles
- uncertainty

Card content
- name
- relevant information
- reason for the suggestion
- possible topic of conversation
```

The application checks these results before saving anything or showing a card.

## What stays outside Jac

Supabase stores phone accounts, Markdown profiles, embeddings, decisions, matches, threads, and messages. It also handles row-level security and realtime chat.

The web client displays the conversation, profile proposals, cards, phone login, and private human chat.

Jac handles the candidate graph, traversal, pair assessment, card content, and matching workflow. Supabase remains the database for durable user data.

## Why the app fits Jac

The matching problem involves a changing set of relationships between people. The system retrieves a small group of candidates, moves through that group, combines fixed rules with LLM interpretation, and changes the graph when people express interest or match.

Using Jac only to send two profiles to an LLM and return a string would use very little of the language. This design uses its graph, walker, and typed LLM features in the matching path:

```text
semantic search
        ↓
candidate graph
        ↓
walker with the user's request
        ↓
typed pair assessment
        ↓
card for one viewer
        ↓
interest edges
        ↓
match and private chat
```
