---
name: critique
description: Adversarially review a diff, plan, files, or PR using multiple models as independent critics
when_to_use: >-
  When the user wants work torn apart rather than surveyed. Trigger phrases: "what is wrong
  with this", "review this adversarially", "find the bugs", "critique my plan". Also invoked
  by the plan and implement skills.
argument-hint: "[target]"
---

# Critique

Try to break something. This is not a survey — each worker must find what is wrong. A finding
must survive scrutiny before it reaches the user.

This skill runs standalone. `/plan` calls it on a draft plan, and `/implement` calls it on a diff.

## Step 1 — Resolve the target

| `$ARGUMENTS` | Target |
|---|---|
| *(empty)* | the working tree diff; falls back to `<default>...HEAD` — resolved from `origin/HEAD`, never hardcoded — if the tree is clean |
| a plan file, or a plan slug | a draft plan |
| `--roster` | `/implement`'s proposed decomposition — grouping, waves, and tiers, before anything spawns |
| one or more paths | those files |
| `--pr <N>` | that pull request (`gh pr diff <N>`) |
| `--base <ref>` | diff against that ref instead |
| `--integration <slug>` | every landed milestone of that plan, together |
| `--plan <file>` | modifier — pairs an approved plan with the target the other arguments resolve |

State what you resolved before you proceed. If the target is empty — clean tree, no changes —
say so and stop rather than reviewing nothing.

`--plan` resolves no target of its own, and it carries the plan the fidelity lens checks against.
`/implement` always passes it. Resolve the plan file before you spawn anything. A plan you cannot
read is a stop, never a silent drop — see step 3.

`--integration` is the only target that takes the integration lens set. `/implement`'s milestone
loop is its caller, and it calls once the last milestone has pushed.

**Resolve `--integration <slug>` before you spawn anything.** No other target names its refs
indirectly, so this is the one target you assemble:

1. Read `<state>/plans/<slug>/state.yml`. Each `milestones.<m>.repos.<repo>` entry names one
   branch and the base its milestone cut from. An entry from `/implement`'s `main` mode also
   names `head`, the commit it pushed, and its branch is the default branch. `/implement`
   archives that directory at Close, which runs after this pass.
2. Take each repository's container path from the plan's `**Repos**:` line. `--plan` carries the
   plan, and `/implement` always passes it.
3. Fetch, then diff each branch against its own base:
   ```bash
   git --git-dir="<container>/.git" fetch origin
   git --git-dir="<container>/.git" diff <base>..<branch>
   ```
   That base is `origin/HEAD`, or the predecessor milestone's branch where the milestones stack in
   that repository. One ref cannot serve two repositories that stack differently. Where an entry
   names `head`, diff `<base>..<head>` instead, because later milestones moved its branch on.

The target is every one of those diffs together. **Use the repository's git directory, never a
worktree.** `<container>/.git` is the bare repository when converted and the ordinary `.git` in a
plain clone. An earlier milestone's teardown removed the worktree of every repository the last
milestone did not touch. A git directory reads a branch without a checkout, so it reaches all of
them.

Stop and say so where an entry is absent, or where a branch does not resolve. A partial target
answers `Plan completeness` wrongly, and that lens is why this pass exists.

**Resolve the critique directory here.** Every critic reads its target from it, and every
headless critic writes its output there. `<state>` is the state directory
`rules/agent-orchestration.md` defines.

```
  under a plan     <state>/plans/<slug>/critique/<segment>/
  standalone       <state>/critique/<slug>/<segment>/

  slug        the plan's slug. Where no plan resolved, a lowercase slug of the target:
              `pr-42`, `working-tree`, or the path with `/` as `-`
  segment     the milestone `/implement` is shipping, plus the repository name where that
              milestone spans more than one; `integration` for `--integration`; `roster` for
              `--roster`; `standalone` otherwise
```

`/implement` calls this skill once per repository per milestone, and once more after the last one
pushes. The repository belongs in the segment for the same reason the milestone does. Two
repositories in one milestone would otherwise write one directory twice.

Write the resolved target into that directory as `target.diff`, or `target.md` for a plan or a
roster. A critic then reads one file rather than re-deriving refs.

A roster is a real target, because an approved artifact has its own failure modes. The roster
fidelity lens in step 3 names them.

## Step 2 — Choose the models

Always ask, unless the caller already supplied a roster.

A roster entry is `claude:<model>` or `codex[:<model>]`. Claude is the host, so a Claude entry
runs as a `critique-worker` subagent. A Codex entry runs headless, and it needs the `codex`
binary. Check for it with `command -v codex`, and offer it only where that succeeds. Omit a Codex
model to take the default from `~/.codex/config.toml`.

**The default roster is one Claude critic and one Codex critic:** `claude:<the session's model>,
codex`. Recommend it whenever `codex` is present. Two runtimes miss more different defects than
two models of one runtime. Two critics also give the agreement signal, so the run needs no
refutation pass. Where `codex` is absent, fall back to the Claude critic alone, and say that the
refutation pass then stands in for agreement.

**Deciding — the critique roster**

```
found:        claude (host), codex <present | absent>
decision:     each model misses different defects, and only you know the budget
default       claude:<model>, codex: one critic per runtime, and cross-model agreement
one           claude alone: cheaper, and a refutation pass stands in for agreement
more          a second Claude model: more coverage, at one more critic's cost
```

Which models should critique this? I recommend `claude:<model>, codex`, because one critic per
runtime finds the widest spread of defects for two critics' cost.

⏸ waiting on you: name the models for this critique

Each model misses different defects, which is the point. Independent critics find more defects
than one critic that you run repeatedly. A Claude model beside a Codex model is more independent
than two Claude models.

When `/plan` or `/implement` calls this skill, it already chose the roster. Use that roster, and
do not ask again.

**One roster serves a whole run.** `/implement` chooses it once, then reuses it for every
milestone critique and for the integration pass. Two milestones critiqued by different rosters
produce findings nobody can compare.

## Step 3 — Pick the lenses

Two lens sets exist. **The per-target set is the default**, and it serves every target step 1
resolves. The integration set serves `--integration` alone. Run one set, never both.

### Per-target lenses

| Lens | Applies when | Question |
|---|---|---|
| **Plan fidelity** | `--plan` resolved a plan | Does this target do what its slices approved — and nothing more? Did the work quietly skip, expand, or substitute anything? |
| **Roster fidelity** | the target is `--roster` | Do two tasks overlap on a file and race? Did the grouping drop a `same-worker` constraint? Does a tier match the work it carries? |
| **Correctness** | always | Where does this produce a wrong result? Give concrete inputs and the wrong output. |
| **Edge cases** | always | Empty, null, concurrent, oversized, malformed. What does the code not handle? Which error path has no test? |
| **Security** | the target touches auth, input handling, secrets, permissions, or shells out | What is exploitable? |

Correctness, edge cases, and security read a draft plan as readily as a diff. A plan that
specifies a wrong result carries a correctness defect.

**Plan fidelity drops silently only when the caller offered no `--plan`.** A standalone
`/critique src/foo.php` has nothing to check fidelity against. When a caller offered `--plan` and
the plan does not resolve, stop and say so. Never drop the lens quietly on a plan you cannot read.

### Integration lenses

`--integration <slug>` selects this set, and nothing else does. Each question needs more than one
milestone's diff to answer.

| Lens | Question |
|---|---|
| **Cross-milestone contract drift** | Does a caller one milestone changed still match a callee another milestone changed? |
| **Plan completeness** | Did every slice the plan declared land in some milestone? |
| **Claim consistency** | Do two milestones state one fact two ways? |
| **Stack coherence** | Do the branches stack in the order the milestones shipped? |

**The integration pass may not raise a finding that lives wholly inside one milestone's diff.**
The per-milestone pass already ran that finding through the filter, and the user already decided.
Drop it rather than present it. One run had to drop a finding by hand as
`re-litigating the disabled-step export semantics, which you and I already settled`.

**No question appears in both sets.** Plan fidelity asks whether one target matches its own
slices. Integration completeness asks whether every slice landed somewhere. Neither question
answers the other.

## Step 4 — Run the critics

Run one critic per roster entry, each running all applicable lenses over the whole target. Follow
`rules/agent-orchestration.md`. Every critic is a read-only worker, at effort `high` or above,
because this is judgment work.

Write the brief once, to `brief.md` in the critique directory. Every critic gets the same brief:

```
  ## Objective       review the target adversarially. Name the target file in the critique
                     directory, the applicable lenses (step 3), and the approved plan's path, or
                     "none"
  ## Boundaries      the repository the target belongs to; the target is immutable
  ## Tool guidance   read the target file first, then whatever code it touches
  ## Output format   one finding per defect, in the shape of
                     ~/.claude/references/critique-findings.schema.json
```

**Give each critic only the target and the approved plan, not the reasoning behind them.** A
critic that already knows why the code is good is no longer a critic. That is why a critic is a
fresh subagent, never a fork.

Start every critic in one message, so they run concurrently:

```
Agent(subagent_type="critique-worker", description="critique <model>", model=<model>,
      effort=<high or above>, prompt=<the contents of brief.md>)

Bash(run_in_background=true, command=<the command in references/runtime-codex.md>)
```

**Never write a headless launch argument from memory.** Read `references/runtime-codex.md`
before you start a Codex critic. It carries the command, the version it was measured against, and
what a failed run looks like.

**Where the target stays writable, say so in the brief rather than assert a denial.** A
`critique-worker` cannot write, and a Codex critic runs in a read-only sandbox. On a Codex host, a
subagent critic is read-only by request alone, per `rules/agent-orchestration.md`.

Wait for every critic's completion notice. A subagent's notice and a background command's exit
notice both count. Never poll.

## Step 5 — Merge

Read each critic's findings: the fenced `json` block that ends a `critique-worker`'s final
message, and `codex.json` for a Codex critic. A critic whose `blocked` is non-empty did not finish.
Say so in the ledger, and merge what it did report.

Match findings that describe the same defect at the same location, even when the wording differs.

**Cross-model agreement raises confidence, and it drops nothing.** Every merged finding enters
step 6, whether one critic found it or every critic did.

**Agreement cannot gate the merge, because each model misses different defects.** That is why the
roster holds more than one. A finding one critic found alone carries no agreement. Nothing refutes
it either, because the refutation pass below covers a one-model roster only. Gating on agreement
discards exactly the findings a multi-model roster exists to produce.

**Agreement is no evidence in the other direction either.** Step 6's criteria decide what reaches
the user, and none of them names agreement. `1b15feba` finding 1 carried three-model agreement,
and the user delegated it anyway. Two two-model findings turned out to be no findings at all.

**When the roster holds one model**, no agreement signal exists at all. Run a refutation pass
instead. Spawn one `refute-worker` per finding, all in one message, and give each one the
finding, the target file, and the plan. It defaults to refuted when it is uncertain. Drop what it
refutes.

## Step 6 — Filter, then escalate what the user must decide

You decide almost every finding yourself. Six criteria escalate a finding to the user, and three
grounds never do. The ledger discloses every decision either way.

**Default: fail toward accepting.** Accept any finding that matches no criterion below.

Real runs back this default. Serial triage cost about 115 human turns across 8 runs for about
176 findings. Delegated triage cost about 20 turns across 14 runs for about 260.

**What acceptance does depends on who called.** A standalone critique reports the remedy and edits
nothing, because the request covered a review only. `/critique --pr 42` that rewrites the local
tree exceeds what the user asked for. When `/implement` calls on a milestone diff, apply each
accepted fix before that skill re-verifies and pushes.

**An `--integration` pass reports the remedy and edits nothing, whoever called it.** Every
milestone it reviews already shipped its PRs. A finding against M1 cannot land on M1's branch. That
branch already carries an open or merged PR. Write it into whatever tree stands open, and M1's fix
lands on another milestone's branch.

Never write an integration remedy into the user's own checkout. `rules/agent-orchestration.md`
keeps a worker out of the user's tree unless the user chose it for a milestone, and
`pr-first-contributions` forbids an unrequested commit on the default branch. An
accepted remedy therefore lands as a follow-up milestone, and `/implement` proposes one.

### The six criteria

Each criterion is a test you apply to one finding. Escalate only on a yes.

- **C1 — the fix rests on a fact you cannot verify.** Check the premise before the remedy.
  `cc3da3e8` 5/26 asserted `No ECR tag exists`, and that premise was false.
- **C2 — the fix needs the user to act outside the repository.** `ee524d20` 4/11 committed the
  user to `handle the tagging and release`.
- **C3 — the fix is irreversible, or visible outside the repository.** The fix at `ee524d20`
  8/11 read `Push it`.
- **C4 — the fix changes a default posture.** The user answered `cc3da3e8` 22/26 with
  `I'd rather start with strict rule enforcement`.
- **C5 — the fix changes who decides, or who merges.** The user answered `ee524d20` Security 3/3
  with `You MUST open a PR and allow me to review and merge it myself`.
- **C6 — two or more fixes exist, and you cannot rank them on stated grounds.** A genuine tie
  only.

**C6 covers a genuine tie and nothing wider.** When you can argue for one fix, take it and
disclose the alternative in the ledger. `More than one plausible fix exists` holds for roughly a
third of findings, and that reading would rebuild serial triage.

### The three anti-criteria

Each one is a prohibition. Never escalate a finding on one of these grounds.

- **Severity `nit`.** The corpus presented 16 nits and fixed 16. The user questioned none.
- **Cross-model agreement.** `1b15feba` finding 1 carried three-model agreement, and the user
  delegated it anyway. Two two-model findings turned out to be no findings at all.
- **A verifiable mismatch between two artifacts with one mechanical fix.** The user accepted
  about 60 of about 120 individually presented findings with a single word.

### The ledger

Report one line per decision, ranked by criticality. Criticality means a wrong result outranks a
plausible failure, which outranks a nit.

```
Ledger — <target> (<models>)

  bug    `src/token.php:88`   refresh drops the retry budget
         fixed: threaded the budget through the call
         declined: reset it in the caller — the caller cannot see the ceiling

  risk   `src/auth.php:12`    the 401 path retries without a bound
         fixed: bounded the loop

  nit    `src/auth.php:40`    `$tok` shadows the outer binding
         fixed: renamed it to `$refreshed`
```

Carry the declined alternative wherever more than one fix existed, and give its reason in one
clause. Omit that line where only one fix existed.

The `fixed:` line reads `remedy:` wherever the run applied nothing. That covers a standalone
critique and every `--integration` pass.

**The ledger is the only surface where a remedy choice stays correctable.** C6 escalates a
genuine tie alone, so every other choice between two fixes reaches the user here.

**A ledger with nothing critical in it carries no reserved heading.** Report it and stop.
`rules/chat-vocabulary.md` reserves a heading for a message the user must act on. A ledger of
accepted findings asks for nothing.

### Escalate one finding per message

Take the most critical first. `rules/chat-vocabulary.md` forbids two questions in one message.
The filter keeps the escalated count low, which is what makes one question per message
affordable.

C1 through C5 carry a proposal you already formed, so each takes `Approve`. C6 carries options
you cannot rank, so it takes `Deciding`. A C6 recommendation names the ground it rests on,
because the stated grounds do not rank the two fixes.

```
**Approve — `src/token.php:88`**

  found:      refresh drops the retry budget — C1, the ceiling is unverifiable
  decision:   the fix assumes a ceiling of 3, and no code in the repository states one
  fix it      threads the budget through the call, on an assumed ceiling
  drop it     three consecutive 401s retry forever

Fix it as proposed, or drop it? I recommend fixing it.
```

⏸ waiting on you: fix `src/token.php:88` as proposed, or drop the finding

Every finding carries a severity — `bug` (wrong behavior), `risk` (plausible failure), `nit`
(style, naming, cleanup). Severity ranks the ledger, so never drop it from a line.

`/critique` owns the filter, the ledger, and this presentation. `/plan` and `/implement` receive
the ledger rather than the raw findings, so nobody triages a finding twice.

The critique directory keeps the target, the brief, and each headless critic's output. Leave it
in place. It moves to `archive/` with its plan.

If nothing survives, there is no ledger and no decision to request. Report the action alone —
one line, no findings block, no closing question:

```
Critique of <target> (<models>) — nothing survived. 4 findings raised, all refuted.
```

A clean critique is a real outcome, not a failure to try hard enough.
