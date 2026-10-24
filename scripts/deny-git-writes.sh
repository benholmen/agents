#!/usr/bin/env bash
set -uo pipefail

block() {
  echo "Blocked: $1 The orchestrator owns git. Record what you needed in your report." >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || block "jq is missing, so this hook cannot vet git commands."
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || block "the hook input did not parse."
[[ -n "${cmd}" ]] || exit 0

read_only=" status diff log show blame grep ls-files ls-tree rev-parse cat-file rev-list merge-base describe shortlog help "

while IFS= read -r sub; do
  [[ -z "${sub}" || "${sub}" == -* ]] && continue
  [[ "${read_only}" == *" ${sub} "* ]] || block "git ${sub} writes to the repository."
done < <(
  grep -oE '(^|[^[:alnum:]_.-])git([[:space:]]+(-C|-c|--git-dir|--work-tree)[[:space:]]+[^[:space:]]+|[[:space:]]+--?[[:alnum:]-]+(=[^[:space:]]+)?)*[[:space:]]+[[:alnum:]-]+' <<<"${cmd}" \
    | awk '{print $NF}'
)

exit 0
