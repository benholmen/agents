---
name: plan
description: Research, grill, and produce an implementation plan in a plan file
argument-hint: "[topic | research file | paths]"
---

# Plan

Produce an implementation plan grounded in research, shaped by interrogating the user.

Three gates: **scope**, **grilling**, **approval**. The output is exactly one artifact — a
plan file. It leads with the plan and keeps the research in an appendix. This skill writes no
schedule. `/implement` composes the slices into milestones when it starts.

`<state>` below is the state directory `rules/agent-orchestration.md` defines.

## Input

`$ARGUMENTS` may contain any of:

- A topic or question — plan from scratch
- A research file (`<state>/research/<slug>.md`, or its slug) — from a standalone `/research`
- File paths — read fully before anything else

With no arguments:

> **Deciding — what to plan**
>
> What should I plan? Give me a topic, a research file from `/research`, or relevant context.
>
> ⏸ waiting on you: name what to plan

That question opens a `Deciding` gate, so it carries the heading and the footer. It offers nothing
to rank, so it carries no context block and no recommendation. `rules/chat-vocabulary.md` states
all three.

## Gate A — Scope and investigation

Do a cheap first pass before you propose anything. Read mentioned files fully, resolve each
repository's container path, and skim enough to form a real proposal.

**Resolve the container with the one derivation `/worktree` states.** See
`skills/worktree/SKILL.md`, under `## Derive the container from any worktree`. Use it verbatim and
write no second copy. `git rev-parse --show-toplevel` is the wrong command here: it returns
`<container>/main` in a converted repository, and `/worktree cut` then refuses the container as a
plain clone.

**Critique roster:** `Critique:` defaults to `/critique`'s default roster, one Claude critic at
the session's model and one Codex critic. Where `codex` is absent, it falls back to the Claude
critic alone, and the gate says so. The user may change it to any roster `/critique` step 2
accepts. Write it to the plan's `### References`.

**Target repos:** infer, and show your evidence for each. Draw on the current repo and on the
repos a research file's target list names. Draw on repos implied by `file:line` references in
findings. Say what you excluded and why.

**Tree staleness:** run a real `git fetch` in each repo in scope. Report how far each tree sits
behind its default branch, as a number of commits. Report `0` for a current tree. A claim that
the tree is current is not a number, so it does not count.

**Investigation:** describe what you intend to look into, and the model and effort each area
needs. If the user supplied a research file, read it fully first. Scope the investigation to the
gaps, and do not re-derive what you already know.

**Decisions:** name each decision you expect to put to the user at gate B. A list of decisions
tells the user what the grilling costs. A count of questions does not, and the count ran 1.43×
low across twenty runs.

**Approve — /plan scope**

```
Before I investigate — confirm or adjust:

  Critique:     claude:<model>, codex   (one critic per runtime; change it)

  Repos in scope:
    <repo>  ─ <evidence>                    <N> commits behind <default>
    <repo>  ─ <evidence>                    <N> commits behind <default>

  Not included: <repo> (<why>)

  I plan to investigate (<N> parallel workers):
    1. <specific question>                  <model> · <effort>
    2. <specific question>                  <model> · <effort>

  Decisions I expect to put to you:
    1. <the decision, in a phrase>
    2. <the decision, in a phrase>

Accept this scope, or tell me which repo or question to add or cut.
```

⏸ waiting on you: accept the `/plan` scope, or name what to change

## Research phase

Run the confirmed investigation following `/research` step 2: one `research-worker` per area, at
the tier gate A confirmed, all spawned in one message. Wait for the completion notices, per
`rules/agent-orchestration.md`. Workers document what exists and return it as their final
message; you own the plan file.

**If the user supplied a standalone research file:** absorb its content into the plan under
`### Research` in the appendix. Then move the source into `<state>/archive/`. The move takes it
out of the active set without deleting it. Add anything new your investigation found.

## Gate B — Grill the user

Follow `/grill`. Ask one question at a time, and wait for the answer before you ask the next.
`rules/chat-vocabulary.md` gives the shape of a question, including the mandatory
recommendation. Point at that rule rather than restating it, and never batch two questions.

**The heading opens the gate once.** The first question carries `Deciding` for a question you
cannot answer, or `Approve` for a proposal you already formed. Every later question inside this
open gate carries no heading. A grilling asks many questions, and one heading each would stop the
heading staying rare.

**Every question carries the footer**, whether or not it carries a heading. Every question waits
for the user, and the footer is the only mark that says so.

The remaining questions may turn out to be details the user would rather see than specify. In
that case, propose defaults, flag them as proposals, and move to gate E.

## The census

Run the inbound-reference census before you write the plan. It is a required step, not a
thoroughness reminder. Every slice must declare every path it touches. The census finds the
paths you did not think of.

Take each file a slice changes, and each symbol it renames or removes. Search for three kinds of
inbound reference:

```
caller     every site that imports, calls, includes, or spawns the thing you change
test       every test that exercises it, by name or through its public entry point
standard   every rule, ADR, README, or skill whose text your change makes false
```

Record every path the search returns in that slice's `**Files**:` list. A hit in another
repository belongs to another slice, because a slice covers exactly one repository.

The third kind is the one that gets missed. A change to a rule falsifies the README table that
describes it. No import points from one to the other, so grep the prose as well as the code.

Nineteen of thirty sessions shipped an incomplete `**Files**:` list, and one run reported ten
affected waves of fourteen. The census now decides what ships in parallel, not only who edits
what. `/implement` composes milestones from slices, and file overlap between two milestones
forces them into sequence.

## Write the plan

Slug from `date +%Y-%m-%dt%H%M` plus a short topic.

**The `t` is lowercase, and that is load-bearing.** This slug builds a branch name, a worktree
path, and `COMPOSE_PROJECT_NAME`. Compose rejects an uppercase project name, so an uppercase slug
fails the first milestone's provisioning rather than the plan.

Write the document below to `<state>/plans/<slug>/plan.md`. Revise it in place with the Edit tool
at every round of feedback, so the file stays the record of what the user agreed.

```
# <Feature or task> Plan

**Repos**: `<name>` — <absolute container path>

One line per repo when more than one is in scope. The path is the container gate A derived, not
`<container>/main`.

## Overview
<the outcome we're after, why, and how we will know it was achieved>

## What We're NOT Doing
<explicit non-goals, to stop scope creep>

## Work item: <name>
**Files**: `path/one.ext`, `path/two.ext`

`path/one.ext` — <what changes and why>
`path/two.ext` — <what changes and why>

### Exit criterion
<the one end state, in a sentence>
**Proof**: `<the command that proves it>`
**Invariants**: <what must not change while the item reaches that state>

### Verification
#### Automated:
- [ ] <runnable command>

#### Manual:
- [ ] <what a human must check>

---

## Work item: <name>
**Files**: `path/three.ext`
**Constraint**: same-worker as <other item>

<same structure>

## Appendix

### Research
<absorbed and newly gathered findings — current state, architecture, each with `file:line`>

### References
- Research absorbed from: <the research file, if any — now in archive/>
- Critique roster: <one entry per critic, such as claude:opus, codex>
```

The plan leads and the evidence follows. One `**Repos**:` line carries the container path
`/implement` needs to cut each milestone's worktree. Each slice verifies itself. There is no
separate testing section, so unit, integration, and manual checks all sit under that slice's
`### Verification`.

**Every work item carries one exit criterion.** It names the end state a machine can check, the
command that proves it, and the invariants that must survive. `/implement` runs each milestone to
the criteria of the items it carries, and it asks the user nothing in between.
`skills/implement/SKILL.md` states that under `## The exit criterion`.

Write a command, never a description. `the tests pass` proves nothing, because nobody can run it.

One corpus attributed 40 of 109 escalations to plan ambiguity. The two most frequent self-imposed
pauses were decisions the plan left open. An exit criterion is what closes them.

**A work item is a slice.** A slice is narrow and vertical: one coherent change, in exactly one
repository, that stands on its own. It says what changes and why, never who runs it. Worker
count, order, and model belong to the schedule. That schedule rests on facts that exist only at
execution time, so `/implement` decides it.

Shape each slice so `/implement` can compose milestones from it:

```
  slice       one worker's unit of work. Narrow, vertical, one repository.
  milestone   a consumable chunk of a plan, sequenced in a DAG. May span
              repositories. The unit of delivery.
  wave        the concurrency schedule inside a milestone, from file overlap.
```

A plan declares slices and nothing above them. `/implement` groups slices into milestones,
orders the milestones, and schedules each milestone's waves. Do not group slices to suit a worker
count, and do not number them to imply sequence.

Rules the rest of the workflow depends on:

- **`**Files**:` must list every path the slice will touch.** The census above is how you get
  that list right. `/implement` computes milestone boundaries, worker grouping, and wave
  parallelism from these. A worker that writes an undeclared path deviates from its task. This is
  the one field nobody can infer later.
- **`**Constraint**:` is optional and has exactly two forms.** Use `same-worker as <item>` when
  two items must not drift apart. Two examples: a shared clause that has to stay byte-identical,
  and a rename and its call sites. Use `after <item>` for a genuine dependency, such as
  documenting a result. Anything else is scheduling and does not belong here.
- **`after` also feeds the milestone DAG.** `/implement` aggregates every `after` in the plan
  onto the milestones that hold the two slices. That aggregate becomes the order the milestones
  ship in, so an `after` you add for convenience delays delivery.
- **Split any slice that spans two repos.** Each slice belongs to exactly one repo in the
  `**Repos**:` list. A slice that straddles two repositories joins neither milestone cleanly.

## Gate E — Approval and fork

Optionally run `/critique <the plan file>` first, with the gate A `Critique:` roster, and fold in
what survives.

Present the design — the slices, their file scopes, and any constraint that ties two together:

**Approve — `plan/<slug>`**

```
Plan: <state>/plans/<slug>/plan.md

  <name>            rules/*.md
  <name>            skills/*.md        same-worker as <name>
  <name>            README.md          after everything above

  Not included: <thing> (<why>)

Approve the plan?
```

⏸ waiting on you: approve `plan/<slug>`, or name the slice to change

**No milestones, no waves, no worker count, no models here.** `/implement` composes and
schedules those at decomposition, against facts that are current then, and gates them
separately. A plan that fixes the schedule forces an approval on evidence nobody has yet.

Iterate on feedback and update the plan file each time. **Do not proceed past this gate without
explicit approval.**

Once the user approves:

**Deciding — what happens to `plan/<slug>`**

```
Plan approved. What next?

  1. Implement now   — I'll start /implement; you'll next see its roster gate
  2. Leave active    — the plan stays in <state>/plans/; run /implement <slug> whenever
```

I recommend <one of the two>, because <the ground>.

⏸ waiting on you: pick one of the two for `plan/<slug>`

`rules/chat-vocabulary.md` makes that line mandatory. This `Deciding` presents two options you
did not rank, so it never counts as its own recommendation.

- **Implement now** — call `/implement <slug>`, with the slug as the first argument. Print no
  command for the user to type. The next stop is that skill's roster gate.
- **Leave active** — do nothing. The plan stays in `<state>/plans/<slug>/`.

**Do not ask for the critique roster here.** Gate A already settled it. One run holds one roster,
and two skills asking for it turns one stop into two.

## Guidelines

- **Be skeptical.** Question vague requirements and verify corrections against the code rather
  than accepting them.
- **Read completely.** No `limit`/`offset` on context files.
- **Be concrete.** Every claim about current behavior carries a `file:line`.
- **No open questions in the plan.** Research it or ask. An unresolved question in an approved
  plan becomes a deviation during implementation.
- **Separate automated from manual verification.** `/implement` treats them differently.
- **`plan.md` holds the plan; `state.yml` holds the schedule.** `/implement` writes the second.
  Never duplicate the plan into it.
