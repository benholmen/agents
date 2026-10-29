---
name: bare-convert
description: Set up or convert a repository into the bare-plus-worktrees layout that /implement's container mode uses
argument-hint: "[set-up | convert | script] [url or clone path]"
disable-model-invocation: true
---

# Bare convert

Turn a repository into a container, so `/worktree` can cut a milestone tree inside it. Three
modes: **set up**, **convert**, and **script**.

Set up clones a repository this machine does not hold yet. Convert rewrites a clone you already
work in, and it preserves uncommitted work. Convert is the destructive mode. It moves the tree
you work in, so it reports every path before it acts.

Script writes the repository's provisioning script, or updates one that went stale. Set up and
convert both end there. Run it alone against a container that already exists.

`rules/agent-orchestration.md` carries the worktree standard. This skill implements that
standard and invents no second convention.

`/worktree` owns cut, provision, and teardown, and it defines the provisioning contract. This
skill writes the script that satisfies that contract. It reads the definition there rather than
restating it.

## The layout

The container is the repository's own path, at whatever depth it sits.

```
<container>/                       the repository's own path
  .git/                            bare repository
  main/                            the user's stable worktree, never removed
  <plan-slug>-<milestone-slug>/    a milestone worktree
```

## Set up

Use this mode for a repository that this machine does not hold yet.

```bash
git clone --bare "<url>" "<container>/.git"
git --git-dir="<container>/.git" config remote.origin.fetch \
  '+refs/heads/*:refs/remotes/origin/*'
git --git-dir="<container>/.git" fetch origin
git --git-dir="<container>/.git" remote set-head origin --auto
DEFAULT="$(git --git-dir="<container>/.git" symbolic-ref refs/remotes/origin/HEAD \
  | sed 's@^refs/remotes/origin/@@')"
git --git-dir="<container>/.git" worktree add "<container>/main" "${DEFAULT}"
```

A bare clone sets no fetch refspec. Without one, `origin/HEAD` and every other
remote-tracking ref stays absent, and cut mode reads `origin/HEAD` for its base.

Then run `## Script` below. The container is not ready until that step finishes.

## Convert

Use this mode to turn an existing clone into the layout. It preserves uncommitted work.

### Preflight everything first

Run every check below before the first move. Each one is cheap. A failure after the first move
leaves the tree somewhere the user did not put it.

The block also resolves `<staging>`, the directory holding the record this convert verifies
against. `<staging>` sits beside `<clone>`, never inside it. The convert moves `<clone>`, so a
file inside it does not survive at a stable path.

```bash
test -d "<clone>/.git"                                  # a plain clone, not already converted
test ! -e "<clone>/main"                                # the destination name is free
test ! -e "<clone>/main-reg"                            # the registration name is free
test ! -e "$(dirname "<clone>")/.$(basename "<clone>").wt-convert"
STAGING="$(dirname "<clone>")/.$(basename "<clone>").wt-verify"
test ! -e "${STAGING}"                                  # the <staging> path is free
BRANCH="$(git -C "<clone>" symbolic-ref --short HEAD)"  # fails on a detached HEAD
```

Stop on any failure and report which check failed. A detached HEAD needs a named branch first,
because `worktree add` takes one.

### Report before you move anything

Print every absolute path that changes, and the uncommitted state you carry over. Change
nothing until the user approves. `rules/chat-vocabulary.md` gives the shape of that gate.

> **Approve — convert `<clone>` to a container**
>
> | | Now | After |
> |---|---|---|
> | Container | `<clone>` | stays at this path |
> | Your checkout | `<clone>` | `<clone>/main` |
> | Repository | `<clone>/.git` | `<clone>/.git`, with `core.bare true` |
> | Branch | `<branch>` | carried over, checked out at `<clone>/main` |
>
> **Carried over:** <n> modified, <n> staged, <n> untracked, <n> ignored
>
> Convert this clone?
>
> ⏸ waiting on you: approve this conversion, or name a different clone

### Record the state, then move

```bash
mkdir "${STAGING}"
git -C "<clone>" status --porcelain --ignored > "${STAGING}/dirt-before.txt"
```

`--ignored` is load-bearing. Without it the file lists no ignored path, and the verification
below then proves nothing about `vendor/` or `node_modules/`.

Move the clone under a container at its own path:

```bash
PARENT="$(dirname "<clone>")"; NAME="$(basename "<clone>")"
mkdir "${PARENT}/.${NAME}.wt-convert"
mv "<clone>" "${PARENT}/.${NAME}.wt-convert/main"
mv "${PARENT}/.${NAME}.wt-convert" "<clone>"
mv "<clone>/main/.git" "<clone>/.git"
git --git-dir="<clone>/.git" config core.bare true
```

Every placeholder above carries quotes, and so does every one below. A clone at a path holding
a space otherwise splits. `dirname` then receives two arguments, and `mkdir` asks for a name
holding a newline. The conversion aborts after the move already happened.

The working tree now sits at `<clone>/main`, and its content never moved. Register it as a
linked worktree:

```bash
git --git-dir="<clone>/.git" worktree add --no-checkout "<clone>/main-reg" "${BRANCH}"
rm -f "<clone>/main-reg/.git"
rmdir "<clone>/main-reg"
cp "<clone>/.git/index" "<clone>/.git/worktrees/main-reg/index"
mv "<clone>/.git/worktrees/main-reg" "<clone>/.git/worktrees/main"
printf 'gitdir: %s\n' "<clone>/.git/worktrees/main" > "<clone>/main/.git"
git -C "<clone>/main" worktree repair
```

The index copy carries the staged half of the uncommitted work. A new linked worktree starts
with an empty index, and without the copy every tracked file reads as deleted.

### Roll back a failed step

Each step below undoes the one above it. Run them in reverse order from the step that failed,
and report what you undid.

```
worktree repair          nothing to undo; re-run it
gitdir file              rm -f "<clone>/main/.git"
worktrees rename         mv "<clone>/.git/worktrees/main" "<clone>/.git/worktrees/main-reg"
index copy               rm -f "<clone>/.git/worktrees/main-reg/index"
worktree add             rm -rf "<clone>/main-reg"
                         then git --git-dir="<clone>/.git" worktree prune
core.bare                git --git-dir="<clone>/.git" config core.bare false
.git move                mv "<clone>/.git" "<clone>/main/.git"
container rename         mv "<clone>" "${PARENT}/.${NAME}.wt-convert"
clone move               mv "${PARENT}/.${NAME}.wt-convert/main" "<clone>"
mkdir                    rmdir "${PARENT}/.${NAME}.wt-convert"
staging mkdir            rm -rf "${STAGING}"
```

A full rollback returns the clone to its original path with its uncommitted work intact. Report
the path the user should find their tree at, whether the rollback ran to the end or stopped.

### Verify, then remove `<staging>`

```bash
git -C "<clone>/main" status --porcelain --ignored \
  | diff -u "${STAGING}/dirt-before.txt" -
```

An empty diff means the conversion kept the modified, staged, untracked, and ignored files.
Both status calls pass `--ignored`, so the diff covers all four kinds. Stop and report anything
else, and keep `<staging>` for the report.

Remove `<staging>` once the diff is empty:

```bash
rm -rf "${STAGING}"
```

Then run `## Script` below. The container is not ready until that step finishes.

## Script

Use this mode to write `scripts/wt-provision.sh`, or to update one that no longer matches the
repository. Set up and convert both end here. Run it alone when `/worktree provision` reports that
the repository carries no script.

Its one argument is the container path, which convert calls `<clone>` above.

`/bare-convert` runs per repository, and `/worktree` runs per milestone. A repository's own script
therefore belongs with this skill.

### Read the contract, then read the repository

`/worktree`'s `## The provisioning contract` states the script's arguments and its three
responsibilities. Read it there, and copy none of it here. Then ask the repository what it holds:

```bash
git -C "<container>/main" cat-file -e HEAD:scripts/wt-provision.sh   # committed already?
test -x "<container>/provision-worktree.sh"                          # kept private already?
git -C "<container>/main" status --porcelain --ignored               # machine-local and derived
test -f "<container>/main/docker-compose.yml"                        # a stack to isolate
```

Each answer decides one part of the script. An ignored file such as `.env` or `auth.json` is a
machine-local file to copy. An ignored directory such as `vendor/` or `node_modules/` holds
derived state to clone and reconcile. A base compose file means the script generates the port
override.

**A repository may need none of the three.** A documentation repository has no derived tree and
no compose stack. Its script validates its two arguments and exits 0. Write that, rather than
steps the repository does not need.

**A stale script is the same job.** Compare what the script copies against what the repository now
ignores. A dependency manager the repository added since, and a service the compose file gained,
both leave the script behind.

**Say so and stop where the script is present and current.** That is the common answer on a second
run, and it needs no gate.

### Propose it, then write it

> **Approve — write `<container>/main/scripts/wt-provision.sh`**
>
> - **Script:** absent (or: present, and stale — <what changed>)
> - **Copies:** <the machine-local files found>
> - **Derives:** <each derived directory, and the reconcile command for it>
> - **Compose:** <the base file, and the services its override resets> (or: none)
>
> Write this script?
>
> ⏸ waiting on you: approve the script, or tell me what this repository actually needs

**Ask about what the repository cannot tell you.** A reconcile command, a certificate path, and a
service nobody runs are all judgment. Propose an answer and let the user correct it.

Write the file, make it executable, and check that it parses:

```bash
chmod +x "<container>/main/scripts/wt-provision.sh"
bash -n "<container>/main/scripts/wt-provision.sh"
```

**The user commits the script, and this skill never does.** A milestone worktree is a fresh
checkout, so a script outside `HEAD` reaches none of them. `rules/pr-first-contributions.md` owns
how that commit lands. This skill writes the file and stops.

**A user who keeps the script private moves it to `<container>/provision-worktree.sh`.** No
checkout holds that path, so nothing can commit it, and `/worktree provision` falls back to it
when the worktree carries no committed script.

## Then hand over

The container is ready once `HEAD` carries its provisioning script, or once
`<container>/provision-worktree.sh` exists and is executable. `/worktree cut` takes it from here,
and it derives the container path itself from any worktree inside it.

**Say so plainly where neither exists yet.** `/worktree cut` provisions every tree it creates, and
it stops on an absent script. A hand-over that calls the container ready sends the user straight
into that stop.
