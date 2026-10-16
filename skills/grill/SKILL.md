---
name: grill
description: Interview the user relentlessly about a plan, decision, or idea until you reach shared understanding
when_to_use: >-
  When the user wants their thinking stress-tested rather than accepted. Trigger phrases:
  "grill me", "interrogate this", "poke holes in it", "challenge my assumptions", "pressure-
  test this decision".
argument-hint: "[topic]"
effort: xhigh
---

# Grill

Stress-test the user's thinking on `$ARGUMENTS`. If the user names no topic, ask what they want
grilled.

Interview the user relentlessly about every aspect of this until you reach a shared
understanding. Walk down each branch of the decision tree, resolving dependencies between
decisions one-by-one.

Every question takes the question shape that `rules/chat-vocabulary.md` defines. Read the shape
there. This skill does not restate it.

Ask one question per message. Never batch two into one call. The user answers the first, and the
second one disappears.

If you can find a *fact* by exploring the environment (filesystem, tools, etc.), look it up
rather than asking. The *decisions*, though, are the user's — put each one to them and wait
for their answer.

Do not act on it until the user confirms you have reached a shared understanding.

## What makes this work

- **Order by dependency.** Ask the question whose answer changes the most other answers first.
  When an answer invalidates something already decided, say so and revisit it rather than
  quietly building on a contradiction.
- **Recommend, always.** A recommendation is mandatory, not expected. Every question carries
  one, with the reason for it. A question without a recommendation is incomplete.
- **Look it up.** Anything discoverable from the filesystem, git, an API, or a tool is yours to
  find. Do not ask the user for a fact you could have read. That wastes a turn.
- **Show the consequence.** State what each option costs and what it forecloses. Options that
  all sound reasonable are not a real choice.
- **Surface what you got wrong.** When research contradicts a recommendation you already made,
  correct it plainly and move on.
- **Track the tree.** Keep a running map of settled items, open items, and items an open
  question blocks.
- **Stop when it converges.** When remaining questions are implementation details the user
  would rather see than specify, propose defaults and flag them as proposals. Summarize for
  confirmation.

## Close

Close with the convergence summary and nothing after it. State what you decided, what you
assume without asking, and what remains open. Then wait for explicit confirmation
before acting.
