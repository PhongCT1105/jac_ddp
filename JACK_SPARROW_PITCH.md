# Jack Sparrow

> A connection agent built in Jac that helps you find one person worth meeting.

People go to hackathons and conferences to meet others, but most still talk to
whoever they know or happen to sit beside. An attendee can be surrounded by
hundreds of relevant people without knowing who they are. A directory or
networking feed does not give them a useful reason to talk now.

Jack Sparrow lets a person describe themselves, what they are working on, and
who they would like to meet in ordinary language. It searches the profiles of
people who chose to join and explains why a particular conversation might be
worthwhile. If both people independently say they are open to meeting, it
creates a private chat for them.

At this hackathon, an attendee might write:

> I am building tools for education. I would like to meet someone working on
> distributed systems, unusual uses of AI, or technology that brings people
> together in real life.

Jack Sparrow could find a relevant attendee and, after mutual interest, help
them meet during the event. The goal is a conversation or collaboration that
would not otherwise have happened—not more time in an app.

## Built in Jac

Jack Sparrow is built in Jac from front to back: browser interface, server
operations, typed models, matching, privacy, messaging, tests, and embedding
workload.

Jac fits because the product is a graph of people, suggestions, private
decisions, matches, and conversations. Walkers find candidates, record
interest, create matches, and open private conversations. Jac is not a wrapper;
Jac is the application.

## What we are showing

Our Phase 1.5 demo lets a visitor write or paste a free-form profile and compare
it with 100 varied fictional profiles. It processes the complete pool and
returns three ranked fictional people with source excerpts, text-similarity
scores, and grounded reasons to talk.

These fictional people cannot be contacted. Our earlier Phase 1 separately
proves private decisions, mutual consent, a private thread, messaging, and
third-user protection. The next release combines both parts for real people.

## A distributed computing system built in Jac

Personal computers contain unused computing power, but applications cannot use
them like a reliable cloud. Independent machines disconnect, fail, and cannot
automatically be trusted.

We built JacGrid in Jac to solve this. It divides an application job into tasks,
runs them on available computers inside restricted sandboxes, verifies results,
retries failed work, and combines the output.

We have validated JacGrid across multiple computers on a local network. It can
detect a lost worker, move its task, verify the result, and keep an audit trail.
Jack Sparrow is its first application, although Phase 1.5 can run on one server.

The longer-term model is that applications get distributed computing capacity
while people earn money by sharing spare capacity. Real payments and open
participation are not built yet; current receipts use simulated TESTUSD.

The name connects both ideas: Jack Sparrow moves between ships to reach his
destination. Here, computing work moves across a fleet of computers to help a
person reach theirs—someone worth meeting.

For the hackathon, Jack Sparrow will be shared through JacHammer, and the
JacGrid coordinator is also intended to run there.
