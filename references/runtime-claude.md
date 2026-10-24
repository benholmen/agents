# Claude runtime adapter

The headless command for a Claude critic in a `/critique` run that Codex hosts. A run that Claude
hosts needs no command: its Claude critic is a `critique-worker` subagent.
`rules/agent-orchestration.md` carries the policy, and this file carries the command that
implements it.

Every measurement here ran on 2026-10-24, against Claude Code **2.1.310**. Run `claude --version`
first. On another version, re-run the checks under **Measured** before you trust this file.

## The command

`claude -p` takes no working-directory flag, so enter the repository first:

```bash
cd "<the repository the target belongs to>" && timeout 1800 claude -p \
  --model "<the roster's model>" \
  --effort "<high or xhigh>" \
  --permission-mode dontAsk \
  --allowedTools Read Grep Glob \
  --add-dir "<the critique directory>" \
  --output-format json \
  --json-schema "$(cat "$HOME/.agents/references/critique-findings.schema.json")" \
  < "<the critique directory>/brief.md" > "<the critique directory>/claude.json"
```

| Flag | What it does here |
|---|---|
| `--permission-mode dontAsk` | Denies every call no rule pre-approves, and never waits for an answer |
| `--allowedTools Read Grep Glob` | Pre-approves the three reading tools, and nothing that writes |
| `--add-dir` | Lets the critic read the brief's files outside the repository |
| `--output-format json` | Wraps the result in one JSON object |
| `--json-schema` | Validates the final answer against the findings schema |

**The result is `.structured_output` in `claude.json`.** Its `findings` array and its `blocked`
string follow `references/critique-findings.schema.json`. A non-zero exit, `.is_error` set to
`true`, or a missing `.structured_output` is a failed critic.

**Never pass `--permission-mode bypassPermissions` or `acceptEdits`.** `dontAsk` is the stricter
mode, not a loosening one: it denies what no rule allows.

## Measured

```
  write attempt under dontAsk                  DENIED by the permission mode
  structured_output against the schema         valid
  brief on stdin                               OK
  wall clock, two-line target, haiku, low      17 seconds
```
