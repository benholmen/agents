---
name: research
description: Investigate a codebase with parallel agents and write the findings to a research file
when_to_use: >-
  When the user wants to understand how something works across a codebase and wants the
  findings written down rather than explained in chat. Trigger phrases: "how does X work",
  "map the Y subsystem", "trace this flow". Read-only.
argument-hint: "[question or area]"
---

# Research

Investigate a codebase and produce a factual map of what exists. This skill runs standalone, and
it is also the research phase inside `/plan`.

## Your only job is to document what exists

- Do NOT suggest improvements, critique the implementation, or propose future work
- Describe what exists, where it lives, how it works, and how the pieces connect
- Your output is a description, not a review

If the user invokes it with no arguments:

> **Deciding — what to research**
>
> What would you like me to research? Give me a question or an area of the codebase.
>
> ⏸ waiting on you: name a question or an area of the codebase

That question opens a `Deciding` gate, so it carries the heading and the footer. It offers nothing
to rank, so it carries no context block and no recommendation. `rules/chat-vocabulary.md` states
all three.

## Step 1 — Establish scope, and confirm it

Do one cheap first pass before you spawn any worker. Read any files the user mentioned fully —
no limit/offset. Resolve each repository's container path, and skim enough structure to form a
proposal. Resolve the container with the derivation in `skills/worktree/SKILL.md`, under
`## Derive the container from any worktree`.

Check for prior work before you investigate. Search `<state>/research/` for the topic's keywords,
where `<state>` is the state directory `rules/agent-orchestration.md` defines. If an existing
research file covers this, read it and extend it. Do not duplicate it.

Then present the gate, in the shape `rules/chat-vocabulary.md` defines:

**Approve — /research scope**

```
  Repos in scope:
    <repo>  ─ <evidence: current repo / N code refs / named in request>

  Not included: <area> (<why>)

  I plan to investigate (<N> parallel workers):
    1. <specific question>                          <model> · <effort>
    2. <specific question>                          <model> · <effort>
```

Accept this scope, or tell me which area to add or cut.

⏸ waiting on you: accept the `/research` scope, or name what to change

Scale the investigation to the question. A narrow lookup deserves one worker; mapping a
subsystem deserves several. State what you are *not* looking at, and why. A wrong omission is
easier to catch than a wrong inclusion.

Tier by area: tracing one call path is not the same job as mapping a subsystem's conventions.

## Step 2 — Investigate

Fan out per `rules/agent-orchestration.md`, with one `research-worker` per confirmed area.

Build the slug first — `date +%Y-%m-%dt%H%M` plus a short topic, e.g.
`2026-04-05t1423-jwt-auth`. Step 4 reuses it.

Spawn every area in one message, so they run concurrently:

```
Agent(subagent_type="research-worker", description="research <area-slug>",
      model=<the tier this area needs>, effort=<the tier this area needs>,
      prompt=<the brief>)
```

A research worker is a read-only worker. Its definition grants `Read`, `Grep`, and `Glob` alone,
so it cannot change the tree it must describe. Its final message is its findings.

Fill the brief's four sections:

```
  ## Objective      the one specific question this worker owns
  ## Boundaries     read only inside <absolute repo path>, or name each repo when several are
                    in scope
  ## Tool guidance  where to start reading, and anything step 1 already established
  ## Output format  findings as factual bullets, each with an inline `file:line`; the repo
                    for each finding when more than one is in scope; `ESCALATION:` first when
                    the question went unanswered
```

Wait for every worker's completion notice, per `rules/agent-orchestration.md`. Never poll.

## Step 3 — Synthesize

When the last notice arrives, read every worker's findings. Connect findings across components,
and keep every `file:line` reference. Resolve a contradiction by reading the code again rather
than by picking one report.

A worker that escalated left its question unanswered. Answer it yourself where a few reads
settle it. Otherwise record it under `## Open Questions`.

## Step 4 — Write the file

Reuse the slug built in step 2.

**Standalone:** write `<state>/research/<slug>.md`, in the shape below.

**Called from `/plan`:** write no file. Return the same content for `/plan` to place under
`### Research` in the plan's `## Appendix`.

```
# Research: <topic>

**Date**: <YYYY-MM-DD>
**Repos**: `<name>` — <absolute path>

## Summary
<the answer to the question asked>

## Current State
- <finding> (`path/to/file.ext:123`)
- <how it connects to the next thing> (`other/file.ext:45-67`)

## Architecture
<patterns, conventions, and design actually found — not recommended>

## Open Questions
<what the code could not answer; omit if none>
```

Every Current State bullet carries an inline `file:line` — that is the only place references
live. Group by repo when more than one is in scope.

## Step 5 — Report

Report the action, the location, and the decision needed. Do not report the findings — the user
reads the file.

```
Researched <topic> — <N> areas, <N> workers.

  File: <state>/research/<slug>.md

Next: /plan <the file> to plan from it, or /critique <the file> to challenge it.
```

## Follow-ups

Extend the same file rather than creating another. Edit a section in place, or add new material
under its heading. Add a dated section at the end for a later investigation.

## Notes

- Read mentioned files fully before spawning anything
- Read-only: no branches, no commits, no code changes
- The file must stand alone. `/plan` may read it in a session that has none of this context
