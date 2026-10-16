---
name: research
description: Investigate a codebase with parallel agents and write the findings to a Solo scratchpad
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

Determine the Solo project with `list_projects`, then use **whichever project is currently
selected**. Do not match paths or assume a name. Confirm it in the gate, so the user catches a
wrong scope before you write anything.

Check for prior work before you investigate: `scratchpad_list(query="<topic keywords>")`. If an
existing research pad covers this, read it and extend it. Do not duplicate it.

Then present the gate, in the shape `rules/chat-vocabulary.md` defines:

**Approve — /research scope**

```
  Solo project: <name>  (<path>)

  Repos in scope:
    <repo>  ─ <evidence: current repo / N code refs / named in request>

  Not included: <area> (<why>)

  I plan to investigate (<N> parallel Solo agents):
    1. <specific question>
    2. <specific question>
```

Accept this scope, or tell me which area to add or cut.

⏸ waiting on you: accept the `/research` scope, or name what to change

Scale the investigation to the question. A narrow lookup deserves one agent; mapping a
subsystem deserves several. State what you are *not* looking at, and why. A wrong omission is
easier to catch than a wrong inclusion.

## Step 2 — Investigate

Fan out with Solo agents, per `solo-agent-orchestration`. Never use the host runtime's own
sub-agent mechanism.

Build the slug first — `date +%Y-%m-%dt%H%M` plus a short topic, e.g.
`2026-04-05t1423-jwt-auth`. Workers name their pads under it, and step 4 reuses it.

Resolve the runtime once with `list_agent_tools`, and use the host runtime, per
`solo-agent-orchestration`. Call `whoami` and keep the returned `process_id` — every worker needs it to signal back.
Then, per confirmed area:

```
spawn_agent(agent_tool_id=<id>, name="research-<area-slug>", extra_args=[
  <the model and effort arguments, at the tier this area needs>,
  <the auto-approval and immutable-target arguments from the adapter>])
  → process_id, agent_instructions
```

`list_agent_tools` returns a `tool_type` for each runtime. Read `references/runtime-<tool_type>.md` and
use the arguments it lists. Never write a launch argument from memory: a runtime renames its
flags between releases, and the adapter is the only current record.

A read-only assignment is not a reason to drop auto-approval, and never a reason to raise it to
a bypass mode.

A research worker is an immutable-target worker. It reads the repository and writes only its own
scratchpad, so it cannot mutate the tree it must describe. `solo-agent-orchestration` gives that
posture, and the adapter gives the arguments. Read what the adapter says its runtime cannot bound.

Tier by area: tracing one call path is not the same job as mapping a subsystem's conventions.

Write the worker's brief to a scratchpad, per `solo-agent-orchestration`'s **The worker brief
pad**. Fill its six sections:

```
  ## Solo context   agent_instructions, pasted verbatim
  ## Objective      the one specific question this worker owns; document what exists, not what
                    should be — no improvements, no critique, no proposed work
  ## Boundaries     read-only: no edits, no branches, no commits, no other git write command;
                    read only inside <absolute repo path>; no todos, no KV; when stuck, record
                    what you found and stop
  ## Tool guidance  read the files you need fully, no limit or offset; report file paths, line
                    numbers, and factual descriptions of how the pieces connect; note which repo
                    each finding belongs to when more than one is in scope
  ## Output format  write findings to scratchpad "research/<slug>/<area-slug>" — the orchestrator
                    owns the research pad
  ## Completion     timer_set per `solo-agent-orchestration`'s **Workers signal completion**,
                    delivery_process_id=<orchestrator process_id>
```

Send only the pointer, per **The pointer shape** under **The PTY ceiling**:

```
send_input(process_id, input=<pointer to the brief pad, naming its id>)
```

Workers signal when they finish. Before arming the guard, write a guard pad per
`solo-agent-orchestration`'s **The guard pad**. It carries the watch list — process id, name,
area, report pad id — and the branches. Arm the timer only once the workers produce output.
`implement-waves.md`'s **The join** gives the reason: an entirely idle watch list returns
`already_satisfied` and creates no timer. Check the return value for that case, then arm one
idle timer per run as the dead-worker fallback only:

```
timer_fire_when_idle_all(processes=[<pids>], max_wait_ms=<generous guard>,
  body="Research guard fired. A worker that never signalled is a failure to investigate,
        not a completion. Procedure: scratchpad_read(scratchpad_id=<guard pad id>)")
  → timer_id
```

Keep the returned `timer_id`. When the last area signals, `timer_cancel(timer_id=<id>)` before
you synthesize. A guard you leave armed fires later and arrives as an instruction about areas
that finished long ago.

Workers write only their own findings pad. You own the research pad.

## Step 3 — Synthesize

On wake, read every worker's scratchpad. Connect findings across components, and keep every
`file:line` reference. Resolve a contradiction by reading the code again rather than by picking
one report.

Then `close_process` each worker and archive its per-area scratchpad — the synthesized pad
replaces them.

## Step 4 — Write the pad

Reuse the slug built in step 2.

**Standalone:**

```
scratchpad_write(
  name="research/<slug>",
  tags=["research", "project:<repo>"],
  content=<document below>
)
```

One `project:<repo>` tag per repo in scope. Record the returned `scratchpad_id`.

**Called from `/plan`:** do not create a pad. Return the same content for `/plan` to place
under `### Research` in the plan pad's `## Appendix`.

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
reads the pad.

```
Researched <topic> — <N> areas, <N> Solo agents.

  Pad: research/<slug>  (id <n>)

Next: /plan research/<slug> to plan from it, or /critique research/<slug> to challenge it.
```

## Follow-ups

Extend the same pad rather than creating another:

- New material under an existing heading → `scratchpad_append_section`
- A section replacement → `scratchpad_edit` with the target object `solo-agent-orchestration`'s
  **Locks and reports** section defines, and the current `expected_revision`. Any other shape
  fails the call outright, so the edit never reaches the pad
- A dated addition at the end → `scratchpad_append`

On a revision mismatch, re-read and retry — something else touched the pad.

## Notes

- Read mentioned files fully before spawning anything
- Read-only: no branches, no commits, no code changes
- No todos — research precedes tracked work
- The pad must stand alone. `/plan` may read it in a session that has none of this context
