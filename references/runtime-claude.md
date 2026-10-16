# Claude runtime adapter

Launch arguments and startup behavior for a Claude worker spawned through Solo's `spawn_agent`.
`rules/solo-agent-orchestration.md` carries the policy. This file carries the flags that
implement it, and the one policy Claude cannot implement.

Every measurement here ran on 2026-09-19, against Claude Code **2.1.278**.

## Policy to flag

| Policy in the rule | Claude flag |
|---|---|
| Launch in auto-approval mode | `"--permission-mode", "auto"` |
| Never use a loosening mode | never `bypassPermissions` and never `acceptEdits` |
| Bound a worker's writes by directory | `"--settings", '{"sandbox":{…}}'` — see **The Bash sandbox** |
| Stop the editing tools reaching the target | `"--settings", '{"permissions":{"deny":["Edit","Write","NotebookEdit"]}}'` |
| Deny an editing worker's git writes | `"--settings", '{"permissions":{"deny":["Bash(git add:*)", …]}}'` — per command |
| Set a worker's working directory | **no equivalent** — see below |
| Match the worker to the job | `"--model", "<alias>"` and `"--effort", "<tier>"` |
| Carry the invariant preamble | `"--append-system-prompt", "<preamble>"` |

Every value here is a valid flag. A wrong one launches cleanly and changes the worker's safety
posture in silence. You cannot discover this fact by trying it.

## The permission modes

`--permission-mode` takes `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, and
`plan`. `manual` is an accepted alias for `default`.

The CLI's own settings documentation defines the two that matter here:

```
'dontAsk' - Don't prompt for permissions, deny if not pre-approved.
'auto' - Use a model classifier to approve/deny permission prompts.
```

`auto` is the default for a Solo worker. A classifier approves the ordinary steps, and a reviewer
still sees the requests that matter.

**`dontAsk` is not a bypass mode.** It denies every call that no rule pre-approves, and the
session never waits for an answer. It is strictly more restrictive than `auto`. Use it where an
allow list can name the worker's whole tool surface, such as a CI-shaped run.

`bypassPermissions` and `acceptEdits` are the loosening modes, and the rule prohibits both.
`acceptEdits` is the older setting and nobody uses it now. A bypass mode removes review from a
process that runs unattended, which is the exact situation review exists for. A read-only
assignment is not an exception.

## The Bash sandbox

Claude Code ships a Bash sandbox that the operating system enforces. It bounds every Bash command
and its child processes by directory. Pass it through `--settings`:

```
"--settings", '{"sandbox":{"enabled":true,"failIfUnavailable":true,
                "allowUnsandboxedCommands":false,
                "filesystem":{"allowWrite":["<scratch dir>"],
                              "denyWrite":["<target repo>"],
                              "denyRead":["<secret dir>"]}}}'
```

| Key | What it does |
|---|---|
| `sandbox.enabled` | Turns the sandbox on |
| `sandbox.failIfUnavailable` | Exits at startup when the sandbox cannot start |
| `sandbox.allowUnsandboxedCommands` | `false` stops a command running outside the sandbox |
| `sandbox.filesystem.allowWrite` | Paths allowed for writing |
| `sandbox.filesystem.denyWrite` | Paths denied for writing; takes precedence over `allowWrite` |
| `sandbox.filesystem.allowRead` | Paths allowed for reading |
| `sandbox.filesystem.denyRead` | Paths denied for reading |

**Always pass `failIfUnavailable: true`.** Without it, a sandbox that cannot start prints a
warning and every command then runs unsandboxed. The launch succeeds, and nothing bounds the
worker.

**`allowWrite` adds to a default set. It does not replace one.** One worker took an `allowWrite`
naming only its scratch directory. It wrote a sibling path under the system temp directory, and
the command exited 0. Naming that path in `denyWrite` changed the result to
`operation not permitted`, and the file kept its contents.

**Name the target in `denyWrite`.** That is the key the sandbox enforces, and it outranks
`allowWrite`. It blocks every write to the target, and it leaves reads intact. A worker under
that posture read the target's `README.md` at exit 0. Its append to the same directory failed
with `operation not permitted`. Two probes measured this pair on Claude Code 2.1.278.

Two limits survive at this version and date:

- **Read, Edit and Write bypass the sandbox.** A worker with `permissions.allow` naming `Write`
  replaced a file that `denyWrite` named, and the tool reported success. These three tools use
  the permission system, so a tool deny list still governs them.
- **A linked worktree keeps `.git` writable.** The sandbox allows writes to the main repository's
  shared `.git`, so it does not deny git. This task did not re-measure that claim.

## The immutable-target worker: sandbox plus deny list

Every critic, every research agent, and every retro agent is one. It writes only its own scratch
directory, it reads the whole disk, and it never writes the target. Pass both postures, because
neither one covers the other:

```
"--settings", '{"permissions":{"deny":["Edit","Write","NotebookEdit",
                "Bash(git add:*)","Bash(git commit:*)",
                "Bash(git push:*)","Bash(git checkout:*)"]},
                "sandbox":{"enabled":true,"failIfUnavailable":true,
                "allowUnsandboxedCommands":false,
                "filesystem":{"allowWrite":["<scratch dir>"],
                              "denyWrite":["<target repo>"]}}}'
```

The sandbox bounds Bash, so `cat > <target>` now fails. The deny list bounds `Edit`, `Write`, and
`NotebookEdit`, which the sandbox does not see. Drop either half and the target stays writable
through the other one.

## The editing worker: git denied per command

An editing worker changes the target, and the rule puts it in its milestone worktree. The preamble
names that path, because Claude sets no working directory. Keep the git commands and drop the
three editing tools:

```
"--settings", '{"permissions":{"deny":["Bash(git add:*)","Bash(git commit:*)",
                "Bash(git push:*)","Bash(git checkout:*)"]}}'
```

A sandbox that permits the worker's edits permits `git add` in the same worktree. The deny list
is therefore the only per-worker control here. `references/runtime-codex.md` records that Codex
has no per-worker equivalent.

## Two flags a Solo worker cannot use

`--permission-prompts none` makes Claude Code deny anything that would prompt, and it works under
`--print` only. `--output-format json` with `--json-schema` returns a validated
`structured_output`, and it works under `--print` only. A Solo worker runs interactively in a
PTY, so neither flag reaches it.

## The one policy Claude cannot implement

**No per-launch working directory.** `rules/solo-agent-orchestration.md` gives an immutable-target
worker its own scratch directory, and an editing worker its milestone worktree. Claude sets
neither. The CLI carries no working-directory flag. `--add-dir` grants tool access rather than
scoping it, and `--worktree` cuts a new worktree instead of entering the milestone's own.
`spawn_agent` takes only `agent_tool_id`, `agent_tool_installation_id`, `extra_args`,
`include_agent_instructions`, `name`, and `project_id`.

A Claude worker therefore runs in the Solo project's own directory, which may contain the target.
One critic launched without a sandbox and reported `pwd` as `/Users/devenj/Code`. That directory
holds the repository its own brief named as immutable.

**The directory reaches a Claude worker through the prompt alone.** Name the absolute path there.
The sandbox now bounds what the worker may write, so the prompt no longer carries that bound by
itself.

## Model and effort

`--model` takes an alias for the latest model, such as `fable`, `opus`, `sonnet`, or `haiku`. It
also takes a full model name, such as `claude-fable-5`. `--effort` takes `low`, `medium`, `high`,
`xhigh`, or `max`. A worker inherits neither from the session, so set both per worker.

## A worker inherits the rules

A spawned Claude worker loads `~/.claude/rules/` the same way the parent session does. It does so
before it reads either the preamble or the assignment. A worker asked to introspect its own context
reported every rule file present, each attributed to its repository path. Neither launch flag
supplied them.

Never restate a rule in a Claude worker prompt. State the job and the constraints specific to
this task.

**This is Claude-specific.** Another runtime has its own instruction-loading path, or none. Check
that runtime's adapter before you assume a worker knows anything.
