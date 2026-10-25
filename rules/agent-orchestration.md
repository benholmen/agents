---
description: Fan out with the host's native subagents, each at the model and effort its job needs. The host's completion notice is the join, and run state lives in files
---

# Agent orchestration

When you delegate work to a parallel worker, spawn it with the host's own subagent mechanism. On
Claude, that is the `Agent` tool with one of the agent definitions this repository installs. A
runtime other than the host joins a run only as a headless critic.

## Default policy

- **Default:** Every worker is a native subagent of the host. It runs in the background, and its
  model and effort are set on the call.
- **Definitions:** Use the agent definition that matches the worker's class. `research-worker`,
  `critique-worker`, and `refute-worker` read and never write. `implement-worker` edits its
  declared paths and cannot run a git write.
- **Other runtimes:** A critic on another runtime runs as a headless command, per
  `references/runtime-<name>.md`. No other worker leaves the host.
- **Scope:** This rule governs delegation. It applies to a fan-out from a skill, and to one from an
  explicit request such as "check these five services in parallel". You do not fan out when you
  read a few files yourself.

## The shape

1. Pick the agent definition for the worker's class. See **Worker classes**.
2. Choose the model and the effort for the job. See **Match the worker to the job**.
3. Write the brief into the `Agent` prompt. See **The brief**.
4. Spawn every worker of one wave in one message, so they run concurrently:
   ```
   Agent(subagent_type=<definition>, description="<role> <slug>", model=<model>,
         effort=<effort>, prompt=<brief>)
   ```
   Keep the agent ID each spawn returns. `SendMessage` and `TaskStop` address a worker by it.
5. Wait for the completion notices. Each worker's notice arrives as its own automated turn.
   Never poll, sleep, or ask a worker for its status while it runs.
6. On the last notice, read the reports. See **Reports**.

**Never spawn a fork as a worker.** A fork inherits this conversation, including the reasoning
behind the work. A critic that already knows why the code is good is no longer a critic. A
research worker that inherits your guess confirms it. A fresh subagent sees only its brief.

## Completion

**The host tells you when a worker finishes, and only the notice counts.** A worker that reasons
at length emits nothing for minutes, so silence says nothing about whether it finished.

**A failed worker is a failure to investigate, not a completion.** Its notice marks it failed,
and it carries the error and the worker's last output. Read that output, then respawn once with
the same brief, or escalate.

**`maxTurns` bounds a worker that loops.** Each agent definition sets one. At the limit, the
worker returns its output marked partial. Resume it with `SendMessage` when the partial output
shows it was close, or escalate.

**Correct a running worker with `SendMessage`.** A worker treats a message from you as task
direction, including a mid-task correction. The same call resumes a finished worker with its
context intact. An escalated worker continues that way once the user decides.

## The brief

The brief is the whole of a worker's context. The worker sees no part of this conversation. Write
four sections, in this order:

```
  ## Objective       the one job, or the path of the task spec that states it
  ## Boundaries      the working directory (absolute), the declared paths, the scratch
                     directory, and what the worker must not touch
  ## Tool guidance   what to read first, the prior waves, and any convention the job needs
  ## Output format   the shape of the final message, and the escalation marker
```

**The agent definition carries what every worker of its class shares.** That covers what it must
not touch, and what to do when stuck. Do not restate it in the brief.

**A worker inherits the rules.** A Claude subagent loads `~/.claude/rules/` the same way this
session does. Never restate a rule in a brief. State the job, and the constraints specific to it.

## Match the worker to the job

Set the model and the effort on every call. A worker does not inherit them from the session. A
mechanical edit against precise line references is one job. A rewrite that must preserve a
behavioral contract is another. The two should not cost the same.

```
  model    fable, opus, sonnet, or haiku
  effort   low, medium, high, xhigh, max
```

**Run the orchestrating session in auto mode, never in a bypass mode.** A background worker takes
the session's mode whenever the session runs in `auto`, `acceptEdits`, or `bypassPermissions`,
whatever its definition says. Auto mode lets a worker work through ordinary steps, and a reviewer
still sees the requests that matter. A bypass mode removes that review from every worker at once.

**A worker's permission prompt reaches you.** A background worker that needs approval surfaces
the prompt in this session and names itself. A grant that lasts beyond one call applies to the
whole session, so grant for one call where you can.

## Worker classes

Two classes exist. Decide the class first.

**The read-only worker.** Every research worker, critic, and refuter is one. Its definition
grants `Read`, `Grep`, and `Glob` alone, so it cannot write a file or run a command. Its final
message is its report. Put anything it must read, such as a diff, in a file it can reach, and
name the path in the brief.

**The editing worker.** Every `/implement` task worker is one. Its definition grants `Edit`,
`Write`, and `Bash`. A `PreToolUse` hook blocks every git subcommand outside a read-only list. Its
working directory is its milestone worktree. The brief names that path, because a subagent starts
in this session's directory.

**The hook is a backstop, not a sandbox.** It reads the command line, so `git add` behind a
variable or inside a script passes. Workers also share this session's sandbox, so nothing bounds
an editing worker's writes to its declared paths. The orchestrator checks that bound at the join
instead. Every path `git status --porcelain` lists must belong to a declared path of the wave. A
path outside them is a deviation.

**The hook loads only from a trusted definition.** `~/.claude/agents/` is trusted. A copy in an
untrusted project's `.claude/agents/` loses its frontmatter hooks, and nothing tells the worker.
The skipped hook appears in the debug log alone. Measured on Claude Code 2.1.310.

## Reports

**Every worker returns its report as its final message.** Claude Code refuses a subagent's
attempt to write a report file, and it tells the subagent to return the content instead.
Measured on 2.1.310.

**An editing worker's report opens with one status line:** `CLEAN`, or
`ESCALATION: <what it found>`. Read every first line before you read any report in full.

**Persist what must outlive this session.** Write an escalated report to
`<state>/plans/<slug>/reports/<milestone>/<task>.md`, because nothing else recreates an
escalation record after a restart. A clean report needs no file, because its commit and
`state.yml` record it. A read-only worker's report becomes the research file or the critique
ledger. The host also keeps every subagent's transcript.

## Headless critics on other runtimes

`/critique` uses more than one model, because each model misses different defects. Its default
roster is one Claude critic and one Codex critic. A critic on the host is a `critique-worker`
subagent with its own `model`. A critic on another runtime runs
as a headless command, with a read-only sandbox and structured output.
`references/runtime-codex.md` carries the Codex command. `references/runtime-claude.md` carries
the Claude command, for a run that Codex hosts.

**Run a headless critic with the Bash tool, in the background.** The host notifies you when the
command exits, exactly as it notifies you for a subagent. Wrap it in `timeout`, which takes the
place of `maxTurns`.

**Never write a launch argument from memory.** Each runtime renames its flags between releases.
Read the adapter, which records the version it was measured against.

**Escalate a launch failure. Never loosen a flag.** When a headless critic fails, read its
adapter, correct the arguments, and retry once. When the second attempt fails, drop that critic
and say so in the ledger. Never reach for a bypass flag to make a launch succeed.

## The state directory

All run state lives in files, in one directory outside every repository:

```
~/.agents/work/
  research/<slug>.md                    a standalone /research result
  plans/<slug>/plan.md                  the plan
  plans/<slug>/state.yml                the schedule and its progress
  plans/<slug>/tasks/<m>-<task>.md      one task spec
  plans/<slug>/reports/<m>/<task>.md    one escalated worker's report
  plans/<slug>/critique/<segment>/      critique inputs and headless critic outputs
  plans/<slug>/scratch/<m>-<task>/      one editing worker's scratch directory
  critique/<slug>/<segment>/            a standalone /critique's inputs and outputs
  archive/                              finished plans and absorbed research
```

`<state>` in any skill means `~/.agents/work`. Create a directory before a step writes into it.

**The orchestrator owns `state.yml`, and no worker writes it.** One writer keeps it consistent.
Change one key at a time with the Edit tool.

**A slug is lowercase.** Build it from `date +%Y-%m-%dt%H%M` plus a short topic. It builds a
branch name, a worktree path, and `COMPOSE_PROJECT_NAME`, and Compose rejects an uppercase
project name.

**Archive rather than delete.** Move a finished plan's directory into `archive/` whole. It stays
readable and searchable, and it no longer claims its branches.

## One worktree per milestone

A worker never shares a working tree with the user unless the user chose that. `/implement`
resolves one workspace mode per repository, and its roster gate names each one:

```
  container   a milestone worktree inside a converted repository
  checkout    the user's own checkout, on the milestone's feature branch
  main        the user's own checkout, committing on the default branch
```

`skills/implement/SKILL.md` carries the table that picks a mode when the user names none: a
converted repository takes `container`, and a plain clone takes `checkout`. `container` cuts one
worktree per milestone and per repository, from a bare-plus-worktrees layout, at these paths:

```
  container          <the repository's own path>                 at whatever depth it sits
  bare repo          <container>/.git                            `git rev-parse --is-bare-repository` returns true
  stable             <container>/main                            the user's worktree, never removed
  worktree           <container>/<plan-slug>-<milestone-slug>    one plan's worktrees sort together
  branch             <type>/<plan-slug>-<milestone-slug>         the plan slug keeps two plans off one branch
  create             test the branch and the path, then cut:
                       git worktree add <worktree> -b <branch> <base>   no such branch yet
                       git worktree add <worktree> <branch>             the branch already exists
                       reuse <worktree>, cut nothing                    the path already holds <branch>
                     base = origin/HEAD, or the predecessor milestone's branch when stacked
  record             state.yml: milestones.<m>.repos.<repo>.branch and .worktree
  remove             at milestone close, after a successful push
  sweep              git worktree prune at run close
```

The record carries the repository, because one milestone cuts one worktree per repository.
Without it the second cut overwrites the first, and teardown then leaks a worktree with its stack
still running.

**Test the branch and the path before you cut.** `git worktree add -b` fails outright when the
branch already exists. `git worktree add` fails the same way when another worktree already holds
the path. Run both tests, because a stopped run can leave either one behind.

**The branch test has three cases, and the plans' `state.yml` files tell them apart.**

- **A resume.** This plan's `state.yml` already names this branch. An earlier pass cut it and
  stopped, so re-cut onto it. Pass no `-b`: `git worktree add <worktree> <branch>`.
- **A closed plan's leftover.** No `state.yml` under `<state>/plans/` names the branch.
  `gh pr list --head <branch> --state merged` returns a merged PR, or the remote no longer
  carries the ref. That plan finished, and its directory moved to `archive/`. Delete the branch
  and cut fresh. `rules/pr-first-contributions.md` carries this test under
  `## Branch staleness check`.
- **A collision.** Another plan's `state.yml` names the branch, or none does and no merged PR
  explains it. Rename this plan's milestone, and escalate. Renaming the other plan's branch breaks
  its open PR.

**The branch carries the plan slug because teardown outlives the plan.** Teardown keeps the
branch, and the close step archives the plan's directory. Drop the prefix, and a second plan that
reuses a milestone slug finds a branch no active plan names. It then escalates over a PR that
merged and closed. `/implement` labels milestones `m1`, `m2`, and `m3`, so that is the common case
rather than the rare one.

**Test the recorded worktree path too.** Where the path exists and holds this milestone's branch,
reuse it and cut nothing. Where it holds anything else, stop and report both paths. A run that
stopped before its push gate leaves its worktree standing on unpushed commits, so a resume finds
the path already taken, and `git worktree add` exits 128 there.

**Test the layout before you cut anything.** A plain clone has no bare layout, so `/worktree`
refuses it and prints the conversion command rather than a worktree path. `/implement` sends a
plain clone to `checkout` before it gets that far.

The worktree is disposable once the push succeeds, because the branch then lives on the remote.
Remove it at milestone close.

**Why a worktree.** The user sits on a branch in their own tree. A worker that cannot take that
branch cannot trample the user's working state. Git refuses to check out one branch in two
worktrees, so the guarantee is structural rather than requested.

**The safety comes from the worktree, not from the bare repository.** A plain clone that adds
worktrees beside it would earn the same guarantee. This standard still requires the bare layout,
for symmetry and grouping: every tree is a peer, one container holds them all, and nothing nests
inside the user's checkout. A worktree nested in a checkout shows up in everything that walks
that checkout, from file watchers to a Compose bind mount of `./`.

**`checkout` and `main` give that guarantee up, by the user's choice.** The run works in the
user's own tree, so the tree must start clean, and the user stays off it until the run closes.
The test for a branch applies there unchanged.

## On Codex

Codex runs these skills with its own subagents, and the parent waits for every child it spawned
before it returns. Three things differ from Claude, and the roster gate discloses each one:

- **No agent definitions install for Codex.** Ask for the model and the reasoning effort in the
  spawn request, and carry the definition's text in the brief.
- **A subagent takes the parent's sandbox and approval policy.** A read-only worker is read-only
  by request alone.
- **No per-worker git denial exists.** Two editing workers that share a tree can cross-commit each
  other's work, silently. Give each one its own tree, or accept the risk knowingly and say so.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| A fork as a worker | It inherits the reasoning a critic must not see, and the guess a researcher must not confirm |
| Polling, sleeping, or asking a worker for status | The notice arrives on its own, and a thinking worker looks idle |
| Treating a failed notice as a completion | The worker never finished, and its last output says why |
| Every worker at the session's model and effort | A one-line edit and a contract-preserving rewrite are not the same job |
| A brief that leans on this conversation | The worker sees only its brief |
| A brief that restates a rule | The worker already loaded the rules |
| The orchestrating session in a bypass mode | Every background worker inherits it, and no reviewer sees anything |
| A worker in the user's tree that the user did not choose | The worker edits the tree the user sits in, and their working state is collateral |
| Treating the git hook as a sandbox | A variable or a script hides the command from it |
| Committing a wave without the declared-path check | An undeclared write rides into a task's commit |
| A worker writing `state.yml` | Two writers make one file inconsistent |
| Loosening a flag after a failed headless launch | The retry loop reaches a bypass flag instead of escalating |
| Cutting a milestone branch with `-b` and no existence test | A resumed run fails outright, because teardown left the branch behind |
| Cutting onto a recorded worktree path with no existence test | A stopped run leaves the worktree standing, so `git worktree add` exits 128 |
