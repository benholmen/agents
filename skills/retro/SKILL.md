---
name: retro
description: Analyse past sessions for recurring failures and hand the findings to /plan
when_to_use: >-
  When the user wants to know what keeps going wrong across sessions rather than inside one.
  Trigger phrases: "run a retro", "what keeps going wrong", "analyse my transcripts", "why do
  these runs keep failing". Read-only.
argument-hint: "[area of concern]"
---

# Retro

Analyse past sessions and hand what you find to `/plan`. This skill reads the transcript corpus
and changes nothing.

Open discovery, and no fixed metric set. The user names an area of concern, or you propose one.
One Solo agent then investigates each area.

With no arguments:

> **Deciding — what the retro looks at**
>
> What should the retro look at? Name an area of concern, or ask me to propose some.
>
> ⏸ waiting on you: name an area of concern, or ask for a proposal

That question opens a `Deciding` gate, so it carries the heading and the footer. It offers nothing
to rank, so it carries no context block and no recommendation. `rules/chat-vocabulary.md` states
all three.

## This skill never edits a skill or a rule

Every finding goes to `/plan`, and `/plan` gates on the user's approval. A change to a skill
therefore stays on the one path the user already reviews. No step below edits another file, and
never add one that does.

## Runs are not comparable

Say this in every report. Each run picks its own areas, so no count here carries to the next run.
A number from this run and a number from the last one measure different things.

Present no trend line, and never call a count better or worse than a previous run's.

A fixed metric set would make runs comparable. It would also fix what a run can find, which
defeats open discovery. Declined on purpose.

## The corpus

Claude Code writes one JSONL file per session:

```
~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
```

The directory name encodes a working directory, and each `/` in that path becomes a `-`. One
session is one file, and the file name is the session id.

## Step 1 — State the corpus scope, and confirm it

**Read the previous run's scope first.** Run `scratchpad_list(tags=["retro"])` and read the
newest pad's `## Corpus scope` section. It names what an earlier run examined, so this run can
extend that rather than repeat it.

Then count the corpus cheaply. Read no transcript yet:

```bash
ls ~/.claude/projects/
ls -lt ~/.claude/projects/<dir>/*.jsonl | head
```

Determine the Solo project with `list_projects`, then use **whichever project is currently
selected**. State it in the gate.

Propose areas only when the user named none. An area is a question about behavior across
sessions, not a metric. `Which escalations never reached the user?` is an area.
`Count the escalations` is a metric.

Then present the gate, in the shape `rules/chat-vocabulary.md` defines:

**Approve — /retro corpus scope**

```
  Solo project: <name>  (<path>)

  Corpus scope:
    projects   <dir>  ─ <N> sessions
    dates      <YYYY-MM-DD> to <YYYY-MM-DD>
    size       <N> files, <total bytes>

  Previous retro: retro/<slug>, which covered <dates>   (or "none")

  Areas of concern (<N> parallel Solo agents):
    1. <specific question>
    2. <specific question>

  Not included: <area> (<why>)
```

Accept this corpus scope, or tell me which area to add or cut.

⏸ waiting on you: accept the `/retro` corpus scope, or name what to change

## Step 2 — Investigate

Fan out with Solo agents, per `solo-agent-orchestration`. Never use the host runtime's own
sub-agent mechanism.

Build the slug first — `date +%Y-%m-%dt%H%M` plus a short topic, such as
`2026-08-24t0930-escalations`. Workers name their pads under it, and step 3 reuses it.

Resolve the runtime once with `list_agent_tools`, and use the host runtime, per
`solo-agent-orchestration`. Read `references/runtime-<tool_type>.md` for the arguments it needs.
Never write a launch argument from memory. Call `whoami` and keep the returned `process_id` —
every worker needs it to signal back.

```
spawn_agent(agent_tool_id=<id>, name="retro-<area-slug>", extra_args=[
  <the model and effort arguments, at the tier this area needs>,
  <the auto-approval and immutable-target arguments from the adapter>])
  → process_id, agent_instructions
```

A read-only assignment is no reason to drop auto-approval, and never a reason to raise it to a
bypass mode.

A retro worker is an immutable-target worker. It reads the corpus and writes only its own
scratchpad, so it cannot edit the skills it reports on. `solo-agent-orchestration` gives that
posture, and the adapter gives the arguments. Read what the adapter says its runtime cannot bound.

Write the worker's brief to a scratchpad, per `solo-agent-orchestration`'s **The worker brief
pad**. Fill its six sections:

```
  ## Solo context   agent_instructions, pasted verbatim
  ## Objective      the one specific question this worker owns, plus the confirmed corpus scope
                    (directories, date range, session list)
  ## Boundaries     read-only against the corpus; never edit a skill, a rule, or any other file
                    in any repository; no todos, no KV; when stuck, record what you found and stop
  ## Tool guidance  the corpus mechanics below, plus: work from the extracted event log, never
                    from a grep over raw JSONL; report every count with the command that produced
                    it; quote the session id and the entry's `.timestamp` for every claim; report
                    what the corpus shows, never the fix — `/plan` owns that
  ## Output format  write findings to scratchpad "retro/<slug>/<area-slug>" — the orchestrator
                    owns the retro pad
  ## Completion     timer_set per `solo-agent-orchestration`'s **Workers signal completion**,
                    delivery_process_id=<orchestrator process_id>
```

### Corpus mechanics — paste this into the brief's Tool guidance section

Each transcript is JSONL, and one line is one entry. The fields you need are `.type`,
`.message.content`, and `.timestamp`.

`.type` holds `user`, `assistant`, or a metadata kind such as `attachment`, `mode`, or
`ai-title`. Filter to the kinds your area needs, and ignore the rest.

A `user` entry whose content holds a `tool_result` block is a tool return, not a human turn.
One measured session held 71 `user` entries. 70 of them were tool returns, and the user typed
1. Count human turns only after you exclude every `tool_result` block. Skip that step and the
count is wrong by two orders of magnitude.

Never grep the raw JSONL for a tool name. Every turn carries the rule text injected into it,
so a tool name matches that prose rather than a call. In one session
`grep -c 'spawn_agent'` returned 4 against 0 real calls, and `grep -c 'lock_acquire'`
returned 11 against 4. `grep -c` also counts lines rather than matches, and one JSONL line
holds a whole turn, so it errs in both directions.

Extract one event log with `jq` first, then work from that file:

    jq -r 'select(.type=="assistant") | .message.content[]?
           | select(.type=="tool_use") | [.id, .name] | @tsv' "$F" > calls.tsv

    jq -r 'select(.type=="user") | .message.content[]?
           | select(.type=="tool_result")
           | [.tool_use_id, (.is_error // false)] | @tsv' "$F" > returns.tsv

Pair a call to its return on `tool_use.id` and `tool_result.tool_use_id`. The `is_error` field
marks a call that failed.

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
  body="Retro guard fired. A worker that never signalled is a failure to investigate,
        not a completion. Procedure: scratchpad_read(scratchpad_id=<guard pad id>)")
  → timer_id
```

Keep the returned `timer_id`. When the last area signals, `timer_cancel(timer_id=<id>)` before
you synthesize.

## Step 3 — Synthesize and write the pad

On wake, read every worker's scratchpad. Connect findings across areas, and keep every session id
and command. Re-run a command yourself when two workers disagree on a count.

Then `close_process` each worker and archive its per-area scratchpad.

Reuse the slug built in step 2:

```
scratchpad_write(
  name="retro/<slug>",
  tags=["retro"],
  content=<document below>
)
```

**Keep this pad, and never archive it.** The next run reads its `## Corpus scope` section to
learn what this run already examined. That section is the only record of the scope.

```
# Retro: <topic>

**Date**: <YYYY-MM-DD>

## Corpus scope
projects   <dir>
dates      <YYYY-MM-DD> to <YYYY-MM-DD>
sessions   <N>
areas      <the confirmed areas>

Runs of this skill are not comparable. Each run picks its own areas, so no count
below carries to another run.

## Findings
- <finding> — <session id>, <timestamp>, <the command that measured it>

## Proposed changes
- <what to change, and the file it belongs in>
```

Every finding carries its session id and the command behind its number. Drop a count with no
command, because nobody can reproduce it.

## Step 4 — Hand to /plan

Report the pad, then hand the proposed changes to `/plan`:

```
Retro over <N> sessions — <N> areas, <N> Solo agents.

  Pad: retro/<slug>  (id <n>)

  Runs are not comparable — this run's counts stand alone.

Next: /plan retro/<slug> turns the proposed changes into slices.
```

`/plan` owns every change from here. It grills, it censuses the inbound references, and it gates
on approval. That gate is why this skill edits nothing itself.

## Notes

- Read-only against the corpus: no edits, in any repository
- Model-invocable, because it has no side effect to gate
- No todos — a retro precedes tracked work
- The pad must stand alone. `/plan` may read it in a session with none of this context
