---
description: Fan out with Solo agents, never a vendor's native sub-agent mechanism. Workers signal their own completion and report to a durable surface
---

# Solo agent orchestration

When you delegate work to a parallel worker, that worker is a **Solo agent**. Spawn it through the Solo MCP server. Never use the runtime's own sub-agent mechanism. That rules out Claude's Task tool, Codex's sub-agents, and any other vendor's in-process worker.

## Default policy

- **Default:** Every spawned worker is a Solo agent, launched with `spawn_agent`. This holds even for a quick read-only lookup.
- **Exceptions:** Only when the user explicitly asks for the vendor mechanism.
- **Solo unavailable:** Say so, then do the work inline or stop. This rule exists to prevent one failure: a fan-out that changed mechanism without telling anyone.
- **Scope:** This rule governs delegation, not every tool call. It applies to a fan-out from a skill, and to one from an explicit request. An explicit request looks like "check these five services in parallel". It also applies when you judge that a job splits. You do not fan out when you read a few files yourself.

## Why

Two reasons survive. Every claim in this section holds on 2026-09-19, against Claude Code 2.1.278.

| | |
|---|---|
| **A different runtime** | A Solo worker runs Codex, or any other runtime the roster holds. A Claude Code subagent runs Claude Code only. |
| **Longer than the turn** | A Solo process outlives the turn that spawned it. You inspect it, re-prompt it, or kill it later. A subagent returns a summary and then exits. |

**Do not argue from a capability a subagent now has.** A subagent takes `model`, `effort`, `permissionMode`, `maxTurns` and `isolation: worktree`. Named subagents message each other. Agent teams carry a mailbox file, a shared task list with file locking, and an automatic completion notification. Agent teams stay experimental, and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` turns them on.

## The shape

1. `list_agent_tools` — resolve the runtime. Use the runtime the plan pad's `Worker runtime:` line names, or the one the user named. Otherwise use the **host runtime**: the entry whose `tool_type` matches the runtime this session runs in. Where no enabled entry matches, or more than one does, stop with `Blocked` and list the enabled entries. Never ask, unless a skill asks for its own roster, as a standalone `/critique` does. Never hardcode a roster or an id.
2. `spawn_agent(agent_tool_id=<id>, name="<role>-<slug>", extra_args=[…])` returns `process_id` and `agent_instructions`. See **Capability, not compliance** for what belongs in `extra_args`.
3. Write the brief pad. See **The worker brief pad**.
4. `send_input(process_id, input=<pointer>)` — the pointer names the pad id. See **The pointer shape**.
5. The worker does its job, writes its report pad, and signals completion as its last act.
6. On the signal, read the report pad. Never scrape process output for content.
7. `close_process(process_id)` for every worker. A join that leaves processes open leaks them.

## The PTY ceiling

Every payload Solo injects into a PTY stays at or under 1,000 bytes. That covers a `send_input` body, a worker's completion body, and a guard body. Anything longer names a scratchpad and stops there.

The corpus recorded 802 `send_input` calls from 2026-08-23 to 2026-09-19. Fifty failed, or 8.35%. No failure occurred at or under 1,000 bytes. Claude workers lost 50 of 456 sends, and Codex workers lost 0 of 143. Short pointers lost 0 of 231. Solo reported `Sent 8848 bytes` for a send the worker received as 670 bytes. The loss therefore sits after Solo accepts the bytes, at a boundary this corpus does not isolate.

### The pointer shape

Put the pad id last, because a truncated message arrives as its tail.

```
You are Solo process <pid> (<name>) in project <project>, id <project id>.
Call whoami() first. If Solo MCP is unavailable, say so and stop.

Do nothing until you have read your brief in full. It carries your job,
your constraints, your reporting target, and your completion signal.

Read this scratchpad now, by id:
scratchpad_read(scratchpad_id=<brief pad id>)
```

**Address every pad by its id, never by its name.** `scratchpad_write` returns the id, and the id never changes. A title may follow it as a human-readable hint. The same holds for a guard pad and for a completion signal.

## The worker brief pad

Write the brief to a scratchpad, and send the pointer. One pad holds one worker's brief. A mid-run amendment edits that pad in place, so no second file accumulates.

`spawn_agent` returns `agent_instructions`. Paste them into `## Solo context`, or the worker never learns that it is a Solo agent.

The brief carries six sections, in this order:

```
  ## Solo context     the worker's process id, the project, and the whoami() instruction
  ## Objective        the one job, or a pointer to the todo that states it
  ## Boundaries       working directory, branch, declared paths, scratch directory,
                      what the worker must not touch, and what to do when stuck
  ## Tool guidance    the locks to take, and the prior waves to read
  ## Output format    the report pad, and the escalation marker
  ## Completion       the timer_set call, with the orchestrator's process id
```

**A brief pad, a guard pad, and a report pad carry no H1 heading.** Solo replaces the `name` you pass `scratchpad_write` with the content's first H1. Without one the name survives, which keeps the pad legible in a listing and resolvable by name. Two probe pads measured this on 2026-09-19.

**A worker without Solo MCP cannot read its brief pad.** Three Codex workers hit this, and their guards collected stdout instead. `whoami()` surfaces the failure first, before the worker starts the job. The pointer therefore calls `whoami()` first, and it tells the worker to stop when Solo is unavailable.

## Workers signal completion

A worker's last act wakes the orchestrator directly:

```
timer_set(delay_ms=1, delivery_process_id=<orchestrator process_id>,
          body="<task> complete, <clean|escalated>. Report in scratchpad <report pad id>.")
```

Solo rejects a zero delay, so `1` is the smallest legal value. The body obeys the ceiling, and the pad id sits last.

**Only the worker knows when it finishes.** Push the signal, and do not watch for its absence. The orchestrator receives completions rather than infers them.

Every worker brief therefore carries the orchestrator's own `process_id`, which `whoami` returns.

## Idle timers are the fallback, not the signal

`timer_fire_when_idle_all(processes=[<pids>], max_wait_ms=<guard>, body=…)` has one job. It catches the worker that dies, hangs, or never signals. Give `max_wait_ms` a real guard value.

**Treat every firing as a question, never as a verdict.** Of 35 firings in one corpus, 28 caught a worker still at work. Nine fired on a stale premise, because a watched worker signalled first.

Idle detection cannot do more than that, for three reasons:

- **There is no debounce.** The timer fires on the first detected idle transition. No parameter changes this. `timer_fire_when_idle_all` accepts only `processes`, `max_wait_ms`, `body`, `delivery_process_id`, `metadata`, and `project_id`. Solo ignores an unknown key silently rather than rejecting it.
- **A thinking worker looks finished.** Solo derives idle state from terminal output, and a worker that reasons at length emits none.
- **Solo treats an already-idle process as satisfied.** For `..._all`, a process that is already idle when you schedule the timer counts as satisfied. An entirely idle watch list returns `already_satisfied` and creates **no timer**. Schedule the timer immediately after `spawn_agent`, before the workers produce output, and you may never wake at all. For `..._any` the opposite holds: Solo ignores an already-idle process, and the timer waits for a new transition.

**Cancel the guard when the last worker signals.** `timer_fire_when_idle_all` returns a `timer_id`. Hold it, and call `timer_cancel(timer_id=<id>)` at the join. An armed guard still fires. It then arrives as a fresh turn about workers that finished long ago. Arm one guard, hold its id, and cancel it at the join.

### The guard pad

The guard body names a pad and obeys the ceiling. Write the branches into the pad, never into the body. Every line of the body reads correctly alone, and the pad id sits last.

```
Guard fired for <milestone>, wave <n>.
A worker that never signalled is a failure to investigate, not a completion.
Procedure: scratchpad_read(scratchpad_id=<guard pad id>)
```

The pad carries the watch list and one branch per outcome:

```
  opening               the guard fired, and this is a failure to investigate
  ## The watch list     one row per worker: process id, name, todo, report pad name
  ## Do this, in order  cancel every other guard, then read status and output,
                        then branch on running, exited, and idle with a pad
  ## Only then          the escalation sweep, and what the orchestrator may commit
```

**The watch list names each report pad, because no id exists yet.** The worker writes that pad after you arm the guard. It writes the pad with no H1, so the name you assigned survives. A guard that fires resolves the id from the name with `scratchpad_list`.

## Capability, not compliance

`spawn_agent` takes `extra_args`. Solo appends these per-launch arguments to the resolved command. They do not change the agent tool's saved defaults. Three uses matter.

**Match the worker to the job.** Set the model and the reasoning effort per worker. A worker does not inherit them from the session. A mechanical edit against precise line references is one job. A rewrite that must preserve a behavioral contract is another. The two should not cost the same.

**Launch every worker in auto-approval mode.** Each runtime fixes the mode. It is not a per-wave judgment call. Auto-approval lets a worker work through ordinary steps without stalling on a prompt. A reviewer still sees the requests that matter. A bypass mode removes that review from a process that runs unattended, which is the exact situation review exists for. A read-only assignment is not an exception. A worker's brief says what it intends to do, not what it is able to do.

**Read the runtime's adapter before you spawn it.** `list_agent_tools` returns a `tool_type` for each runtime. Read `references/runtime-<tool_type>.md`, which maps every policy in this rule to the argument that implements it. Each runtime names its own flags and renames them between releases, so never write a launch argument from memory.

**An adapter also records what its runtime cannot do.** A policy here is a requirement, not a promise that every runtime can meet it. A runtime may have no way to express one of them, and the adapter says so. Read it before you rely on a guarantee.

**Escalate a launch failure. Never loosen a flag.** When `spawn_agent` fails, read the runtime's adapter, correct the arguments, and retry once. When the second attempt fails, stop and escalate. Never relax a sandbox, drop a deny list, or reach for a bypass mode to make a launch succeed. Escalation is the terminal action, and this rule offers no fallback below it.

One session already paid for this. The third spawn attempt abandoned `spawn_agent` and launched Codex directly. It used the exact bypass flag this rule and `references/runtime-codex.md` both prohibit by name. Nothing told the retry loop when to stop, so the loop found the prohibited flag on its own.

**Bound a worker's writes by whether it edits the target.** Two classes exist. An immutable-target worker reads the target and writes only scratch. An editing worker changes the target, and its working directory is its milestone worktree. One posture does not fit both. Decide the class first, then read the runtime's adapter for the arguments.

**The immutable-target worker.** Every critic, every research agent, and every retro agent is one. It writes only its own scratch directory, it reads the whole disk, and it never writes the target.

**Derive the scratch directory once, here.** A worker's scratch directory is `<the session scratchpad directory>/<worker name>`, where `<worker name>` is the `name` you pass `spawn_agent`. Create it before you spawn, because a launch argument cannot name a path that does not exist. Every worker gets its own, so two workers never overwrite one file.

**Name that path in the brief of any worker that writes a file.** Each adapter names the argument that bounds writes to that directory. An editing worker needs the path too, because a verification proof mutates a copy rather than the target. A worker that writes only its Solo scratchpad needs no path.

**Both runtimes bound a worker's writes by directory.** Claude Code ships a Bash sandbox that the operating system enforces. `sandbox.filesystem.allowWrite` and `denyWrite` name the writable paths, for every Bash command and its child processes. Codex scopes writes to its working directory. **Codex also keeps `/tmp` and `$TMPDIR` writable.** Every worker's scratch directory lives there, so `workspace-write` does not isolate one Codex worker's scratch from another's. A target under a temp root loses this posture's protection too. Each adapter carries the arguments and the date of its last measurement. This paragraph holds on 2026-09-19, against codex-cli 0.155.1 and Claude Code 2.1.278.

Two limits survive on Claude, at the same version and date:

- **Read, Edit and Write bypass the sandbox.** They use the permission system instead, so a tool deny list still governs them.
- **A linked worktree keeps `.git` writable.** The sandbox allows writes to the main repository's shared `.git`, so it does not deny git.

**The editing worker.** A sandbox that permits its edits permits `git add` in its milestone worktree. No directory-scoped posture denies git there. A per-command deny list does, where the runtime scopes one to a single worker.

Where no runtime in the roster can, the denial does not exist. **Disclose the gap rather than restate the promise.** Name the runtime that cannot enforce it, and name the exposure. Two workers in one tree cross-commit each other's work, silently, and the undo costs a lot of time. Give each worker its own tree, or accept the risk knowingly and say so.

**Carry the invariant preamble once, where the runtime allows it.** Two things are identical across every worker in a wave. They are what a worker must not touch, and what to do when stuck.

The working directory is not one of them. A milestone that spans repositories cuts one worktree per repository. **A task receives one preamble per repository it writes in.** Each one names that repository's own worktree, and it scopes the task's declared paths to that repository. Most tasks write in one repository and take one preamble. A `same-worker` task may span two, and it then takes two. A runtime with a system-prompt argument takes the preamble there. That shortens each `send_input` and makes the constraints harder to drop by accident. A runtime without one carries the preamble in the brief pad's `## Boundaries`. `send_input` still carries the pointer alone.

## One worktree per milestone

A worker never shares a working tree with the user. Cut one worktree per milestone and per repository. Cut it from a bare-plus-worktrees layout, and use these paths:

```
  container          <the repository's own path>                 at whatever depth it sits
  bare repo          <container>/.git                            `git rev-parse --is-bare-repository` returns true
  stable             <container>/main                            the user's worktree, never removed
  worktree           <container>/<plan-slug>-<milestone-slug>    one plan's worktrees sort together
  branch             <type>/<plan-slug>-<milestone-slug>         the plan slug keeps two plans off one branch
  example container  ~/Code/jahnkelabs/agents
  example worktree   ~/Code/jahnkelabs/agents/<plan-slug>-<milestone-slug>
  create             test the branch and the path, then cut:
                       git worktree add <worktree> -b <branch> <base>   no such branch yet
                       git worktree add <worktree> <branch>             the branch already exists
                       reuse <worktree>, cut nothing                    the path already holds <branch>
                     base = origin/HEAD, or the predecessor milestone's branch when stacked
  record             kv_set plan:<slug>:milestone:<m>:worktree:<repo>
  remove             at milestone close, after a successful push
  sweep              git worktree prune at run close
```

The milestone slug is lowercase, because the KV key carries it. The `record` key carries the repository too, because one milestone cuts one worktree per repository. Without it the second cut overwrites the first, and teardown then leaks a worktree with its stack still running.

**Test the branch and the path before you cut.** `git worktree add -b` fails outright when the branch already exists. `git worktree add` fails the same way when another worktree already holds the path. Run both tests, because a stopped run can leave either one behind.

**The branch test has three cases, and this plan's own KV record tells them apart.**

- **A resume.** `plan:<slug>:milestone:<m>:branch:<repo>` already names this branch. Teardown removed the worktree and left the branch behind, so re-cut onto it. Pass no `-b`: `git worktree add <worktree> <branch>`.
- **A closed plan's leftover.** No KV key claims the branch. `gh pr list --head <branch> --state merged` returns a merged PR, or the remote no longer carries the ref. That plan finished, and its close step deleted the KV that named the branch. Delete the branch and cut fresh. `rules/pr-first-contributions.md` carries this test under `## Branch staleness check`.
- **A collision.** No KV key claims the branch, and no merged PR explains it. Another live plan owns it. Rename this plan's milestone, and escalate. Renaming the other plan's branch breaks its open PR.

**The branch carries the plan slug because teardown outlives the KV record.** Teardown keeps the branch, and a plan's close step deletes every `plan:<slug>:*` key. Drop the prefix, and a second plan that reuses a milestone slug finds a branch no KV key claims. It then escalates over a PR that merged and closed. `/implement` labels milestones `m1`, `m2`, and `m3`, so that is the common case rather than the rare one.

**Test the recorded worktree path too.** `plan:<slug>:milestone:<m>:worktree:<repo>` holds it, so this costs one `kv_get`. Where the path exists and holds this milestone's branch, reuse it and cut nothing. Where it exists and holds anything else, stop and report both paths. `/stash` leaves a worktree standing on unpushed commits and on uncommitted work. A stashed plan therefore resumes onto a path another worktree still holds, and `git worktree add` exits 128 there.

A milestone slug is therefore unique inside its plan. The plan slug separates it from every other plan's.

A plain clone fails loudly. Test the layout before you cut anything, and print the conversion command rather than a worktree path.

The worktree is disposable once the push succeeds, because the branch then lives on the remote. Remove it at milestone close.

A worker's working directory is a worktree, so its lock keys carry that worktree's path. A worker writing in two repositories has two, and each file locks under the worktree that holds it.

**Why a worktree.** The user sits on a branch in their own tree. A worker that cannot take that branch cannot trample the user's working state. Git refuses to check out one branch in two worktrees, so the guarantee is structural rather than requested.

**The safety comes from the worktree, not from the bare repository.** A plain clone that adds worktrees beside it earns the same guarantee. This standard still requires the bare layout, for symmetry and grouping. Every tree is a peer, and one container holds them all.

## Every worker prompt carries

Split what you send by what varies.

Pass the **preamble** through the runtime's system-prompt argument, or in every prompt where the runtime has none. It carries the working directory as an absolute path, with an instruction to stay inside it. That path names one repository's worktree. A task writing in two repositories therefore receives two preambles, one per repository. Its lock keys come from the matching worktree.

The preamble names what the worker must not touch: git writes, undeclared paths, todos it does not own, and KV. It also says what to do when stuck, which is to record what it found and stop. A worker that improvises past its brief is the expensive failure. A worker that stops behaves correctly.

The **assignment** lives in the brief pad, and `send_input` carries only the pointer. It names the one job this worker owns and where to write its report. It also carries the orchestrator's `process_id`. A todo or a work item may already state the job. The brief then points at it rather than restating it.

**Check whether the worker already has the rules.** A runtime that loads these rules on its own makes restating them in a prompt a waste. A runtime that does not means every rule the worker must follow reaches it only through its prompt. The adapter says which, and it names the path that runtime reads. Assume nothing here: a worker that silently lacks a constraint you believe it has is the failure this check prevents.

Workers do one job and report. The orchestrator owns git, todo lifecycle, KV, and the synthesized artifact.

## Locks and reports

**Take a lock only where a second writer may exist.** Decomposition gives every worker in a wave a disjoint file scope, so workers in one wave never contend. Across 700 acquisitions in four weeks, no acquisition failed on contention. The machinery cost 94 failed calls, 147 malformed keys, and 53 locks nobody released. Lock a file when a second orchestration run, or a person, may edit the same tree. Otherwise take no lock.

**A lock key is the absolute path, lowercased.** The shape is `path:/absolute/path/to/the/file`. Solo scopes a lock to the project, and one project holds many repositories. A relative key such as `path:readme.md` therefore collides across repositories. Solo rejects an uppercase key outright, in a lock key and in a KV key.

**Reports go to scratchpads.** Solo splits the two surfaces. Todos carry ownership, blockers, locks, and state. Scratchpads carry findings and reports. Give each worker one report pad. Run `scratchpad_find` for the escalation marker across all of them before you read any in full.

**`scratchpad_edit` takes a target object, never a bare string.** The two legal objects are `{"type": "section", "section_heading": "<heading>"}` and `{"type": "line_range", "offset": <n>, "limit": <n>}`. Across one corpus of 210 calls, 37 malformed the target. Nineteen passed `null` or omitted it, thirteen passed a bare string, and four passed an object with no `type`. One invented a type, and the call failed outright.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| Vendor sub-agent for fan-out | It runs only the session's runtime, and it dies with the turn that spawned it |
| "Spawn N parallel agents" with no mechanism named | The runtime uses its own default, so name `spawn_agent` explicitly |
| Workers running git writes in a shared tree | `git add` from two workers cross-commits their work |
| A tool deny list treated as a sandbox | Without the Bash sandbox, `cat > <target>` still writes the target through the shell |
| An inline brief over 1,000 bytes | Claude workers lost 50 of 456 sends, and a truncated brief loses its head |
| A pointer that names the pad id first | Truncation keeps the tail, so the pad id goes last |
| A pointer that addresses a pad by its title | Solo renamed the pad to its first H1, so the title resolves nothing |
| An H1 heading in a brief pad or a guard pad | Solo overwrites the name you gave the pad, and a listing then loses it |
| Cutting a milestone branch with `-b` and no existence test | A resumed run fails outright, because teardown left the branch behind |
| Cutting onto a recorded worktree path with no existence test | `/stash` leaves the worktree standing, so `git worktree add` exits 128 |
| Treating an idle timer as the completion signal | No debounce, and a thinking worker looks like a finished one |
| Scheduling an idle timer before workers produce output | An all-idle watch list returns `already_satisfied` and creates no timer |
| A guard body that carries the branches inline | It exceeds the ceiling, and the orchestrator wakes to a truncated instruction |
| Reading a worker's result from process output | Rendered rows, capped and wrapped: fine for a sentinel, incomplete for a report |
| Every worker at the session's model and effort | A one-line edit and a contract-preserving rewrite are not the same job |
| Spawning without an explicit approval mode | The runtime default is a prompt nobody watches, and the worker stalls unattended |
| Reaching for a runtime's bypass mode | Removes review from the one process nobody watches |
| Loosening a flag after a failed spawn | The retry loop reaches a bypass mode instead of escalating |
| A worker sharing the user's working tree | The worker edits the tree the user sits in, and their working state is collateral |
| A lock on every file a worker touches | 700 acquisitions produced no contention failure and 94 self-inflicted ones |
| A `scratchpad_edit` target outside `section` and `line_range` | The call fails, and the report never reaches its durable surface |
