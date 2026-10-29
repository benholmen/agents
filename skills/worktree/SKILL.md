---
name: worktree
description: Cut, provision, and tear down one milestone worktree in a bare-plus-worktrees repository
when_to_use: >-
  When a milestone needs a working tree of its own, or when a closed milestone gives one back.
  Trigger phrases: "cut a worktree", "provision this worktree", "tear the milestone down".
  Also invoked by the implement skill, once per repository per milestone.
argument-hint: "[cut | provision | teardown] [container] [milestone] [branch] [base]"
---

# Worktree

Give every milestone worker its own working tree. Three modes: **cut**, **provision**, and
**teardown**.

A milestone loop needs this before it can run. A fresh worktree holds no `.env`, no
`auth.json`, no `vendor/`, and no `node_modules/`. It also cannot start a container stack
without colliding with the stack already running. Every gate in the corpus fails on an
unprovisioned worktree for reasons unrelated to the change.

`rules/agent-orchestration.md` carries the worktree standard. This skill implements that
standard and invents no second convention.

This skill refuses a repository that is not a container yet. `/bare-convert` sets one up, or
converts an existing clone, and it runs before the first cut.

## The layout

The container is the repository's own path, at whatever depth it sits.

```
<container>/                       the repository's own path
  .git/                            bare repository
  main/                            the user's stable worktree, never removed
  provision-worktree.sh            optional: a private provisioning script, never committed
  <plan-slug>-<milestone-slug>/    a milestone worktree
  <plan-slug>-<milestone-slug>/    a second milestone worktree
```

Every milestone worktree carries the plan slug as a prefix. The plan slug leads with a sortable
timestamp, so one plan's worktrees sort together and two plans never interleave. The stable
worktree keeps the name `main`, and it carries no prefix.

The branch carries the plan slug too: `<type>/<plan-slug>-<milestone-slug>`. Teardown keeps the
branch, and `/implement`'s close step archives the `state.yml` that names it. The prefix is
therefore what tells a resume from another plan's leftover. `rules/agent-orchestration.md` states
that reasoning once.

Every slug is lowercase, because it builds `COMPOSE_PROJECT_NAME`, and Compose rejects an
uppercase project name.

## Derive the container from any worktree

Every mode needs the container path, and this skill states the one derivation. Read it from any
worktree of that repository:

```bash
CONTAINER="$(dirname "$(git -C "<any-worktree>" \
  rev-parse --path-format=absolute --git-common-dir)")"
```

Two wrong derivations look right. `git rev-parse --show-toplevel` returns the worktree, so
`<container>/main` reaches a caller that wanted `<container>`. Cut mode then tests
`<container>/main/.git` for bareness, reads `false`, and refuses a converted container. Verified
on git 2.50.1.

`--path-format=absolute` is load-bearing. Without it `--git-common-dir` may answer the relative
`.git`, and `dirname` then returns `.`. Verified on git 2.50.1.

`/plan` records the container with this derivation, so the path it hands `/implement` needs no
repair.

## What the caller passes

Every mode takes the container, the milestone slug, and the branch. Cut alone takes the base,
because only cut creates anything.

```
<container>        the repository's own path
<milestone-slug>   the milestone slug, lowercase — the `[milestone]` argument
<branch>           <type>/<plan-slug>-<milestone-slug>, resolved by the caller
<base>             origin/HEAD, or the predecessor milestone's branch when the milestones stack
```

**Never rebuild the branch name here.** `<type>` is `feat`, `fix`, or `chore`, chosen for the work
per `rules/pr-first-contributions.md`. Only the caller holds that choice. Build the name here as
well, and the two constructions can differ. The next pass then reads a `state.yml` entry naming a
branch that does not exist. It takes the collision case, and escalates over its own branch.

Three more values follow from those four, and this skill states each derivation once:

```
<worktree>    <container>/ then <branch> with its <type>/ prefix removed
<plan-slug>   <branch> with its <type>/ prefix and its -<milestone-slug> suffix removed
<repo>        the basename of <container>
```

`/implement` resolves all four before it calls, and it passes them in the order above.

## Cut

Use this mode to create a milestone worktree and provision it.

Refuse a plain clone. Test the container itself, never `<container>/main`:

```bash
if ! git --git-dir="<container>/.git" rev-parse --is-bare-repository 2>/dev/null \
     | grep -qx true; then
  echo "error: <container> holds no bare repository" >&2
  exit 1
fi
```

Report that refusal to the user:

> **Blocked — `<container>` is not a container**
>
> - **Found:** `<container>/.git` is a plain clone, not a bare repository
> - **Needed:** the bare-plus-worktrees layout, per `rules/agent-orchestration.md`
> - **Next:** `/bare-convert convert <container>`
>
> ⏸ waiting on you: run /bare-convert convert <container>, or name another container

Test the branch and the recorded worktree path before you cut. `rules/agent-orchestration.md`
carries both tests, the three branch cases, and the escalation each one demands. Follow it rather
than a second copy here.

Then cut the worktree:

```bash
git -C "<container>/main" worktree add "<worktree>" -b "<branch>" "<base>"
```

Pass no `-b` on a resume, because the branch already exists. Where the recorded path already holds
this milestone's branch, reuse that worktree and cut nothing.

Report the path to the caller, which records it in its plan's `state.yml`, as the orchestration
rule requires. Then run provision mode against the new worktree.

**Provision mode can refuse, and cut then ends `Blocked` with the worktree standing.** Report that
refusal as provision mode writes it. The recorded path stays correct, so the retry reuses the tree
rather than cutting a second one.

## Provision

Use this mode to fill a worktree that already exists. Cut mode runs it, and you can run it again
after a lockfile changes.

**Resolve the provisioning script first.** The committed script wins. A private script at the
container root is the fallback, for a repository whose script the user keeps out of its history:

```bash
if [ -x "<worktree>/scripts/wt-provision.sh" ]; then
  SCRIPT="<worktree>/scripts/wt-provision.sh"
elif [ -x "<container>/provision-worktree.sh" ]; then
  SCRIPT="<container>/provision-worktree.sh"
else
  SCRIPT=""
fi
```

**Refuse a worktree that resolves no script.** Report that refusal to the user:

> **Blocked — `<repo>` carries no provisioning script**
>
> - **Found:** neither `<worktree>/scripts/wt-provision.sh` nor `<container>/provision-worktree.sh`
>   exists and is executable
> - **Needed:** a script that meets **The provisioning contract** below
> - **Next:** `/bare-convert script <container>`
> - **Kept:** `<worktree>`, so the script can land on this milestone's branch
>
> ⏸ waiting on you: run /bare-convert script <container>, or add the script yourself

**Keep the worktree and the branch here.** The cleanup below undoes a script that ran and failed.
A script that never existed leaves nothing to undo. Remove the tree, and the retry meets the same
absence, so the run loops instead of reporting.

**A milestone worktree is a checkout, so a committed script must sit on `HEAD`.** A script left
untracked in `<container>/main` reaches no worktree cut afterwards. Keep a private script at
`<container>/provision-worktree.sh` instead, which no checkout holds and no commit can carry.
`/bare-convert` states both.

```bash
"${SCRIPT}" "<container>/main" "<worktree>"
```

**Run the committed script from the target worktree, not from `main`.** Pass `main` as the
source argument only, which is the whole of its role. A milestone whose own branch updates the
script must run the updated one. A stacked milestone inherits its predecessor's version the same
way. The private script has one version, so every milestone runs it.

**Clean up after a failed provision.** The worktree and the branch both exist by then, so the
retry fails on two paths that are already taken:

```bash
git -C "<container>/main" worktree remove --force "<worktree>"
git --git-dir="<container>/.git" branch -D "<branch>"
```

Delete the branch only when this cut created it. A resume cut onto an existing branch, and that
branch carries work the remote holds.

## The provisioning contract

Each target repository commits its own script at `scripts/wt-provision.sh`. It takes the source
worktree and the target worktree as arguments:

```bash
scripts/wt-provision.sh <source-worktree> <target-worktree>
```

A user who keeps the script out of the repository's history puts it at
`<container>/provision-worktree.sh` instead. It takes the same arguments and owns the same
responsibilities. Provision mode prefers the committed script when both exist.

The script owns three responsibilities.

### Files

**Copy the machine-local files.** `.env`, `auth.json`, and certificates are untracked, so a
fresh worktree holds none of them.

**Clone the derived state, then reconcile it.** The reconcile re-runs the install. It is
mandatory rather than optional. A cloned `.terraform/` or `vendor/` can carry absolute paths
that point back at the source worktree. A cloned `node_modules/` matches whatever lockfile the
source held.

A clone alone is therefore unsafe. The clone gives you the speed, and the reconcile gives you
the correctness.

### Containers

**Publish no host ports.** Generate an override that resets the port list of **every** service
the base file declares. Read that service list rather than a fixed pair:

```bash
docker compose -f docker-compose.yml config --services
```

Emit one `ports: !reset []` entry per service into `docker-compose.worktree.yml`:

```yaml
services:
  <each service the command above printed>:
    ports: !reset []
```

`ports: !reset []` removes every published port on Compose v5.1.2, verified. Compose discards
the base port list rather than merging it.

An override that names a subset leaves the rest publishing. The second milestone stack then
fails to bind, and the gate fails for a reason unrelated to the change. Check the generated
override before you start anything:

```bash
docker compose -f docker-compose.yml -f docker-compose.worktree.yml config \
  | grep -c published
```

That count must be 0. Some repositories bind ports that no offset can move, and a shifted
published port breaks every URL the app generates. Removal is therefore the only safe answer.

**Run the gates inside the compose network.**

```bash
docker compose -f docker-compose.yml -f docker-compose.worktree.yml run --rm app <gate>
```

The compose network sits closer to production than a host-published port, which is what
`rules/testing-philosophy.md` asks for.

**Name the project explicitly.** Export
`COMPOSE_PROJECT_NAME=<repo>-<plan-slug>-<milestone-slug>`. Compose otherwise derives the
project name from the directory basename, verified.

The plan slug matters here, exactly as it does in the worktree path. Two live plans can
name a milestone `m1`, and `<repo>-m1` then gives both stacks one network and one volume set.
The worktree paths would stay distinct while the stacks merged.

### Each milestone stack is fully isolated

Its own containers, its own volumes, its own network, and no published ports.
`COMPOSE_PROJECT_NAME` gives one milestone one Compose project, and a project creates a container
for every service its base file declares.

Isolation therefore needs no naming convention inside the stack. Two milestones can hold a
bucket, a topic, or a database of the same name. Neither project can see the other's.

The milestone owns those volumes, which is why teardown removes them.

## The clone helper

Every provisioning script calls one shared helper, so many repositories do not grow many
dialects:

```bash
~/.claude/bin/wt-clone.sh "<source>" "<destination>"
```

It clones copy-on-write where the filesystem supports one, and it copies plainly everywhere
else. It reports the mode it chose, and it exits non-zero when the copy fails.

**It refuses a source holding a symlink that resolves outside the source root.** A pnpm-style
store keeps its internal links and clones fine. A `vendor/` directory holding a path repository
does not, and the helper names the link it refused. Run the reconcile alone for that source.

The helper checks the filesystem before it copies. `cp -c` on macOS falls back to a plain copy
without reporting it, and `cp --reflink=auto` does the same on Linux. A caller that expected a
clone would otherwise consume the full size of the source with no warning.

A clone costs time by file count rather than by bytes, and it consumes no space until the copy
diverges.

## Teardown

Tear the stack down at milestone close. Remove the worktree after the push succeeds.

```bash
COMPOSE_PROJECT_NAME="<repo>-<plan-slug>-<milestone-slug>" docker compose \
  --project-directory "<worktree>" \
  -f "<worktree>/docker-compose.yml" \
  -f "<worktree>/docker-compose.worktree.yml" down -v --remove-orphans
```

**Every path here is absolute, and that is load-bearing.** Teardown's callers reach this block
from somewhere else, and none of them sets a working directory. A relative `-f` then finds no
file, or it finds another repository's stack.

`down -v` removes the named volumes, and `--remove-orphans` removes a container that the
current file no longer declares. The milestone owns both, so neither removal reaches another
stack.

**Check that the tree holds nothing to lose, then force the removal.**

```bash
git -C "<worktree>" rev-list --count '@{upstream}..HEAD'
git -C "<worktree>" status --porcelain
```

The first must return 0, which proves the push carried every commit. The second must list only
paths the provisioning contract wrote. Stop and report any other line.

```bash
git -C "<container>/main" worktree remove --force "<worktree>"
```

**`--force` is mandatory here, not a fallback.** Plain `git worktree remove` refuses a tree
holding a modified tracked file, or an untracked file the repository does not ignore. The
generated `docker-compose.worktree.yml` is exactly such a file, so the plain form exits 128 on
the first provisioned repository. Verified on git 2.50.1.

`--force` removes the tree and the `worktree list` entry together, so teardown needs no prune.
The rule sweeps with `git worktree prune` at run close. The branch survives the removal, and it
lives on the remote once the push succeeds, so the worktree is disposable.
