# Codex runtime adapter

The headless command for a Codex critic in a `/critique` run that Claude hosts.
`rules/agent-orchestration.md` carries the policy, and this file carries the command that
implements it.

Every measurement here ran on 2026-10-24 and 2026-10-26, against codex-cli **0.163.0**. Run `codex
--version` first. On another version, re-run the checks under **Measured** before you trust this
file.

## The command

Run it with the Bash tool, in the background:

```bash
timeout 1800 codex exec \
  -s read-only \
  -C "<the repository the target belongs to>" \
  -m "<the entry's model, resolved>" \
  -c model_reasoning_effort="<the entry's effort>" \
  --ephemeral \
  --output-schema "$HOME/.claude/references/critique-findings.schema.json" \
  -o "<the critique directory>/codex.json" \
  - < "<the critique directory>/brief.md" > "<the critique directory>/codex.log" 2>&1
```

| Flag | What it does here |
|---|---|
| `-s read-only` | The critic cannot write anywhere, `/tmp` included. Reads reach the whole disk |
| `-C <repo>` | Sets the working root, so relative paths in the target resolve |
| `-m <model>` | The model **Choose the model** resolved. Always pass it, so `config.toml` cannot change it |
| `-c model_reasoning_effort=` | The effort `/critique` step 2 chose for the target. Always pass it |
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

## Choose the model

A roster entry that names a model uses it. A bare `codex` takes the model Codex itself lists
first. Codex keeps its ranked model list in `~/.codex/models_cache.json` and refreshes it from
OpenAI, so this follows each new release with no edit here:

```bash
jq -r '[.models[] | select(.visibility == "list" and .supported_in_api)]
       | sort_by(.priority) | .[0].slug' ~/.codex/models_cache.json
```

Fall back to `model` in `~/.codex/config.toml` where the cache is missing or prints nothing.
Where neither exists, omit `-m`, and take the model from **Confirm what ran**.

**Check the effort against the model.** Each model lists its levels in
`supported_reasoning_levels`. Where the chosen effort is absent, use the highest level listed
below it:

```bash
jq -r --arg m "<model>" '.models[] | select(.slug == $m)
       | [.supported_reasoning_levels[].effort] | join(" ")' ~/.codex/models_cache.json
```

## Confirm what ran

`codex.log` opens with a header that names the model and the effort the run used:

```
model: <model>
reasoning effort: <effort>
```

Read both before you merge findings, and report them in the ledger. They are the record of what
ran, whatever the command asked for.

## Measured

```
  read a file outside -C                       OK
  shell write under /tmp                       BLOCKED, Operation not permitted
  final message in -o, against the schema      valid JSON
  brief on stdin                               OK
  trust prompt inside a git repository         none
  wall clock, two-line target, low effort      17 seconds
  models_cache.json fields                     slug, priority, visibility, supported_in_api,
                                               supported_reasoning_levels
  first listed model, 2026-10-26               gpt-6.1-sol, the coding workhorse, at priority 0
  effort levels the listed models offer        low, medium, high, xhigh, max; some add ultra
  codex.log header                             names model and reasoning effort
```
