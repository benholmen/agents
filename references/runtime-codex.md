# Codex runtime adapter

The headless command for a Codex critic in a `/critique` run that Claude hosts.
`rules/agent-orchestration.md` carries the policy, and this file carries the command that
implements it.

Every measurement here ran on 2026-10-24, against codex-cli **0.163.0**. Run `codex --version`
first. On another version, re-run the checks under **Measured** before you trust this file.

## The command

Run it with the Bash tool, in the background:

```bash
timeout 1800 codex exec \
  -s read-only \
  -C "<the repository the target belongs to>" \
  -m "<the roster's model>" \
  -c model_reasoning_effort="<high or xhigh>" \
  --ephemeral \
  --output-schema "$HOME/.claude/references/critique-findings.schema.json" \
  -o "<the critique directory>/codex.json" \
  - < "<the critique directory>/brief.md" > "<the critique directory>/codex.log" 2>&1
```

| Flag | What it does here |
|---|---|
| `-s read-only` | The critic cannot write anywhere, `/tmp` included. Reads reach the whole disk |
| `-C <repo>` | Sets the working root, so relative paths in the target resolve |
| `-m <model>` | The roster's model. Omit it to take `model` from `~/.codex/config.toml` |
| `-c model_reasoning_effort=` | The effort. Use `high` or above, because this is judgment work |
| `--ephemeral` | Keeps the run out of `~/.codex/sessions` |
| `--output-schema` | Forces the final message to match the findings schema |
| `-o <file>` | Codex writes the final message there itself, so the read-only sandbox does not block it |
| `- < brief.md` | Reads the brief from stdin, so a long brief needs no shell quoting |

**The result is `codex.json`.** Its `findings` array and its `blocked` string follow
`references/critique-findings.schema.json`. A non-zero exit, or a missing or unparseable
`codex.json`, is a failed critic. Read `codex.log` for the reason.

**Never pass `--dangerously-bypass-approvals-and-sandbox`.** Never pass `--approve-for-me` to a
critic either, because it implies the `workspace-write` sandbox.

**Pass `--skip-git-repo-check` where `-C` names no git repository.** A standalone critique of
loose files is the one case.

## Measured

```
  read a file outside -C                       OK
  shell write under /tmp                       BLOCKED, Operation not permitted
  final message in -o, against the schema      valid JSON
  brief on stdin                               OK
  trust prompt inside a git repository         none
  wall clock, two-line target, low effort      17 seconds
```
