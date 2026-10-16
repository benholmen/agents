# Implement: wave execution

`/implement` runs one milestone's tasks in waves. Step 3 of its milestone loop sends you here.

`rules/solo-agent-orchestration.md` carries the policy and the shapes. This file carries what
`/implement` puts inside them. Read the rule first, and restate none of its shapes here.

Workers are Solo agents, per `solo-agent-orchestration`. Nothing below works otherwise. A vendor
sub-agent cannot hold a lock, own a todo, or wake this session when it finishes.

Call `whoami` once and keep the returned `process_id`. Every worker needs it to signal back.

## Schedule the waves

Slices marked `same-worker` share one task. Slices marked `after` land in a later wave. Slices
whose `**Files**:` overlap never run concurrently. Everything else is free. Group for coherence
rather than for a worker count. A task that spans one subsystem is easier to brief and verify
than one assembled to fill a slot.

## Spawn each task

Take the waves of the current milestone in order. For each task in the wave:

1. `todo_update(todo_id, status="in_progress")` — status is `open`, `in_progress`, `backlog`,
   or `completed`, and priority is `high`, `medium`, or `low`
2. Spawn at the approved tier, on the worker runtime `/implement` resolved, enforcing every constraint the
   runtime can enforce:
   ```
   spawn_agent(agent_tool_id=<that runtime's id>, name="<task>-<slug>", extra_args=[
     <the model and effort arguments, at the approved tier>,
     <the auto-approval argument from the adapter>,
     <the editing-worker arguments from the adapter, with any per-command git denial>,
     <the system-prompt argument carrying the preamble below, if the runtime has one>])
   ```
   `list_agent_tools` returns a `tool_type` for each runtime. Read `references/runtime-<tool_type>.md`
   and use the arguments it lists. Never write a launch argument from memory. A runtime renames
   its flags between releases, and the adapter is the only current record.

   Auto-approval keeps the worker from stalling on its actual job. It still leaves the requests
   that matter reviewable. Never use a bypass mode.

   **Every task worker is an editing worker.** `rules/solo-agent-orchestration.md` carries that
   class and what each runtime can enforce for it. A sandbox that permits a worker's edits permits
   `git add` in the same tree. Only a per-command deny list denies it, where the runtime scopes one
   to a single worker. Use that denial where the runtime has one. A worker that *cannot* stage is
   safer than one asked not to. Two workers that share a tree cross-commit silently.

   Where the runtime has no such denial, the denial does not exist. The roster gate disclosed
   that. Do not restate it here as a guarantee.

   When a spawn fails, read the adapter, correct the arguments, and retry once. Escalate on the
   second failure, and never loosen a flag to make a launch succeed.
3. Write this task's brief pad, per [The brief pad](#the-brief-pad).
4. `send_input(process_id, input=<the pointer>)`, per [The pointer](#the-pointer).

Those four steps run once per task. **Spawn every task in the wave before you wait for any of
them.** The roster gate approved the wave as concurrent, and waiting after each spawn serialises
it. One guard then covers one task instead of the wave.

## The preamble

The **preamble** has two halves. What a worker must not touch, and what to do when stuck, are
identical for every worker in the milestone. The working directory is not. Pass the preamble
through the runtime's system-prompt argument, or in every prompt where the runtime has none.

**A task receives one preamble per repository it writes in.** Each one names that repository's own
worktree, and it scopes the task's declared paths to that repository. The task's lock keys come
from the matching worktree, so a path locks under the tree that holds it.

Most tasks write in one repository and take one preamble. A `same-worker` task may hold slices in
two, and it then takes two. The commit block below already commits such a task once per
repository. `solo-agent-orchestration` carries the same rule.

```
You are a Solo agent implementing one task of an approved plan.

Working directory: <this repository's worktree, absolute>. Stay inside it.
Declared paths: <this task's paths inside this repository>.

Do not write any file outside your task's declared paths — needing to is a deviation.
Do not create or complete todos, or write KV. Write only your own report scratchpad.
The orchestrator owns git. Run no git write, whatever your permission layer allows.

When stuck, or when finishing would mean departing meaningfully from the task as written:
record what you found and stop. Do not improvise a fix, expand scope, or proceed down an
unapproved path. Stopping is correct behavior here, not failure.

Lock and KV keys must be lowercase — normalize any path before using it as a key.
```

## The brief pad

One pad holds one worker's brief, and `send_input` never carries the brief itself.
`solo-agent-orchestration` fixes the six sections under `## The worker brief pad`. Keep that
order, and put this task's content in each:

```
  ## Solo context     the worker's process id, this project, and the agent_instructions
                      that spawn_agent returned
  ## Objective        Solo todo <id>, which carries the slices, their files, their
                      verification, and their proof commands. Name the plan pad for
                      surrounding context.
  ## Boundaries       the worktree of each repository this task writes in, the branch, the
                      declared paths, the worker's scratch directory, and the preamble above
  ## Tool guidance    the prior waves, or "this is the first wave of this milestone", plus
                      any lock this task needs
  ## Output format    the report pad "<slug>/<milestone>/<task>", and the ESCALATION: marker
  ## Completion       the rule's timer_set call, with this session's process_id
```

A mid-run amendment edits that pad in place. Never write a second pad for one worker.

`## Completion` carries the body text, and the rule gives the call:

```
body="Task <letter> complete, <clean|escalated>. Report in scratchpad <the report pad id>."
```

**A brief pad, a guard pad, and a report pad carry no H1.** The rule's `## The worker brief pad`
says why.

**Take a lock only where a second writer may exist.** The rule's `## Locks and reports` carries
that test and the key shape. Tell the worker to report the holding actor and escalate where a
lock is unavailable, rather than wait.

**The report pad carries the milestone, not the task letter alone.** A composition may restart
task letters per milestone, so `<slug>/<task>` lets M2 task A overwrite M1 task A. That destroys
an escalation record that nothing recreates.

`## Objective` also carries the worker's own procedure:

```
1. Read every file your task names, fully, before you change anything
2. Make the changes
3. Run the task's automated verification, then each proof command your todo names.
   Every check must be able to fail.
   Run each one against the pre-change state first. Where a check already passes, prove it fails
   on a mutated copy under <this worker's scratch directory, absolute>. Never mutate the
   repository for a proof.
4. Write your report to scratchpad "<slug>/<milestone>/<task>", with no H1, and keep the id it
   returns. Record what you did, the verification output, each proof command and its result, and
   anything you found that the task did not anticipate. Begin the report with "ESCALATION:" if
   you stop rather than finish.
5. Release any lock you took, then signal completion per `## Completion`
```

## The pointer

`send_input` carries a pointer at the brief pad and nothing else. `solo-agent-orchestration` gives
the text under `### The pointer shape`, and the 1,000-byte ceiling that forces it under
`## The PTY ceiling`. The pointer names the pad id, and the id sits last, because a truncated
message arrives as its tail.

## The join

1. **Wait for the workers to signal.** Each one wakes this session directly when it finishes.
   One idle timer per wave is the dead-worker fallback, and nothing more.

   Write the guard pad before you arm that timer, in the shape `### The guard pad` gives. The
   body names the pad id and stops there. The 1,000-byte ceiling covers a guard body too.

   Then arm the timer, once the workers produce output. An entirely idle watch list returns
   `already_satisfied` and creates no timer at all.
   ```
   timer_fire_when_idle_all(processes=[<pids>], max_wait_ms=<generous guard>,
     body="Guard fired for milestone <m>, wave <N>.
           A worker that never signalled is a failure to investigate, not a completion.
           Procedure: scratchpad_read(scratchpad_id=<the guard pad id>)")
     → timer_id
   ```

   Do not treat that timer as the completion signal. It has no debounce, and a worker that thinks
   at length looks like a finished one — see `solo-agent-orchestration`.

   Keep the returned `timer_id`. One guard per wave means one id to hold.
2. When every task in the wave signals, `timer_cancel(timer_id=<id>)` for that wave's guard. Then
   run `scratchpad_find` for `ESCALATION` across the wave's report pads. Do this before you read
   any pad in full. If nothing matches, read only what you need for the commit messages.

Then commit the wave's tasks. **Commit each task separately, staging only its declared paths:**

```bash
cd <the worktree of the repository that task wrote in>
git add <task's declared paths>
git commit -m "<type>(<scope>): <task summary>"
```

Never `git add -A` — another task's work may be in the tree. A task that wrote in two
repositories commits once per repository. Then `todo_complete` each task and start the next wave
of this milestone, which marks its todos in progress. Emit the wave state block below after that
wave starts. After the last wave, emit one final block with every task committed.

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
  wave 2  ▶ B  skeleton and contract   opus · high   worker 383, todo 161
  wave 3    C  measurement harness     opus · xhigh
            D  shared guest image      opus · xhigh
  wave 4    E  three backends          opus · xhigh
  wave 5    F  run the bakeoff         supervised
  wave 6    G  decision record         opus · high
```

<what the plan did not anticipate, in one or two sentences. Then the guard's id.>

Each row names its wave, the task letter, and a short task name. The state follows:

```
  committed   ✓ and the short SHA
  running     ▶, the tier, the worker process id, and the todo id
  pending     the tier alone
```

No row repeats a wave number. Rows after a wave's first row leave the wave column empty, as
wave 3 does above. An escalated task takes ⚠ and a blocked one takes ⊘, per the rule's glyphs.

Keep the paragraph to what a reader needs to orient. A wave that met the plan needs no sentence
at all, and the guard line is then the whole paragraph. An escalation belongs under `Blocked`
instead, which `/implement` owns.
