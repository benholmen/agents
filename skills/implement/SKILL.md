---
name: implement
description: Execute an approved plan as a loop of milestones, each landing its own PRs
argument-hint: "[<slug> | <plan file>] [--in container|checkout|main] [--critique <roster>]"
---

# Implement

Orchestrate execution of an approved plan. You own git, `state.yml`, and worker coordination.
Workers write code and nothing else.

The plan declares **slices**. This skill composes them into **milestones**, and each milestone
ships its own PRs before the next one starts.

```
  slice       one worker's unit of work. Narrow, vertical, one repository.
  milestone   a consumable chunk of a plan, sequenced in a DAG. May span
              repositories. The unit of delivery.
  wave        the concurrency schedule inside a milestone, from file overlap.
```

A **task** is one worker, one task spec, one report, one model tier. A task carries one
slice, or several that must not drift apart. Workers escalate on **deviation**, not on
completion — see [Escalation](#escalation).

`<state>` below is the state directory `rules/agent-orchestration.md` defines. This plan's
directory is `<state>/plans/<slug>/`.

## Input

- **A plan** (`<slug>`, or the path of its `plan.md`) — the normal case. A calling skill passes it
  here.
- **`--in <mode>`** — where the work happens, for every repository in the run. See
  [Where the work happens](#where-the-work-happens). Plain words carry it too: "work in my
  checkout" is `checkout`, and "commit straight to main" is `main`.
- **`--critique <roster>`** — the critique roster. Without it, read the plan's `### References`.
- **An existing `state.yml` for the slug** — this is a resumed run. `state.yml` *is* the
  composition, so reuse it rather than composing again. Pick up at the first milestone that has
  not landed.

Read the plan fully. If none exists, send the user to `/plan`.

With no plan named, list the active plans under `<state>/plans/` and ask which one. That opens a
`Deciding` gate, per `rules/chat-vocabulary.md`, and a caller never reaches it.

## Where the work happens

Each repository runs in one of three workspace modes. `container` gives each milestone a tree of
its own. The other two work in the folder you work in, the way a person would.

```
  container   a worktree inside a converted repository: <container>/<plan-slug>-<m>
  checkout    your own checkout, on the milestone's feature branch
  main        your own checkout, committing on the default branch, with no PR
```

`<container>` is the path on the plan's `**Repos**:` line. Your own checkout, `<checkout>` below,
is `<container>/main` in a converted repository, and `<container>` itself in a plain clone.
`<default>` is the branch `origin/HEAD` names.

**Without `--in`, the repository's layout decides, by this table and nothing else:**

```
  converted repository (its .git is bare)      container
  plain clone                                  checkout
```

Test the layout with `git --git-dir="<container>/.git" rev-parse --is-bare-repository`. A
milestone worktree needs the bare layout, so a plain clone works in your checkout until you
convert it with `/bare-convert`.

**`--in` overrides the table for every repository.** Two choices still refuse:

```
  container on a plain clone       a plain clone has no bare layout. Convert it first
  main without the user's words    the table never picks main. It needs --in main or plain words
```

`--in main` is the explicit instruction `pr-first-contributions` requires before a commit lands on
the default branch. No other mode commits there.

**`checkout` and `main` share your folder with the run.** The tree must hold no uncommitted work
when the milestone starts, and you and your other sessions stay off it until the run closes. In
exchange, it needs no provisioning: the run uses your `.env`, your installed dependencies, and the
stack you already run.

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
  no plan
  a workspace refusal: a /worktree Blocked, or a checkout holding uncommitted work
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
   Each PR title states the milestone's outcome, scoped to its repository. A repository in `main`
   mode lands a push to its default branch instead of a PR.
2. **Order the milestones into a DAG.** Aggregate every slice's `after` constraint onto the
   milestones that hold the two slices. That aggregate is the dependency half of the order.

   **File overlap forces ordering, never parallelism.** Add an edge for every file two milestones
   share. The loop is sequential either way, so this edge decides which of the two ships first.
   The second branch would otherwise carry a conflict the user never approved.
3. **Schedule the waves inside each milestone.** `references/implement-waves.md` carries the
   rules that turn file overlap into a wave order.
4. **Assign each task a model and effort tier.** A task does not inherit these from the session.
   Judge by what the task demands. A mechanical edit against precise line references is not a
   contract-preserving rewrite, and the two should not cost the same. Every task runs as an
   `implement-worker`, and model and effort vary per task.
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
           B  skills/{research,critique,worktree}/SKILL.md   sonnet · medium
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

     Workspace:  agents   checkout   ~/repos/agents, one feature branch per milestone
                          plain clone, not yet converted
                          keep yourself and other sessions off it until the run closes
     Critique per milestone: claude:opus, codex:<model> — from the plan, resolved now
                             M1 medium (one rule file), M2 high (two skills rewritten)
   ```

   Adjust any milestone boundary, model, effort, grouping, or workspace, or approve as proposed.

   ⏸ waiting on you: approve the roster, or name what to change

   **The summary is the justification.** One task reads "three localized edits against precise
   line references". Another reads "a rewrite of two skills onto one vocabulary". Each argues for
   a different tier by itself. Write the summary so the tier follows from it, and add no separate
   rationale field.

   The roster is where a milestone that does two things, or two milestones that should be one,
   becomes obvious.

   **The workspace line names every repository's mode, its tree, and the fact that decided it.**
   That fact is `--in`, the user's words, or the row of the layout table that matched. The user
   can change any repository's mode here. Add the shared-folder line wherever a repository runs
   in `checkout` or `main`. For `main`, say that commits land on the default branch with no PR.

   **The critique line comes from the plan, resolved here.** `/plan` records the roster under
   `### References`, and `--critique` overrides it. With neither, use `/critique`'s default
   roster: one Claude critic and one Codex critic. Resolve each entry's model now, per
   `/critique` step 2, and show the resolved models. One run holds one set of models, or nobody can
   compare its milestone findings.

   **Size each milestone's critique effort from `/critique`'s target table,** and give the reason
   beside it, the way a task's summary argues for its tier. A one-file config milestone gets
   `medium`, an ordinary one `high`, and one that touches auth or a public contract `xhigh`. The
   user can change either line here, and the gate asks nothing else about critique.

   **Disclose a host that cannot deny git writes.** On Claude, `implement-worker`'s hook denies
   them, so the roster carries no extra line. On Codex, `rules/agent-orchestration.md` says no
   per-worker denial exists. Add a `Sandbox:` line there that names the exposure: two workers in
   one tree can cross-commit each other's work. Never promise a denial the host cannot give.
6. **Write the schedule.** Write `<state>/plans/<slug>/state.yml`, the one record of the
   composition, which exists nowhere else:

   ```yaml
   plan: <slug>
   critique: [claude:opus, codex:<model>]
   workspace:
     <repo>:
       mode: checkout
       start: <the branch your checkout was on, set by milestone loop step 1>
   milestones:
     m1:
       outcome: <one sentence>
       after: []
       status: pending
       critique_effort: high
       repos:
         <repo>:
           branch: <type>/<slug>-m1
           base: origin/HEAD
           worktree: <set by milestone loop step 1>
           pr: <set by milestone loop step 7>
       waves:
         - [m1-a]
         - [m1-b]
   tasks:
     m1-a:
       title: <short task name>
       repo: <repo>
       paths: [<declared path>, ...]
       model: opus
       effort: xhigh
       status: pending
       agent: <the agent ID, set at spawn>
       commit: <set at the wave join>
   ```

   A milestone's `status` moves from `pending` to `running` to `landed`. A task's moves from
   `pending` to `running` to `committed`, or to `escalated`. Keys are lowercase.

   In `main` mode a repository's `branch` is the default branch, its `base` is the commit the
   milestone started from, and step 7 adds `head`, the commit it pushed. It records no `pr`.

   Then write one **task spec** per task, at `<state>/plans/<slug>/tasks/<m>-<task>.md`. It
   carries the slices the task covers, their files, their verification, and their proof commands.
   The plan holds slices; the spec holds the grouping. The worker reads its own spec, so this is
   the only place the grouping's detail belongs.

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

1. **Prepare each repository's tree, in its workspace mode.** Record the branch in `state.yml`
   first, then prepare the tree:
   ```
   state.yml: milestones.<m>.repos.<repo>.branch = <branch>
   ```
   **The record goes first, and that order is load-bearing.** The branch test reads it to tell a
   resume from a collision. Write it after the tree exists, and a run that dies between the two
   takes the collision branch. It then escalates over its own branch.

   The branch is `<type>/<slug>-<milestone>`, per `rules/agent-orchestration.md`, and in `main`
   mode it is the default branch. The base is `origin/HEAD`, or the predecessor milestone's
   branch in that repository when the milestones stack there. `<type>` is `feat`, `fix`, or
   `chore`, and this skill holds that choice.

   **`container` cuts through `/worktree`:**
   ```
   /worktree cut <container path from the plan's **Repos**: line> <milestone> <branch> <base>
   ```
   **Pass the container path, never the repository name.** `/worktree` substitutes it into
   `--git-dir`. Pass `agents` instead, and cut mode resolves against the session's working
   directory. `/plan` records the container path on its `**Repos**:` line. `<repo>` stays the
   short name in every `state.yml` key.

   **Pass the branch and the base, because `/worktree` builds neither.** Let it construct the name
   a second time, and the two can differ from the record you just wrote. That skill owns the
   layout, the provisioning, and every refusal it states. Add nothing to its procedure, and do not
   paraphrase it.

   **A `Blocked` from `/worktree` stops this milestone.** A converted repository with no
   provisioning script is the common case. Pass that report to the user as it stands, and cut no
   second worktree. The tree it kept is the one the retry reuses.

   **A resumed run may find the worktree still standing.** A run that stopped before its push gate
   leaves one behind, and `rules/agent-orchestration.md` carries both tests. Reuse a recorded path
   that holds this milestone's branch, and stop where it holds anything else.

   **`checkout` branches in your own checkout:**
   ```bash
   git -C "<checkout>" status --porcelain
   git -C "<checkout>" symbolic-ref --short HEAD
   git -C "<checkout>" fetch origin
   git -C "<checkout>" switch -c "<branch>" "<base>"
   ```
   **`main` brings your checkout level with the default branch:**
   ```bash
   git -C "<checkout>" status --porcelain
   git -C "<checkout>" symbolic-ref --short HEAD
   git -C "<checkout>" fetch origin
   git -C "<checkout>" switch "<default>"
   git -C "<checkout>" merge --ff-only "origin/<default>"
   git -C "<checkout>" rev-parse HEAD
   ```
   In both, the status must print nothing. On the run's first milestone, record the
   `symbolic-ref` answer as `workspace.<repo>.start`, so Close can return the checkout there. In
   `main`, record the last command's commit as the milestone's `base`. A refused fast-forward
   means your default branch holds commits the remote lacks, so stop and put it to the user.

   **A `checkout` resume finds its branch already there.** Switch to it with no `-c`. The rule's
   three branch cases apply to a checkout exactly as they do to a cut worktree.

   **Uncommitted work in your checkout stops this milestone.** That work is yours, and a branch
   switch would carry it into the run's first commit.

   **Blocked — `<checkout>` holds uncommitted work**

   ```
   found:      <the git status --porcelain lines>
   options:    commit or stash it yourself, then resume
               convert <repo> with /bare-convert, which carries the work into main/,
               then run it in container

   I recommend <the option>, because <the ground it rests on>.
   ```

   ⏸ waiting on you: clear `<checkout>`, or convert `<repo>`

   Record the tree under `milestones.<m>.repos.<repo>.worktree`: the path `/worktree` reported, or
   `<checkout>` itself. Then set the milestone's `status` to `running`.
2. **Re-check the census in the worktree.** The plan's `**Files**:` lists came from a census at
   plan time. Repeat it now for this milestone's slices, in the tree you just cut.
   `/plan` names what it searches for: the caller, the test, and the standard your change
   falsifies.

   **Escalate on drift.** A path the census now returns, and the plan does not declare, is a
   deviation. Stop and put it to the user. Do not widen a task's declared paths yourself.
3. **Run the milestone's waves.** `references/implement-waves.md` carries the spawn, the brief,
   the join, and the commit. Each wave commits its own tasks at its join, so no task commit
   follows the last wave.
4. **Critique this milestone's diff, once per repository it touches.** Name the base explicitly,
   and pass the plan:
   ```
   /critique --base <that repository's effective base> --plan <the plan file> \
             --critique <each critique entry>@<this milestone's critique_effort>
   ```
   A repository's effective base is the ref step 1 cut from there. That is `origin/HEAD`, or the
   predecessor milestone's branch where those milestones stack. In `main` mode it is the commit
   step 1 recorded as `base`.

   **One `--base` cannot express two repositories.** Repository A stacks on `fix/<slug>-m1` while
   repository B starts from `origin/HEAD`. One ref is then wrong for one of them. It either fails
   to resolve, or it pulls in commits this milestone never touched.

   Without `--base`, `/critique` falls back to the default branch and reviews the predecessor's
   diff as this milestone's. It then re-raises findings the user already settled.

   Every invocation uses the models the gate resolved, at this milestone's `critique_effort`.
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
     <repo>   <N> commits   push to <default>, no PR

     Quality gates: <results>
   ```

   ⏸ waiting on you: approve the push for milestone `<m>`
7. **Push and open one PR per repository the milestone touches.** Follow
   `pr-first-contributions`, which owns the stacked-PR base and the title spec. Update an open PR
   rather than opening a second one. Record each PR under `milestones.<m>.repos.<repo>.pr`.

   **A `main` repository pushes its default branch and opens no PR:**
   ```bash
   git -C "<checkout>" push origin "<default>"
   ```
   Record the pushed commit as `head`.
8. **Run the integration critique, once the last milestone has pushed.** This is a step, not an
   option. Skip it on every earlier milestone.
   ```
   /critique --integration <slug> --plan <the plan file> --critique <each critique entry>@xhigh
   ```
   It runs the four integration lenses with the same models, always at `xhigh`, because it
   reads every milestone together. One lens is the reason this step exists: did every slice the
   plan declared land in some milestone? A per-milestone critique sees one milestone's diff, so
   it cannot answer that.

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
     <repo>   pushed to <default>   <N> commits   <base>..<head>

     Quality gates: <results>
     Critique:      <N> findings, <M> presented, <model> · <effort> per critic, as it ran
     Integration:   <N> findings, <M> presented, <model> · <effort> per critic, as it ran
   ```

   Then the ledger, in the shape `/critique` defines. `Landed` carries no footer, because the
   run continues.

   **The last milestone's block carries the `Integration:` line and the integration ledger too.**
   Omit both on every earlier milestone, because step 8 ran nothing there.
10. **Tear down and clean up.** Do all three, in this order:
    ```
    stop any worker of this milestone that still runs, with TaskStop
    container: stop the stack and remove the worktree, per /worktree's teardown block
    set the milestone's status to landed in state.yml
    ```
    The branch lives on the remote once the push succeeds, so the worktree is disposable. A worker
    still running here would write into a tree that teardown removes. A `checkout` or `main` tree
    stays as it is, because it is yours, and the next milestone branches from there.

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

The worker's report is the record, and its first line says whether it escalated. The join writes
an escalated report to `reports/<m>/<task>.md`, so it survives this session. The wave join is the
only place an escalation appears. Resolve every escalation before the
milestone lands, or the run stops here.

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

Do not start the next wave until you resolve this. If the plan needs a change, update the plan
file so it stays the record of what the user actually agreed.

**Resume the escalated worker with `SendMessage`, carrying the decision.** It keeps everything it
read and found. Spawn a fresh worker only where the decision changes the task itself, and update
its task spec first.

Automated verification failing is not automatically an escalation — a worker that can fix it
within the plan's intent should. It escalates when the fix would require departing from the plan.

## Close

Close the run after the last milestone lands. Every milestone pushed its own PRs and tore down
its own worktrees, and step 9 reported the integration critique. Nothing here opens a PR.

1. Confirm no worker of this run still runs. Stop any that does, with `TaskStop`.
2. `git worktree prune` in each container, per `rules/agent-orchestration.md`.
3. Return each `checkout` or `main` repository to the branch it started on, where its tree is
   clean: `git -C "<checkout>" switch "<workspace.<repo>.start>"`.
4. Move `<state>/plans/<slug>/` into `<state>/archive/` whole. It has served its purpose, and
   once archived it no longer claims its branches.

**Close is silent.** Each `Landed` already carried its own PR URLs, quality gates, and ledger.
Repeat none of it here. `rules/chat-vocabulary.md` reserves five occasions, and a closing report
is a sixth. One line is the exception: say so when step 3 could not return a checkout, because
your folder is then not where you left it.

**The integration critique runs before this section, and that order matters.** It compares the
landed branches against the plan and reads its branches from `state.yml`. Archive the plan
first, and you remove both halves of that comparison.

## Notes

- Never commit to the default branch outside `main` mode; never push or open a PR without
  explicit approval
- If the plan turns out to be wrong, fix the plan and re-approve. Never let implementation
  quietly diverge from the approved record
