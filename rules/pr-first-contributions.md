---
description: PR-first git workflow with conventional titles, draft PRs, stacked bases, and squash-merge descriptions
---

# PR-first contributions

Contribute code through pull requests by default. The PR is the unit of contribution, not the individual branch commits. The PR carries the record of the change into the default branch's history.

## Default policy

- **Default:** Deliver every repository change through a **PR**. Base it on the repo's default branch, resolved from `origin/HEAD`: `main`, `master`, or whatever it points to.
- **Base:** The default branch is the usual base, not the only one. Work that depends on an unmerged branch bases on that branch instead. See `## Stacked PRs`.
- **Exceptions:** Skip the PR workflow only when the user **clearly** instructs otherwise. Examples: "commit directly to main", "no PR", "push straight to default branch", `/implement --in main`. If the request is ambiguous, ask once. Otherwise follow this rule.
- **Branch:** Cut a feature branch from the latest default branch, or from the unmerged branch this work depends on. Name it for the work and prefix it by type: `feat/…`, `fix/…`, `chore/…`. Never commit on the default branch.
- **Commits:** Only create commits when the user asks or when the PR workflow clearly requires it. No secrets, no `--no-verify`, and no amend unless the user allows it.
- **Pushes:** Never push or open a PR without explicit approval. Approval for one push does not carry to the next.
- **Draft by default:** Open PRs as drafts. Mark ready for review only when the user says so.
- **Destructive git:** No `reset --hard`, force-push, or history rewrite without explicit approval.

## Branch staleness check

Run this check before the first commit on the current branch in this session. Run it again before you push or open a PR.

```bash
git fetch origin

BRANCH="$(git branch --show-current)"
DEFAULT="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
[ -z "$DEFAULT" ] && DEFAULT="$(git remote show origin | awk '/HEAD branch/ {print $NF}')"
[ -z "$DEFAULT" ] && { echo "cannot resolve the default branch — staleness check did not run"; exit 1; }

git diff --quiet "origin/${DEFAULT}"..HEAD && CONTENT_DIFF=empty || CONTENT_DIFF=present
MERGED="$(gh pr list --head "$BRANCH" --state merged --limit 1 --json number,title,mergedAt 2>/dev/null)"
```

You need both signals. Content alone is not enough. A branch with no commits yet reports `empty`, and so does a branch whose commits cancel out. Both are good places to work.

A merged PR alone is not enough either. A squash-merged branch still reports commits ahead, and it carries no unmerged content. `git rev-list --count` is therefore the wrong test.

Resolution must succeed before either signal means anything. A `git diff` against an unresolved ref exits non-zero, which reads as `present`. A silent resolution failure would therefore disable the check. The block above aborts for that reason.

**Stale—do not commit yet:** `CONTENT_DIFF` is `empty` **and** `MERGED` is non-empty. Tell the user that the branch is already merged. Cite the PR number and title from `MERGED`. Then `git switch "${DEFAULT}"`, `git pull origin "${DEFAULT}"`, and cut a fresh branch for the work. Carry forward uncommitted changes or cherry-pick only with user approval.

**Fresh:** `CONTENT_DIFF` is `empty` and `MERGED` is empty—a new branch with nothing on it yet. Proceed.

**Carries work:** `CONTENT_DIFF` is `present`. Keep the branch. If a prior PR on it already merged, this content needs a **new** PR. Do not assume the old PR is still open.

## Before presenting work

- **Run the repo's quality gates**—tests, lint, type checks, whatever the project uses. Report a failure with the shortest decisive output. Do not hide it and do not work around it. If a failure is out of scope, say so plainly. Do not leave it silently broken.
- **Leave a clean tree.** `git status` shows no uncommitted changes and no stray untracked files. A milestone worktree exempts the files the provisioning contract generated. `/worktree` defines that exempt set, and deleting one of them removes the override the stack runs on.
- **Summarize and stop.** State what changed, the quality gate results, and `git log --oneline "origin/${BASE}"..HEAD`. Set `BASE` to the parent branch when the work stacks, and to `${DEFAULT}` otherwise. Use the remote ref, because a local branch may lag. A stacked branch logged against the default branch reports its parent's commits as its own. Then wait. Do not push as part of "finishing".

## Push and open the PR

```bash
git push -u origin HEAD && git remote prune origin

gh pr create --draft --title "<conventional-title>" --body "$(cat <<'EOF'
<What changed and why—enough for a future reader of `git log`.>

<Breaking changes, migrations, follow-ups, intentional tradeoffs, links to issues or discussions. Omit if none.>
EOF
)"
```

A PR for this branch may already be open. Push the new commits, then update its title and description. Do not open a duplicate. Return the PR URL to the user.

## Stacked PRs

A branch whose work depends on another unmerged branch opens its PR against that branch. Pass `--base` to say so:

```bash
gh pr create --draft --base "<parent branch>" --title "<conventional-title>" --body "…"
```

Without `--base`, `gh` targets the default branch. The PR then shows the parent branch's commits as its own. A reviewer cannot separate the new work from the work already under review.

**A stacked PR names its parent PR's URL in its body.** A base branch name does not say which PR owns that branch. The diff does not show the dependency at all. State the parent URL, and say that it merges first.

**Merge a stack from base to head.** GitHub retargets an open PR when its base merges, so the child survives the parent's merge. Merging the child first orphans the parent's review.

**A set of PRs may instead merge together.** One change that spans several repositories lands one PR per repository. Each one bases on its own repository's default branch, unless that repository already carries an unmerged predecessor branch. Where it does, the stacking rule above wins, and that PR bases on the predecessor. A milestone can both span repositories and stack in one of them. None of the set stands alone either: merging one and dropping the rest leaves the change half-applied. Say in each body that the set merges together, and name the sibling PR URLs.

## Title and description

Every PR lands as a squash merge. The PR title becomes the commit title on the default branch, and the PR body becomes the commit body. Write both so that a reader of `git log` needs nothing from the PR thread. Branch-level commit messages are secondary. Keep the body concise. Skip a boilerplate header such as `## Summary` unless it adds clarity. Do not include a test plan section unless the user explicitly asks for one.

The title is `<type>(<scope>): <short description>`. Use a lowercase type. A scope is optional, but include one where you can. Use one of exactly three types, which the semantic PR checks in repos such as Sage require.

| Type | Use for | Example |
|------|---------|---------|
| `feat` | New behavior or user-facing capability | `feat(cli): add install doctor command` |
| `fix` | Bug fix | `fix(auth): handle expired token refresh` |
| `chore` | Tooling, CI, deps, refactors without behavior change, docs-only | `chore(ci): bump golangci-lint` |

When a change spans multiple types, pick the dominant type or split the work into multiple PRs. Use `@split-to-prs` for large mixed work.
