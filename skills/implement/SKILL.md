---
name: implement
description: Execute an approved plan as a loop of milestones, each landing its own PRs
argument-hint: "[plan/<slug>] [--critique <models>]"
---

# Implement

Orchestrate execution of an approved plan. You own git, todo lifecycle, and worker
coordination. Workers write code and nothing else.

The plan declares **slices**. This skill composes them into **milestones**, and each milestone
ships its own PRs before the next one starts.

```
  slice       one worker's unit of work. Narrow, vertical, one repository.
  milestone   a consumable chunk of a plan, sequenced in a DAG. May span
              repositories. The unit of delivery.
  wave        the concurrency schedule inside a milestone, from file overlap.
```

A **task** is one worker, one todo, one report scratchpad, one model tier. A task carries one
slice, or several that must not drift apart. Workers escalate on **deviation**, not on
completion — see [Escalation](#escalation).

## Input

- **A plan pad** (`plan/<slug>` or an id) — the normal case. A calling skill passes it here.
- **`--critique <models>`** — the critique roster. Without it, read the pad's `### References`.
- **Existing todos for the slug** — this is a resumed run. The todos *are* the composition, so
  reuse them rather than composing again. Pick up at the first milestone with open tasks.

Read the pad fully. If none exists, send the user to `/plan`.

The pad's `### References` names the `Worker runtime:`. With none named, use the host runtime, per
`solo-agent-orchestration`.

With no plan pad named, list the active pads via `scratchpad_list(tags=["plan"])` and ask which
one. That opens a `Deciding` gate, per `rules/chat-vocabulary.md`, and a caller never reaches it.

Use whichever Solo project is currently selected, consistent with `/plan`.

## Speaking

`rules/chat-vocabulary.md` reserves the headings and the footer. Speak on five occasions and no
others: a gate, a wave join, a milestone landing, an escalation, and a failure.

Narrate no worker completion. That ban cites 78% of one run's assistant turns, which counted one
message per worker. A wave join instead emits one `Running` block covering every wave of the
milestone, and `references/implement-waves.md` defines it.

## The exit criterion

The plan declares one machine-checkable end state per work item, and the command that proves it.
Run each milestone to the criteria of the work items it carries. Never ask the user whether to
continue, and never re-ask a question the plan already answered.

Stop on these, and on nothing else:

```
  no plan pad
  a /worktree refusal
  census drift
  a critique escalation, C1 to C6
  the roster gate
  the push gate
  a worker deviation
  an integration finding that invalidates an open PR
```

## Compose the milestones

Skip anything the `/plan` fork already confirmed — do not re-ask what the user just settled.

1. **Compose milestones from the plan's slices.** A milestone's outcome is one sentence with no
   `and`. Add slices while that sentence stays true. Open a new milestone once the sentence needs
   an `and`. That is the whole test.

   A milestone may span repositories, and it then lands **one PR per repository it touches**.
   Each PR title states the milestone's outcome, scoped to its repository.
2. **Order the milestones into a DAG.** Aggregate every slice's `after` constraint onto the
   milestones that hold the two slices. That aggregate is the dependency half of the order.

   **File overlap forces ordering, never parallelism.** Add an edge for every file two milestones
   share. The loop is sequential either way, so this edge decides which of the two ships first.
   The second branch would otherwise carry a conflict the user never approved.
3. **Schedule the waves inside each milestone.** `references/implement-waves.md` carries the
   rules that turn file overlap into a wave order.
4. **Assign each task a model and effort tier.** A task does not inherit these from the session.
   Judge by what the task demands. A mechanical edit against precise line references is not a
   contract-preserving rewrite, and the two should not cost the same. Every task runs on the
   worker runtime the roster gate approves, and model and effort vary within it.
5. **Gate the roster.** This is an approval stop, not an announcement. Milestones and their PR
   titles come first. Waves and tiers come second, inside the milestone that holds them.

   **Approve — roster for `plan/<slug>`**

   ```
   2 milestones, 4 workers.

     M1  reserve a chat vocabulary for messages that need a reply
         agents  feat(rules): reserve a chat vocabulary for messages that need a reply
         wave 1
           A  rules/chat-vocabulary.md                       opus · xhigh
              Author one rule from scratch, matching house style across six
              existing files.
         wave 2
           B  skills/{research,recall,stash}/SKILL.md        sonnet · medium
              Three localized edits against precise line references.

     M2  deliver each milestone as its own PRs
         agents  feat(skills): deliver each milestone as its own PRs
         after M1 — both touch README.md
         wave 1
           C  skills/{plan,implement}/SKILL.md               opus · xhigh
              Rewrite two skills onto one delivery vocabulary that must not
              drift between them.
           D  rules/pr-first-contributions.md                sonnet · high
              Add stacked-PR guidance to a general rule without turning it
              into an appendix.

     Workers: <runtime> — from the plan, or the host runtime.
     Critique per milestone: <models> — from the plan.
     Sandbox: <runtime> cannot deny a worker's git writes.
   ```

   Adjust any milestone boundary, model, effort, or grouping, or approve as proposed.

   ⏸ waiting on you: approve the roster, or name what to change

   **The summary is the justification.** One task reads "three localized edits against precise
   line references". Another reads "a rewrite of two skills onto one vocabulary". Each argues for
   a different tier by itself. Write the summary so the tier follows from it, and add no separate
   rationale field.

   The roster is where a milestone that does two things, or two milestones that should be one,
   becomes obvious.

   **Both runtime lines come from the plan.** `/plan` records them under `### References`, and
   `--critique` overrides the critique roster. Restate both in this gate as lines the user can
   change, and ask nothing else. With no roster in the pad or `--critique`, use the host runtime,
   per `solo-agent-orchestration`. One run holds one roster, or nobody can compare its milestone
   findings. `list_agent_tools` resolves the enabled runtimes. Never hardcode a roster.

   **Disclose a worker runtime that cannot deny git writes.** `rules/solo-agent-orchestration.md`
   carries the posture, and the adapter names what each runtime can enforce. Read both before you
   propose a runtime. Where one cannot deny those writes, include the `Sandbox` line above and
   name the exposure. Two workers in one tree cross-commit each other's work. Omit that line where
   the worker runtime denies them. Do not restate a flag, and never promise a denial the
   roster cannot give.
6. **Create the todos** — one per approved task, tagged with its milestone. The body carries the
   **task spec**: the slices it covers, their files, their verification, and their proof
   commands. The plan holds slices; the todo holds the grouping, which exists nowhere else. The
   worker reads its own todo, so this is the only place the spec belongs.
   ```
   todo_create(title="<task>: <name>", body=<task spec>,
               tags=["plan:<slug>", "milestone:<m>", "project:<repo>", "task:<letter>"])
   todo_add_blocker(todo_id=<dependent>, blocker_id=<prerequisite>)
   ```
   Keys and tags are lowercase.

   **Every automated check must be able to fail.** Run each check against the pre-change tree
   before you write it into the spec, and record the output there. A check that already passes
   needs a mutation proof. Copy the file to a scratch path, break what the check tests, and record
   the failure on the copy. Never mutate the repository for a proof. Mark a check `unverifiable`
   where neither route works, and say why.

   Two checks in the corpus could never fire. `grep -rn 'App\\Models'` searched for two literal
   backslashes, and `grep -ci Test` matched an unrelated domain string. Both read as passing
   evidence.

## The milestone loop

**This loop is sequential.** Run the milestones in DAG order, one at a time. One pass ships one
milestone, then starts again at step 1. Two milestones never run at once, whatever their DAG
edges allow. This skill therefore offers no concurrency setting, and it asks the user for none.
The waves inside one milestone still run their tasks concurrently — that is step 3's job.

1. **Cut a worktree and branch for each repository the milestone touches.** Write the branch key
   first, then cut:
   ```
   kv_set(key="plan:<slug>:milestone:<m>:branch:<repo>", value="<branch>")
   /worktree cut <container path from the plan's **Repos**: line> <milestone> <branch> <base>
   ```
   **The key goes first, and that order is load-bearing.** `/worktree` reads the key to tell a
   resume from a collision. Write it after the cut, and a run that dies between the two takes the
   collision branch. It then escalates over its own branch.

   **Pass the container path, never the repository name.** `/worktree` substitutes it into
   `--git-dir`. Pass `agents` instead, and cut mode resolves against the session's working
   directory and refuses an already-converted repository. `/plan` records the container path on
   its `**Repos**:` line. `<repo>` stays the short name in every KV key here.

   That skill owns the layout, the provisioning, the naming, and every refusal it states. Add
   nothing to its procedure, and do not paraphrase it.

   **A `Blocked` from `/worktree` stops this milestone.** It refuses a plain clone, and it refuses
   a repository that carries no provisioning script. Pass that report to the user as it stands, and
   cut no second worktree. The tree it kept is the one the retry reuses.

   The branch is `<type>/<slug>-<milestone>`, per `solo-agent-orchestration`. The base is
   `origin/HEAD`, or the predecessor milestone's branch in that repository when the milestones
   stack there. **Pass both to `/worktree`, which builds
   neither.** `<type>` is `feat`, `fix`, or `chore`, and this skill holds that choice. Let
   `/worktree` construct the name a second time, and the two can differ from the key you just
   wrote.

   **A resumed run may find the worktree still standing.** `/stash` leaves one behind, and
   `solo-agent-orchestration` carries both tests. Reuse a recorded path that holds this
   milestone's branch, and stop where it holds anything else.

   `/worktree` records the tree path under `plan:<slug>:milestone:<m>:worktree:<repo>`. Both keys
   carry the milestone and the repository, and `solo-agent-orchestration` says why.
2. **Re-check the census in the worktree.** The plan's `**Files**:` lists came from a census at
   plan time. Repeat it now for this milestone's slices, in the tree you just cut.
   `/plan` names what it searches for: the caller, the test, and the standard your change
   falsifies.

   **Escalate on drift.** A path the census now returns, and the plan does not declare, is a
   deviation. Stop and put it to the user. Do not widen a task's declared paths yourself.
3. **Run the milestone's waves.** `references/implement-waves.md` carries the spawn, the brief
   pad, the pointer, the guard, and the join. Each wave commits its own tasks at its join, so no
   task commit follows the last wave.
4. **Critique this milestone's diff, once per repository it touches.** Name the base explicitly,
   and pass the plan:
   ```
   /critique --base <that repository's effective base> --plan <the plan pad>
   ```
   A repository's effective base is the ref step 1 cut from there. That is `origin/HEAD`, or the
   predecessor milestone's branch where those milestones stack.

   **One `--base` cannot express two repositories.** Repository A stacks on `fix/<slug>-m1` while
   repository B starts from `origin/HEAD`. One ref is then wrong for one of them. It either fails
   to resolve, or it pulls in commits this milestone never touched.

   Without `--base`, `/critique` falls back to the default branch and reviews the predecessor's
   diff as this milestone's. It then re-raises findings the user already settled.

   Every invocation uses the critique roster the gate approved.
5. **Apply the filter and present what survives.** `/critique` owns the filter, the ledger, and
   the presentation of a finding. Point at it and add nothing. Each repository's invocation
   returns its own ledger, so present them grouped by repository.

   **Commit the remedies.** `/critique` applies each accepted fix in this milestone's worktrees,
   and it leaves them uncommitted. Commit them here, once per repository, before the push gate:
   ```bash
   git add <the paths the ledger's fixes touched>
   git commit -m "fix(<scope>): apply the critique remedies for milestone <m>"
   ```
   This is the one commit outside a wave join. Skip it, and the push gate counts commits over a
   dirty tree.
6. **Gate the push.** `pr-first-contributions` forbids a push without explicit approval, and this
   gate is where you ask. Re-run its staleness check first.

   **Approve — push milestone `<m>`**

   ```
     <repo>   <N> commits   base <branch>   "<the PR title>"
     <repo>   <N> commits   base <branch>   "<the PR title>"

     Quality gates: <results>
   ```

   ⏸ waiting on you: approve the push for milestone `<m>`
7. **Push and open one PR per repository the milestone touches.** Follow
   `pr-first-contributions`, which owns the stacked-PR base and the title spec. Update an open PR
   rather than opening a second one.
8. **Run the integration critique, once the last milestone has pushed.** This is a step, not an
   option. Skip it on every earlier milestone.
   ```
   /critique --integration <slug> --plan <the plan pad>
   ```
   It runs the four integration lenses with the same critique roster. One of them is the
   reason this step exists: did every slice the plan declared land in some milestone? A
   per-milestone critique sees one milestone's diff, so it cannot answer that.

   Every milestone pushed its branch, so the diffs live on the remote. `/critique` step 1 states
   how it resolves them. Pass the slug and the plan, and add nothing to that procedure.

   **This pass needs no worktree, and that is why it can run.** Step 10 of an earlier milestone
   removed the worktree of every repository this milestone leaves alone.

   **The integration pass edits nothing, and `/critique` owns that.** Its ledger line reads
   `remedy:` rather than `fixed:`. Every milestone it reviews already shipped its PRs, so an
   accepted remedy lands as a follow-up milestone. Propose that milestone and let the user approve
   it. Escalate as `Blocked` where a finding invalidates a PR the run already opened.

   **It runs before the landing so its result reaches the user inside `Landed`.** Run it after,
   and the run speaks a sixth time.
9. **Announce the landing.** It reports and does not block.

   **Landed — `<milestone>`**

   ```
   <the milestone's outcome, in one sentence>

     <repo>   <PR url>   <N> commits   base <the default branch>
     <repo>   <PR url>   <N> commits   base <the predecessor milestone's branch>

     Quality gates: <results>
     Critique:      <N> findings, <M> presented, <models>
     Integration:   <N> findings, <M> presented, <models>
   ```

   Then the ledger, in the shape `/critique` defines. `Landed` carries no footer, because the
   run continues.

   **The last milestone's block carries the `Integration:` line and the integration ledger too.**
   Omit both on every earlier milestone, because step 8 ran nothing there.
10. **Tear down and clean up.** Do all four, in this order:
    ```
    timer_cancel(timer_id=<each guard armed for this milestone>)
    close_process(process_id=<each worker of this milestone>)
    lock_release for any lock a dead worker left held
    stop the stack and remove the worktree, per /worktree's teardown block
    ```
    The branch lives on the remote once the push succeeds, so the worktree is disposable. A guard
    left armed fires during a later milestone, about workers that finished long ago.

Then start the next milestone.

**Critique and triage block the next milestone. The user's PR review does not.** A finding that
survives the filter may change what the next milestone should do, so the loop waits for it. The
run would otherwise stall behind a human queue. Open the PR, announce the landing, and move on.

## Escalation

A worker escalates when it cannot self-resolve. It also escalates when finishing would mean
deviating meaningfully from what the user approved. A worker that writes an undeclared path
deviates from the task.

**In-flight workers in the same wave finish.** They hold disjoint file scopes, so no other work
depends on the problem.

The worker's report scratchpad is the durable record, and its completion signal says whether it
escalated. The wave join is the only place an escalation appears. Resolve every escalation before
the milestone lands, or the run stops here.

**Blocked — milestone `<m>` wave `<N>`**

```
  A  ✓ committed
  B  ⚠ escalated — <what the worker found>
  C  ⊘ blocked behind B

The plan assumed <X>; the code actually does <Y>.
Options: <adjust the plan / a different approach / drop the slice>

I recommend <the option>, because <the ground it rests on>.
```

⏸ waiting on you: pick one option for task `B`

**The recommendation is mandatory.** `rules/chat-vocabulary.md` requires one on every question, and
a `Blocked` options list ranks nothing by itself. Name the option you would take and the ground it
rests on. An `Approve` gate needs no separate line, because its proposal is its own
recommendation.

Do not start the next wave until you resolve this. If the plan needs a change, update the pad so
it stays the record of what the user actually agreed.

Automated verification failing is not automatically an escalation — a worker that can fix it
within the plan's intent should. It escalates when the fix would require departing from the plan.

## Close

Close the run after the last milestone lands. Every milestone pushed its own PRs and tore down
its own worktrees, and step 9 reported the integration critique. Nothing here opens a PR.

1. `scratchpad_archive(scratchpad_id=<plan pad>)` — it has served its purpose
2. `todo_delete` every todo tagged `plan:<slug>` — the run ended, so nothing reads the grouping now
3. `kv_delete` every `plan:<slug>:*` key
4. `close_process` any surviving worker
5. `git worktree prune` in each container, per `solo-agent-orchestration`

**Delete the todos rather than leaving them completed.** `todo_complete` keeps the todo, so a
closed run otherwise leaves one per task in Solo forever. The README says todos exist only while
this skill runs a plan, and step 2 is what makes that true. Each report scratchpad already holds
what the task did.

**Close is silent.** Each `Landed` already carried its own PR URLs, quality gates, and ledger.
Repeat none of it here. `rules/chat-vocabulary.md` reserves five occasions, and a closing report
is a sixth.

**The integration critique runs before this section, and that order matters.** It compares the
landed branches against the plan pad. Archive the pad first, and you remove half of that
comparison.

## Notes

- Never commit to the default branch; never push or open a PR without explicit approval
- If the plan turns out to be wrong, fix the plan and re-approve. Never let implementation
  quietly diverge from the approved record
