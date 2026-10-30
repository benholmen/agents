#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${AGENTS_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
DEST="${HOME}/.claude"
AGENTS_DEST="${HOME}/.agents"
CODEX_DEST="${HOME}/.codex"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: uninstall.sh

Removes what scripts/install.sh installed from this repository, for both
runtimes:

  every link in ~/.claude/rules, ~/.claude/skills, ~/.claude/agents, and
  ~/.agents/skills that resolves into this repository
  ~/.claude/references, ~/.agents/references, and the two links in
  ~/.claude/bin, when they resolve into this repository
  ~/.codex/AGENTS.md, when this repository's installer generated it
  the git hooks the installer wrote into this repository

It touches nothing else. Your own files, links into another checkout, the
backups the installer made in ~/.claude/backups, and the run state in
~/repos/.agents/work all stay.

Override the repo root with AGENTS_REPO=/path/to/agents.
USAGE
  exit 0
fi

GEN_MARKER="$(sed -n 's/^GEN_MARKER="\(.*\)"$/\1/p' "${REPO_ROOT}/scripts/install.sh")"
if [[ -z "${GEN_MARKER}" ]]; then
  echo "error: cannot read GEN_MARKER from ${REPO_ROOT}/scripts/install.sh" >&2
  exit 1
fi

unlink_if_ours() {
  local dest="$1" target
  [[ -L "${dest}" ]] || return 0
  target="$(readlink "${dest}")"
  [[ "${target}" == "${REPO_ROOT}" || "${target}" == "${REPO_ROOT}/"* ]] || return 0
  rm -f "${dest}"
  echo "  removed: ${dest#"${HOME}/"}"
}

unlink_entries() {
  local dir="$1" entry
  unlink_if_ours "${dir}"
  [[ -d "${dir}" ]] || return 0
  shopt -s nullglob
  for entry in "${dir}"/* "${dir}"/.*; do
    unlink_if_ours "${entry}"
  done
  shopt -u nullglob
}

remove_codex_rules() {
  local out="${CODEX_DEST}/AGENTS.md"
  [[ -f "${out}" ]] || return 0
  if ! head -n 1 "${out}" | grep -qF "${GEN_MARKER}"; then
    echo "  kept: .codex/AGENTS.md, which this installer did not generate"
    return 0
  fi
  if ! grep -qF "source: ${REPO_ROOT}/{rules}" "${out}"; then
    echo "  kept: .codex/AGENTS.md, generated from another checkout"
    return 0
  fi
  rm -f "${out}"
  echo "  removed: .codex/AGENTS.md"
}

remove_git_hooks() {
  local hooks hook path
  hooks="$(git -C "${REPO_ROOT}" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" \
    || return 0
  for hook in post-commit post-checkout post-merge; do
    path="${hooks}/${hook}"
    [[ -f "${path}" && ! -L "${path}" ]] || continue
    grep -qF "${GEN_MARKER}" "${path}" || continue
    rm -f "${path}"
    echo "  removed git hook: ${hook}"
  done
}

echo "Uninstalling for Claude..."
unlink_entries "${DEST}/rules"
unlink_entries "${DEST}/skills"
unlink_entries "${DEST}/agents"
unlink_if_ours "${DEST}/references"
unlink_if_ours "${DEST}/bin/wt-clone.sh"
unlink_if_ours "${DEST}/bin/wt-prune.sh"
unlink_if_ours "${DEST}/bin/deny-git-writes.sh"

echo "Uninstalling for Codex..."
unlink_entries "${AGENTS_DEST}/skills"
unlink_if_ours "${AGENTS_DEST}/references"
remove_codex_rules
remove_git_hooks

echo ""
echo "Uninstalled. The installer's backups stay in ~/.claude/backups, and run"
echo "state stays in ~/repos/.agents/work."
