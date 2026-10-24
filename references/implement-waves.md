# Implement: wave execution

`/implement` runs one milestone's tasks in waves. Step 3 of its milestone loop sends you here.

`rules/agent-orchestration.md` carries the policy and the shapes. This file carries what
`/implement` puts inside them. Read the rule first, and restate none of its shapes here.

`<state>` is the state directory the rule defines, and this plan's directory is
`<state>/plans/<slug>/`.

## Schedule the waves

Slices marked `same-worker` share one task. Slices marked `after` land in a later wave. Slices
whose `**Files**:` overlap never run concurrently. Everything else is free. Group for coherence
rather than for a worker count. A task that spans one subsystem is easier to brief and verify
than one assembled to fill a slot.

## Spawn each task

Take the waves of the current milestone in order. For each task in the wave:

1. Set the task's `status` to `running` in `state.yml`. Create its scratch directory,
   `<state>/plans/<slug>/scratch/<m>-<task>/`.
2. Write its brief, per [The brief](#the-brief).
3. Spawn it at the approved tier:
   ```
   Agent(subagent_type="implement-worker", description="<m>-<task> <slug>",
         model=<the approved model>, effort=<the approved effort>, prompt=<the brief>)
   ```
   Record the agent ID it returns beside the task, for `SendMessage` and `TaskStop`.

**Spawn every task in the wave before you wait for any of them.** Put the spawns in one message.
The roster gate approved the wave as concurrent.

**Every task worker is an editing worker.** `implement-worker` grants `Edit`, `Write`, and `Bash`,
and its hook blocks git writes. A worker that *cannot* stage is safer than one asked not to. Two
workers that share a tree would otherwise cross-commit silently. The hook is a backstop, and the
declared-path check in [The join](#the-join) is the bound.

On a Codex host, no such denial exists. The roster gate disclosed that. Do not restate it here as
a guarantee.

## The brief

`implement-worker`'s definition carries what every task shares: stay inside the worktree, write
no undeclared path, run no git write, stop when stuck, the five-step procedure, and the report's
status line. The brief carries what varies, in the four sections `rules/agent-orchestration.md`
fixes:

```
  ## Objective       the task spec <state>/plans/<slug>/tasks/<m>-<task>.md, which carries the
                     slices, their files, their verification, and their proof commands. Name the
                     plan file for surrounding context
  ## Boundaries      the worktree of each repository this task writes in (absolute), its branch,
                     the declared paths inside each, and the scratch directory (absolute)
  ## Tool guidance   the prior waves of this milestone and what they committed, or "this is the
                     first wave of this milestone"
  ## Output format   the report as the final message, opening with CLEAN or ESCALATION
```

**A task receives one worktree entry per repository it writes in.** Each entry names that
repository's own worktree, and it scopes the task's declared paths to that repository. Most tasks
write in one repository. A `same-worker` task may hold slices in two, and the commit block below
then commits it once per repository.

**An escalated report's path carries the milestone, not the task letter alone.** A composition
may restart task letters per milestone, so `reports/<task>.md` would let M2 task A overwrite M1
task A. That destroys an escalation record that nothing recreates.

**Amend a running task with `SendMessage`.** Edit its task spec first, so the spec stays the
record. Never spawn a second worker for one task.

## The join

1. **Wait for every worker in the wave to finish.** Each completion notice arrives on its own.
   Never poll. A notice that marks a worker failed is a failure to investigate, per the rule's
   `## Completion`.
2. **Sweep the status lines.** Each report opens with `CLEAN` or
   `ESCALATION: <what it found>`. Finish the sweep before you read any report in full. Where
   nothing escalated, read only what you need for the commit messages. Write each escalated
   report to `<state>/plans/<slug>/reports/<m>/<task>.md`, then take it to `/implement`'s
   `## Escalation`.
3. **Check the declared paths.** In each worktree the wave wrote in:
   ```bash
   git -C "<worktree>" status --porcelain
   ```
   Every path it lists must fall under a declared path of a task in this wave. The paths the
   provisioning contract wrote are exempt, as `/worktree`'s teardown checks define them. Any other
   path is a deviation. Stop, and put it to the user under `Blocked` exactly as you would an
   escalation.

Then commit the wave's tasks. **Commit each task separately, staging only its declared paths:**

```bash
cd <the worktree of the repository that task wrote in>
git add <task's declared paths>
git commit -m "<type>(<scope>): <task summary>"
```

Never `git add -A` — another task's work may be in the tree. A task that wrote in two
repositories commits once per repository. Then set each task's `status` to `committed` and its
`commit` to the short SHA in `state.yml`, and start the next wave of this milestone. Emit the wave
state block below after that wave starts. After the last wave, emit one final block with every
task committed.

**The wave join is the only place a task commits.** No step after the last wave commits a task
again. A second task commit instruction stops on `nothing to commit`. Deferring it instead lets a
later wave's changes enter an earlier task's diff.

The milestone loop's critique remedies are the one exception, and its step 5 owns that commit.

## The wave state block

Every wave join emits one block, and this is the only place a wave speaks.
`rules/chat-vocabulary.md` reserves the `Running` heading for it. It stops nothing and carries
no footer.

**Emit it after the next wave starts, never before.** A block that shows the next wave as pending
goes stale immediately, and the user must ask.

**It carries every wave in the milestone, not the wave that just ended.** The user's need is to
read where the run is without asking. A block that covers one wave answers that for ten minutes,
and then the reader asks again.

**Running — `<milestone>`**

```
  wave 1  ✓ A  salvage artifacts       committed 927c3db
  wave 2  ▶ B  skeleton and contract   opus · high   agent a3f9c2
  wave 3    C  measurement harness     opus · xhigh
            D  shared guest image      opus · xhigh
  wave 4    E  three backends          opus · xhigh
  wave 5    F  run the bakeoff         supervised
  wave 6    G  decision record         opus · high
```

<what the plan did not anticipate, in one or two sentences>

Each row names its wave, the task letter, and a short task name. The state follows:

```
  committed   ✓ and the short SHA
  running     ▶, the tier, and the worker's agent ID
  pending     the tier alone
```

No row repeats a wave number. Rows after a wave's first row leave the wave column empty, as
wave 3 does above. An escalated task takes ⚠ and a blocked one takes ⊘, per the glyphs in
`rules/chat-vocabulary.md`.

Keep the paragraph to what a reader needs to orient. A wave that met the plan needs no sentence
at all. An escalation belongs under `Blocked` instead, which `/implement` owns.
