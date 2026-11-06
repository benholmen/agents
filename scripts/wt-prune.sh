#!/usr/bin/env bash
# Braces make bash parse the whole file before running it; without them, an edit or git pull during a prompt runs whatever bytes sit at bash's old read position.
{
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: wt-prune.sh [--dry-run] [--unattended] [--log FILE] [--days N] [container ...]

Removes outdated worktrees from bare-plus-worktrees repositories, along
with every Docker resource each one created: containers, volumes,
networks, and the images its stack built. It also removes the local
branch.

With no container named, it uses the bare repository that holds the
current directory. Outside one, it uses every bare repository one level
below the current directory.

A worktree is stale when its pull request is merged or closed, or when
nothing in it has changed for N days (30 by default). Activity is the
newest of the last commit, the last checkout or reset, and the newest
changed or untracked file.

A stale worktree is removed without asking when nothing in it would be
lost: no changed or untracked file other than the generated
docker-compose.worktree.yml, and no commit missing from the remote or
from its pull request. A review checkout, a detached worktree named for
its pull request such as review-pr-1234, only counts commits you made.

A worktree whose folder is already gone is removed without asking,
unless its branch holds commits missing from the remote and from its
pull request. Then you choose, as for a stale one.

A stale worktree that would lose work is shown with its changes, and you
choose for each one:

  d  delete it
  a  save the work to ~/repos/.agents/work/archive/worktrees, then delete it;
     with the folder gone, it saves the branch's unpushed commits as a
     verified git bundle
  k  keep it
  v  view the changes
  q  keep this one and every one after it

The script never touches main, the default branch, a locked worktree,
or the worktree you run it from. A Compose project that a kept worktree
uses is never removed.

It also finds Compose projects whose worktree no longer exists. One
whose containers all point at a missing folder is removed without
asking. One with only volumes or images left, whose name matches no
folder, is shown for you to choose.

Without a terminal it removes only what needs no answer, and it keeps
the rest. It prints what it freed when it finishes.

--unattended is for a scheduled run. It never prompts, even from a
terminal, and it holds back some of what needs no answer:

  Docker unreachable    it removes nothing, because it cannot tell which
                        Compose projects a worktree owns
  a fetch fails         it removes nothing from that repository, because
                        its remote branches may be out of date
  containers running    it keeps a worktree whose Compose project still
                        has a running container
  Docker cleanup fails  it keeps that worktree's folder and branch, so
                        the next run can finish the job

It ends with what it removed, what it held back, what needs your
answer, and the command that asks you.

One run goes at a time. While a run holds ~/.cache/wt-prune.lock, a
second run stops at once.

Options:
  -n, --dry-run   show what would happen, and change nothing
  --unattended    never prompt, and hold back as described above
  --log FILE      append all output to FILE, and trim FILE to its last
                  512 kB once it passes 1 MB
  --days N        days without activity before a worktree is stale
  -h, --help      show this help

Pull request state comes from gh for GitHub remotes and glab for GitLab
remotes. When a lookup fails, only the age rule applies.
USAGE
}

DRY_RUN=0
UNATTENDED=0
LOG_FILE=""
DAYS=30
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --unattended) UNATTENDED=1 ;;
    --log)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --log takes a file" >&2
        exit 2
      fi
      LOG_FILE="$2"
      shift
      ;;
    --log=*)
      LOG_FILE="${1#--log=}"
      if [[ -z "${LOG_FILE}" ]]; then
        echo "error: --log takes a file" >&2
        exit 2
      fi
      ;;
    --days)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
        echo "error: --days takes a whole number" >&2
        exit 2
      fi
      DAYS="$2"
      shift
      ;;
    --days=*)
      DAYS="${1#--days=}"
      if [[ ! "${DAYS}" =~ ^[0-9]+$ ]]; then
        echo "error: --days takes a whole number" >&2
        exit 2
      fi
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      echo "usage: wt-prune.sh [--dry-run] [--unattended] [--log FILE] [--days N] [container ...]" >&2
      exit 2
      ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

GENERATED_PATHS="docker-compose.worktree.yml"
ARCHIVE_ROOT="${HOME}/repos/.agents/work/archive/worktrees"
NOW="$(date +%s)"
HERE="$(pwd -P)"
SELF="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
LOCK="${HOME}/.cache/wt-prune.lock"
LOG_LIMIT=1048576
LOG_KEEP=524288

if [[ -n "${LOG_FILE}" ]]; then
  mkdir -p "$(dirname "${LOG_FILE}")"
  exec >>"${LOG_FILE}" 2>&1
fi

mkdir -p "$(dirname "${LOCK}")"
if ! mkdir "${LOCK}" 2>/dev/null; then
  holder="$(cat "${LOCK}/pid" 2>/dev/null || true)"
  if [[ -z "${holder}" ]] || ps -p "${holder}" -o command= 2>/dev/null | grep -q wt-prune; then
    echo "wt-prune: $(date '+%Y-%m-%d %H:%M') another run${holder:+ (pid ${holder})} holds ${LOCK}, so this one stops" >&2
    exit 1
  fi
  rm -rf "${LOCK}"
  if ! mkdir "${LOCK}" 2>/dev/null; then
    echo "wt-prune: $(date '+%Y-%m-%d %H:%M') another run holds ${LOCK}, so this one stops" >&2
    exit 1
  fi
fi
trap 'rm -rf "${LOCK}"' EXIT
echo "$$" >"${LOCK}/pid"

if [[ -n "${LOG_FILE}" && "$(wc -c <"${LOG_FILE}" | tr -d ' ')" -gt "${LOG_LIMIT}" ]]; then
  tail -c "${LOG_KEEP}" "${LOG_FILE}" | sed 1d >"${LOG_FILE}.trim"
  cat "${LOG_FILE}.trim" >"${LOG_FILE}"
  rm -f "${LOG_FILE}.trim"
fi

if [[ "${UNATTENDED}" -eq 1 ]]; then
  export GIT_TERMINAL_PROMPT=0
  echo ""
  echo "==== wt-prune --unattended, $(date '+%Y-%m-%d %H:%M'), in ${HERE}"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wt-prune.XXXXXX")"
trap 'rm -rf "${TMP}" "${LOCK}"' EXIT
trap 'rm -rf "${TMP}" "${LOCK}"; exit 130' INT TERM

is_container() {
  [[ -d "$1/.git" ]] \
    && [[ "$(git --git-dir="$1/.git" rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]
}

CONTAINERS=()

if [[ ${#ARGS[@]} -gt 0 ]]; then
  for arg in "${ARGS[@]}"; do
    if [[ ! -d "${arg}" ]]; then
      echo "error: not a directory: ${arg}" >&2
      exit 1
    fi
    dir="$(cd -P "${arg}" && pwd -P)"
    if ! is_container "${dir}"; then
      echo "error: not a bare-plus-worktrees container: ${dir}" >&2
      exit 1
    fi
    CONTAINERS+=("${dir}")
  done
else
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "${common}" ]] && is_container "$(dirname "${common}")"; then
    CONTAINERS+=("$(cd -P "$(dirname "${common}")" && pwd -P)")
  else
    for dir in "${HERE}"/*/; do
      dir="${dir%/}"
      if is_container "${dir}"; then
        CONTAINERS+=("${dir}")
      fi
    done
  fi
fi

if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
  echo "error: no bare-plus-worktrees container here or one level below ${HERE}" >&2
  exit 1
fi

if [[ "${UNATTENDED}" -eq 0 ]] && { : </dev/tty; } 2>/dev/null; then
  INTERACTIVE=1
else
  INTERACTIVE=0
fi

has() { command -v "$1" >/dev/null 2>&1; }

mtime() {
  case "$(uname -s)" in
    Darwin) xargs -0 stat -f '%m' 2>/dev/null ;;
    *) xargs -0 -r stat -c '%Y' 2>/dev/null ;;
  esac
}

to_bytes() {
  awk -v s="$1" 'BEGIN {
    n = s + 0; u = s; sub(/^[0-9.]+ */, "", u)
    m = 1
    if (u == "kB" || u == "KB") m = 1e3
    else if (u == "MB") m = 1e6
    else if (u == "GB") m = 1e9
    else if (u == "TB") m = 1e12
    printf "%.0f\n", n * m
  }'
}

human() {
  awk -v b="$1" 'BEGIN {
    if (b < 0) b = 0
    if (b >= 1e9) printf "%.1f GB\n", b / 1e9
    else if (b >= 1e6) printf "%.0f MB\n", b / 1e6
    else if (b >= 1e3) printf "%.0f kB\n", b / 1e3
    else printf "%d B\n", b
  }'
}

plural() {
  if [[ "$1" -eq 1 ]]; then
    printf '%s %s' "$1" "$2"
  else
    printf '%s %s' "$1" "${3:-$2s}"
  fi
}

norm_project() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-'
  printf '\n'
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-'
  printf '\n'
}

DOCKER=0
if has docker && docker info >/dev/null 2>&1; then
  if has jq; then
    DOCKER=1
  else
    echo "wt-prune: warning: jq is missing, so Docker resources are left alone" >&2
  fi
fi

: >"${TMP}/containers.tsv"
: >"${TMP}/volumes.tsv"
: >"${TMP}/images.tsv"
: >"${TMP}/networks.tsv"
: >"${TMP}/projects"

docker_totals() {
  [[ "${DOCKER}" -eq 1 ]] || return 0
  docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null | while IFS=$'\t' read -r type size; do
    printf '%s\t%s\n' "${type}" "$(to_bytes "${size}")"
  done
}

load_docker() {
  [[ "${DOCKER}" -eq 1 ]] || return 0
  docker ps -a --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}\t{{.State}}\t{{.ID}}' \
    | awk -F'\t' '$1 != ""' >"${TMP}/containers.tsv"
  docker network ls --format '{{.ID}}\t{{.Label "com.docker.compose.project"}}' \
    | awk -F'\t' '$2 != ""' >"${TMP}/networks.tsv"
  docker system df -v --format json >"${TMP}/df.json"
  jq -r '.Volumes[]
    | [.Name,
       ((.Labels // "") | split(",") | map(select(startswith("com.docker.compose.project="))) | (.[0] // "") | ltrimstr("com.docker.compose.project=")),
       .Size]
    | select(.[1] != "") | @tsv' "${TMP}/df.json" >"${TMP}/volumes.tsv"
  jq -r '.Images[] | [.ID, .UniqueSize] | @tsv' "${TMP}/df.json" >"${TMP}/image-sizes.tsv"
  docker images --no-trunc --format '{{.Repository}}:{{.Tag}}\t{{.Repository}}\t{{.ID}}' \
    | awk -F'\t' 'NR == FNR { size[$1] = $2; next } $2 != "<none>" { print $1 "\t" $2 "\t" (($3 in size) ? size[$3] : "0B") }' \
      "${TMP}/image-sizes.tsv" - >"${TMP}/images.tsv"
  cut -f1 "${TMP}/containers.tsv" >"${TMP}/projects.raw"
  cut -f2 "${TMP}/networks.tsv" >>"${TMP}/projects.raw"
  cut -f2 "${TMP}/volumes.tsv" >>"${TMP}/projects.raw"
  grep -v '^$' "${TMP}/projects.raw" | sort -u >"${TMP}/projects" || true
}

project_known() { grep -qxF -- "$1" "${TMP}/projects"; }

project_images() {
  awk -F'\t' -v p="$1" '
    NR == FNR { proj[$1] = 1; next }
    {
      best = ""
      for (q in proj) if (index($2, q "-") == 1 && length(q) > length(best)) best = q
      if (best == p) print $1
    }' "${TMP}/projects" "${TMP}/images.tsv"
}

project_summary() {
  local p="$1" containers volumes images vbytes=0 ibytes=0 size
  containers="$(awk -F'\t' -v p="${p}" '$1 == p' "${TMP}/containers.tsv" | wc -l | tr -d ' ')"
  volumes="$(awk -F'\t' -v p="${p}" '$2 == p' "${TMP}/volumes.tsv" | wc -l | tr -d ' ')"
  while IFS= read -r size; do
    vbytes=$((vbytes + $(to_bytes "${size}")))
  done < <(awk -F'\t' -v p="${p}" '$2 == p { print $3 }' "${TMP}/volumes.tsv")
  images=0
  while IFS= read -r ref; do
    images=$((images + 1))
    size="$(awk -F'\t' -v r="${ref}" '$1 == r { print $3; exit }' "${TMP}/images.tsv")"
    ibytes=$((ibytes + $(to_bytes "${size:-0B}")))
  done < <(project_images "${p}")
  printf '%s: %s, %s (%s), %s (%s)\n' "${p}" "$(plural "${containers}" container)" \
    "$(plural "${volumes}" volume)" "$(human "${vbytes}")" "$(plural "${images}" image)" "$(human "${ibytes}")"
}

remove_project() {
  local p="$1" ids vols nets imgs
  ids="$(awk -F'\t' -v p="${p}" '$1 == p { print $4 }' "${TMP}/containers.tsv")"
  vols="$(awk -F'\t' -v p="${p}" '$2 == p { print $1 }' "${TMP}/volumes.tsv")"
  nets="$(awk -F'\t' -v p="${p}" '$2 == p { print $1 }' "${TMP}/networks.tsv")"
  imgs="$(project_images "${p}")"
  if [[ -n "${ids}" ]]; then
    docker rm -f ${ids} >/dev/null 2>&1 || { echo "  warning: some containers of ${p} were not removed"; PROJECT_FAILED=1; }
  fi
  if [[ -n "${vols}" ]]; then
    docker volume rm -f ${vols} >/dev/null 2>&1 || { echo "  warning: some volumes of ${p} were not removed"; PROJECT_FAILED=1; }
  fi
  if [[ -n "${nets}" ]]; then
    docker network rm ${nets} >/dev/null 2>&1 || { echo "  warning: some networks of ${p} were not removed"; PROJECT_FAILED=1; }
  fi
  if [[ -n "${imgs}" ]]; then
    docker image rm ${imgs} >/dev/null 2>&1 || echo "  warning: some images of ${p} are still in use, and stay"
  fi
}

worktree_projects() {
  local wt="$1" name="$2" repo="$3" candidate elsewhere
  [[ "${DOCKER}" -eq 1 ]] || return 0
  {
    if [[ -f "${wt}/.env" ]]; then
      sed -n 's/^COMPOSE_PROJECT_NAME=//p' "${wt}/.env" | tr -d "\"'" | tail -1
    fi
    awk -F'\t' -v w="${wt}" '$2 == w { print $1 }' "${TMP}/containers.tsv"
    { norm_project "${name}"; norm_project "${repo}-${name}"; } | while IFS= read -r candidate; do
      elsewhere=0
      while IFS= read -r dir; do
        if [[ -n "${dir}" && -d "${dir}" ]]; then
          elsewhere=1
        fi
      done < <(awk -F'\t' -v p="${candidate}" -v w="${wt}" '$1 == p && $2 != w { print $2 }' "${TMP}/containers.tsv")
      if [[ "${elsewhere}" -eq 0 ]]; then
        echo "${candidate}"
      fi
    done
  } | while IFS= read -r candidate; do
    if [[ -n "${candidate}" ]] && project_known "${candidate}"; then
      echo "${candidate}"
    fi
  done | sort -u | paste -s -d, -
}

remote_of() {
  local url="$1" rest host path
  rest="$(printf '%s' "${url}" | sed -E 's#^[a-z+]+://##; s#^[^@/]+@##')"
  host="$(printf '%s' "${rest}" | sed -E 's#[:/].*##')"
  path="$(printf '%s' "${rest}" | sed -E 's#^[^:/]+[:/]##; s#^[0-9]+/##; s#\.git$##')"
  case "${host}" in
    *github*) printf 'github\t%s/%s\n' "${host}" "${path}" ;;
    *gitlab*) printf 'gitlab\t%s/%s\n' "${host}" "${path}" ;;
    *) printf 'none\t-\n' ;;
  esac
}

PR_RE='(^|[-_])(pr|mr)-?([0-9]+)$'

lookup_pr() {
  local kind="$1" slug="$2" name="$3" branch="$4" num="" out=""
  PR_NUM="-"
  PR_STATE="NONE"
  PR_HEAD="-"
  PR_URL="-"
  if [[ "${name}" =~ ${PR_RE} ]]; then
    num="${BASH_REMATCH[3]}"
  fi
  case "${kind}" in
    github)
      has gh || { PR_STATE="UNKNOWN"; return 0; }
      if [[ -n "${num}" ]]; then
        out="$(gh pr view "${num}" -R "${slug}" --json number,state,headRefOid,url \
          -q '"\(.number) \(.state) \(.headRefOid) \(.url)"' </dev/null 2>/dev/null)" || { PR_STATE="UNKNOWN"; return 0; }
      elif [[ "${branch}" != "-" ]]; then
        out="$(gh pr list -R "${slug}" --head "${branch}" --state all --limit 20 --json number,state,headRefOid,url \
          -q '(map(select(.state == "OPEN")) + map(select(.state == "MERGED")) + map(select(.state == "CLOSED")))[0] // empty
              | "\(.number) \(.state) \(.headRefOid) \(.url)"' </dev/null 2>/dev/null)" || { PR_STATE="UNKNOWN"; return 0; }
      fi
      ;;
    gitlab)
      { has glab && has jq; } || { PR_STATE="UNKNOWN"; return 0; }
      if [[ -n "${num}" ]]; then
        out="$(glab mr view "${num}" -R "${slug}" -F json </dev/null 2>/dev/null \
          | jq -r '"\(.iid) \(.state) \(.sha) \(.web_url)"')" || { PR_STATE="UNKNOWN"; return 0; }
      elif [[ "${branch}" != "-" ]]; then
        out="$(glab mr list -R "${slug}" -s "${branch}" -A -F json </dev/null 2>/dev/null \
          | jq -r '(map(select(.state == "opened")) + map(select(.state == "merged")) + map(select(.state != "opened" and .state != "merged")))[0] // empty
                   | "\(.iid) \(.state) \(.sha) \(.web_url)"')" || { PR_STATE="UNKNOWN"; return 0; }
      fi
      ;;
    *) return 0 ;;
  esac
  [[ -n "${out}" ]] || return 0
  read -r PR_NUM PR_STATE PR_HEAD PR_URL <<<"${out}"
  if [[ "${PR_HEAD}" == http* && -z "${PR_URL}" ]]; then
    PR_URL="${PR_HEAD}"
    PR_HEAD="-"
  fi
  [[ "${PR_URL}" == https://* || "${PR_URL}" == http://* ]] || PR_URL="-"
  case "${PR_STATE}" in
    OPEN | opened) PR_STATE="OPEN" ;;
    MERGED | merged) PR_STATE="MERGED" ;;
    *) PR_STATE="CLOSED" ;;
  esac
}

last_activity() {
  local wt="$1" newest=0 t
  for t in \
    "$(git -C "${wt}" log -1 --format=%ct HEAD 2>/dev/null || true)" \
    "$(git -C "${wt}" log -g -1 --format=%ct HEAD 2>/dev/null || true)" \
    "$( (cd "${wt}" && git ls-files -z -m -o --exclude-standard 2>/dev/null | mtime | sort -n | tail -1) || true)"; do
    if [[ "${t}" =~ ^[0-9]+$ && "${t}" -gt "${newest}" ]]; then
      newest="${t}"
    fi
  done
  echo "${newest}"
}

dirty_lines() {
  local filter=() path
  for path in ${GENERATED_PATHS}; do
    filter+=(-e "?? ${path}")
  done
  git -C "$1" status --porcelain --untracked-files=normal 2>/dev/null | grep -vxF "${filter[@]}" || true
}

unpushed_args() {
  local wt="$1" review="$2" pr_head="$3" email
  UNPUSHED_ARGS=(HEAD --not --remotes)
  if [[ "${pr_head}" != "-" ]] && git -C "${wt}" cat-file -e "${pr_head}^{commit}" 2>/dev/null; then
    UNPUSHED_ARGS+=("${pr_head}")
  fi
  if [[ "${review}" -eq 1 ]]; then
    email="$(git -C "${wt}" config user.email || true)"
    if [[ -n "${email}" ]]; then
      UNPUSHED_ARGS+=("--committer=${email}")
    fi
  fi
}

gone_args() {
  local gd="$1" branch="$2" pr_head="$3"
  GONE_ARGS=("refs/heads/${branch}" --not --remotes)
  if [[ "${pr_head}" != "-" ]] && git --git-dir="${gd}" cat-file -e "${pr_head}^{commit}" 2>/dev/null; then
    GONE_ARGS+=("${pr_head}")
  fi
}

DISK_BEFORE="$(df -k "${CONTAINERS[0]}" | awk 'NR == 2 { print $4 }')"
docker_totals >"${TMP}/docker-before.tsv"
load_docker

: >"${TMP}/worktrees.tsv"

for container in "${CONTAINERS[@]}"; do
  gd="${container}/.git"
  repo="$(basename "${container}")"
  echo "wt-prune: checking ${repo}"
  fetched=1
  if ! git --git-dir="${gd}" fetch --prune --quiet origin </dev/null 2>/dev/null; then
    echo "wt-prune: warning: could not fetch ${repo}, so remote branches may be out of date"
    fetched=0
  fi
  default="$(git --git-dir="${gd}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  IFS=$'\t' read -r kind slug <<<"$(remote_of "$(git --git-dir="${gd}" remote get-url origin 2>/dev/null || true)")"

  git --git-dir="${gd}" worktree list --porcelain | awk '
    /^worktree / { p = substr($0, 10); h = "-"; b = "-"; l = 0; pr = 0; bare = 0; next }
    /^HEAD / { h = $2; next }
    /^branch / { b = substr($0, 8); sub("^refs/heads/", "", b); next }
    /^bare/ { bare = 1; next }
    /^locked/ { l = 1; next }
    /^prunable/ { pr = 1; next }
    /^$/ { if (p != "" && !bare) print p "\t" h "\t" b "\t" l "\t" pr; p = ""; next }
    END { if (p != "" && !bare) print p "\t" h "\t" b "\t" l "\t" pr }' >"${TMP}/list.tsv"

  while IFS=$'\t' read -r wt head branch locked prunable <&3; do
    name="$(basename "${wt}")"
    review=0
    if [[ "${branch}" == "-" && "${name}" =~ ${PR_RE} ]]; then
      review=1
    fi
    action=keep
    reason=""
    age=0
    dirty=0
    unpushed=0
    PR_NUM="-"
    PR_STATE="NONE"
    PR_HEAD="-"
    PR_URL="-"

    if [[ "${prunable}" -eq 1 || ! -d "${wt}" ]]; then
      action=delete
      reason="folder already gone"
      if [[ "${branch}" != "-" ]] && git --git-dir="${gd}" show-ref --verify --quiet "refs/heads/${branch}"; then
        lookup_pr "${kind}" "${slug}" "${name}" "${branch}"
        gone_args "${gd}" "${branch}" "${PR_HEAD}"
        if ! unpushed="$(git --git-dir="${gd}" rev-list --count "${GONE_ARGS[@]}" 2>/dev/null)"; then
          action=ask
          reason="folder already gone, could not count its commits not on the remote"
          unpushed=0
        elif [[ "${unpushed}" -gt 0 ]]; then
          action=ask
          reason="folder already gone, $(plural "${unpushed}" commit) not on the remote"
        fi
      fi
    elif [[ "${wt}" == "${container}/main" ]]; then
      reason="stable worktree"
    elif [[ "${locked}" -eq 1 ]]; then
      reason="locked"
    elif [[ "${HERE}" == "${wt}" || "${HERE}" == "${wt}"/* ]]; then
      reason="you are running from it"
    elif [[ -n "${default}" && "${branch}" == "${default}" ]]; then
      reason="default branch"
    else
      lookup_pr "${kind}" "${slug}" "${name}" "${branch}"
      if [[ "${PR_HEAD}" != "-" ]] && ! git --git-dir="${gd}" cat-file -e "${PR_HEAD}^{commit}" 2>/dev/null; then
        # A merged PR's branch is deleted, so its head is only reachable through the pull ref.
        case "${kind}" in
          github) git --git-dir="${gd}" fetch --quiet origin "refs/pull/${PR_NUM}/head" </dev/null 2>/dev/null || true ;;
          gitlab) git --git-dir="${gd}" fetch --quiet origin "refs/merge-requests/${PR_NUM}/head" </dev/null 2>/dev/null || true ;;
        esac
      fi
      age=$(( (NOW - $(last_activity "${wt}")) / 86400 ))
      dirty="$(dirty_lines "${wt}" | wc -l | tr -d ' ')"
      unpushed_args "${wt}" "${review}" "${PR_HEAD}"
      unpushed="$(git -C "${wt}" rev-list --count "${UNPUSHED_ARGS[@]}" 2>/dev/null || echo 0)"

      pr_text=""
      case "${PR_STATE}" in
        MERGED) pr_text="PR #${PR_NUM} merged" ;;
        CLOSED) pr_text="PR #${PR_NUM} closed" ;;
        OPEN) pr_text="PR #${PR_NUM} open" ;;
        UNKNOWN) pr_text="PR lookup failed" ;;
        *) pr_text="no PR" ;;
      esac

      if [[ "${PR_STATE}" == "MERGED" || "${PR_STATE}" == "CLOSED" || "${age}" -ge "${DAYS}" ]]; then
        reason="${pr_text}, last active $(plural "${age}" day) ago"
        if [[ "${dirty}" -eq 0 && "${unpushed}" -eq 0 ]]; then
          action=delete
        else
          action=ask
          [[ "${dirty}" -gt 0 ]] && reason="${reason}, ${dirty} uncommitted"
          [[ "${unpushed}" -gt 0 ]] && reason="${reason}, $(plural "${unpushed}" commit) not on the remote"
        fi
      else
        reason="${pr_text}, last active $(plural "${age}" day) ago"
      fi
    fi

    if [[ "${UNATTENDED}" -eq 1 && "${action}" == "delete" ]]; then
      if [[ "${DOCKER}" -eq 0 ]]; then
        action=hold
        reason="${reason}, held back: Docker is unreachable"
      elif [[ "${fetched}" -eq 0 ]]; then
        action=hold
        reason="${reason}, held back: could not fetch"
      fi
    fi

    projects="$(worktree_projects "${wt}" "${name}" "${repo}")"
    if [[ "${UNATTENDED}" -eq 1 && "${action}" == "delete" && -n "${projects}" ]]; then
      running="$(awk -F'\t' -v l=",${projects}," 'index(l, "," $1 ",") > 0 && $3 == "running"' "${TMP}/containers.tsv" | wc -l | tr -d ' ')"
      if [[ "${running}" -gt 0 ]]; then
        action=hold
        reason="${reason}, held back: $(plural "${running}" container) running"
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${container}" "${repo}" "${wt}" "${name}" "${branch}" "${head}" "${action}" "${reason}" \
      "${PR_NUM}" "${PR_STATE}" "${age}" "${dirty}" "${unpushed}" "${projects:--}" "${PR_HEAD}" "${PR_URL}" >>"${TMP}/worktrees.tsv"
  done 3<"${TMP}/list.tsv"
done

awk -F'\t' '{ n = split($14, p, ","); for (i = 1; i <= n; i++) if (p[i] != "-") print p[i] }' \
  "${TMP}/worktrees.tsv" | sort -u >"${TMP}/attributed"
awk -F'\t' '$7 == "keep" || $7 == "hold" { n = split($14, p, ","); for (i = 1; i <= n; i++) if (p[i] != "-") print p[i] }' \
  "${TMP}/worktrees.tsv" | sort -u >"${TMP}/protected"

: >"${TMP}/living"
for container in "${CONTAINERS[@]}"; do
  find "$(dirname "${container}")" -mindepth 2 -maxdepth 3 -name .git 2>/dev/null | while IFS= read -r dotgit; do
    dir="$(dirname "${dotgit}")"
    norm_project "$(basename "${dir}")"
    norm_project "$(basename "$(dirname "${dir}")")-$(basename "${dir}")"
  done >>"${TMP}/living"
done
sort -u -o "${TMP}/living" "${TMP}/living"

: >"${TMP}/orphans.tsv"
if [[ "${DOCKER}" -eq 1 ]]; then
  while IFS= read -r p; do
    grep -qxF -- "${p}" "${TMP}/attributed" && continue
    dirs="$(awk -F'\t' -v p="${p}" '$1 == p { print $2 }' "${TMP}/containers.tsv" | sort -u)"
    if [[ -n "${dirs}" ]]; then
      live=0
      ours=0
      while IFS= read -r dir; do
        if [[ -n "${dir}" && -d "${dir}" ]]; then
          live=1
        fi
        for container in "${CONTAINERS[@]}"; do
          if [[ "${dir}" == "${container}"/* ]]; then
            ours=1
          fi
        done
      done <<<"${dirs}"
      [[ "${live}" -eq 0 && "${ours}" -eq 1 ]] || continue
      running="$(awk -F'\t' -v p="${p}" '$1 == p && $3 == "running"' "${TMP}/containers.tsv" | wc -l | tr -d ' ')"
      if [[ "${running}" -eq 0 ]]; then
        printf '%s\tdelete\tits folder is gone\n' "${p}" >>"${TMP}/orphans.tsv"
      else
        printf '%s\task\tits folder is gone, %s containers still running\n' "${p}" "${running}" >>"${TMP}/orphans.tsv"
      fi
    else
      grep -qxF -- "${p}" "${TMP}/living" && continue
      printf '%s\task\tno containers, and no folder by that name\n' "${p}" >>"${TMP}/orphans.tsv"
    fi
  done <"${TMP}/projects"
fi

echo ""
for container in "${CONTAINERS[@]}"; do
  repo="$(basename "${container}")"
  echo "${repo}"
  awk -F'\t' -v c="${container}" '$1 == c && $8 != "stable worktree" { printf "  %-7s %-50s %s\n", $7, $4, $8 }' \
    "${TMP}/worktrees.tsv" | sort -k1,1 -s
done
if [[ -s "${TMP}/orphans.tsv" ]]; then
  echo "Compose projects with no worktree"
  awk -F'\t' '{ printf "  %-7s %-50s %s\n", $2, $1, $3 }' "${TMP}/orphans.tsv" | sort -k1,1 -s
fi
echo ""

manual_command() {
  local cmd c
  cmd="cd $(printf '%q' "${HERE}") && $(printf '%q' "${SELF}")"
  if [[ "${DAYS}" -ne 30 ]]; then
    cmd="${cmd} --days ${DAYS}"
  fi
  if [[ ${#ARGS[@]} -gt 0 ]]; then
    for c in "${CONTAINERS[@]}"; do
      cmd="${cmd} $(printf '%q' "${c}")"
    done
  fi
  echo "${cmd}"
}

unattended_report() {
  local title="$1" removed="$2" held asks
  echo ""
  echo "${title}"
  if [[ -s "${removed}" ]]; then
    sed 's/^/  /' "${removed}"
  else
    echo "  nothing"
  fi
  held="$(awk -F'\t' '$7 == "hold" { printf "  %s/%s  %s\n", $2, $4, $8 }' "${TMP}/worktrees.tsv")"
  if [[ -n "${held}" ]]; then
    echo "Held back until a later run"
    printf '%s\n' "${held}"
  fi
  echo "Needs your answer"
  asks="$(
    awk -F'\t' '$7 == "ask" { printf "  %s/%s  %s\n", $2, $4, $8; if ($16 ~ /^https?:\/\//) printf "    %s\n", $16 }' "${TMP}/worktrees.tsv"
    awk -F'\t' '$2 == "ask" { printf "  Compose project %s  %s\n", $1, $3 }' "${TMP}/orphans.tsv"
  )"
  if [[ -n "${asks}" ]]; then
    printf '%s\n' "${asks}"
  else
    echo "  nothing"
  fi
  echo "To decide in a terminal, run:"
  echo "  $(manual_command)"
}

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "wt-prune: dry run, nothing was changed"
  if [[ "${UNATTENDED}" -eq 1 ]]; then
    {
      awk -F'\t' '$7 == "delete" { print $2 "/" $4 }' "${TMP}/worktrees.tsv"
      awk -F'\t' '$2 == "delete" { print "Compose project " $1 }' "${TMP}/orphans.tsv"
    } >"${TMP}/would-remove"
    unattended_report "Would remove" "${TMP}/would-remove"
  fi
  exit 0
fi

REMOVED_AUTO=0
REMOVED_ASKED=0
ARCHIVED=0
KEPT_ASKED=0
UNANSWERED=0
ORPHANS_REMOVED=0
PROJECT_FAILED=0
FOLDER_KB=0
: >"${TMP}/failed"
: >"${TMP}/removed"

remove_projects() {
  local list="$1" p
  [[ "${DOCKER}" -eq 1 && "${list}" != "-" ]] || return 0
  for p in ${list//,/ }; do
    if grep -qxF -- "${p}" "${TMP}/protected"; then
      echo "  kept Compose project ${p}, which a kept worktree uses"
    else
      remove_project "${p}"
    fi
  done
}

remove_entry() {
  local gd="$1" wt="$2" admin found=() n
  for admin in "${gd}"/worktrees/*/; do
    admin="${admin%/}"
    [[ -f "${admin}/gitdir" ]] || continue
    if [[ "$(cat "${admin}/gitdir")" == "${wt}/.git" ]]; then
      found+=("${admin}")
    fi
  done
  n=${#found[@]}
  if [[ "${n}" -ne 1 ]]; then
    echo "$(plural "${n}" "worktree entry" "worktree entries") in ${gd}/worktrees point at it" >"${TMP}/remove.err"
    return 1
  fi
  rm -rf -- "${found[0]}"
}

remove_folder() {
  local container="$1" wt="$2" attempt
  if git --git-dir="${container}/.git" worktree remove --force "${wt}" </dev/null 2>"${TMP}/remove.err"; then
    return 0
  fi
  if [[ "${wt}" != /* || -L "${wt}" || "${wt}" == "${container}" || "${wt}" == "${container}/main" ]]; then
    return 1
  fi
  # git worktree remove can fail partway through a large folder, and a retry succeeds.
  for attempt in 1 2 3; do
    if [[ ! -e "${wt}" ]] || rm -rf -- "${wt}" 2>"${TMP}/remove.err"; then
      break
    fi
    sleep 2
  done
  [[ ! -e "${wt}" ]] || return 1
  remove_entry "${container}/.git" "${wt}"
}

delete_worktree() {
  local container="$1" wt="$2" branch="$3" projects="$4" kb=0
  if [[ -d "${wt}" ]]; then
    kb="$(du -sk "${wt}" 2>/dev/null | cut -f1 || echo 0)"
  fi
  PROJECT_FAILED=0
  remove_projects "${projects}"
  if [[ "${UNATTENDED}" -eq 1 && "${PROJECT_FAILED}" -eq 1 ]]; then
    echo "  kept ${wt}, because some of its Docker resources remain"
    echo "${wt}" >>"${TMP}/failed"
    return 1
  fi
  FOLDER_KB=$((FOLDER_KB + ${kb:-0}))
  if [[ -d "${wt}" ]]; then
    if ! remove_folder "${container}" "${wt}"; then
      echo "  could not remove ${wt}: $(tail -1 "${TMP}/remove.err" 2>/dev/null)"
      echo "${wt}" >>"${TMP}/failed"
      return 1
    fi
  else
    # git refuses to delete a branch that a missing worktree still holds.
    if ! remove_entry "${container}/.git" "${wt}"; then
      echo "  could not remove the entry for ${wt}: $(tail -1 "${TMP}/remove.err" 2>/dev/null)"
      echo "${wt}" >>"${TMP}/failed"
      return 1
    fi
  fi
  if [[ "${branch}" != "-" ]]; then
    git --git-dir="${container}/.git" branch -D "${branch}" >/dev/null 2>&1 || true
  fi
}

archive_worktree() {
  local repo="$1" wt="$2" branch="$3" head="$4" pr="$5" review="$6" pr_head="$7" dest untracked
  dest="${ARCHIVE_ROOT}/${repo}-$(basename "${wt}")-$(date +%Y-%m-%dt%H%M)"
  mkdir -p "${dest}" || return 1
  {
    echo "worktree  ${wt}"
    echo "branch    ${branch}"
    echo "head      ${head}"
    echo "pr        ${pr}"
    echo "archived  $(date '+%Y-%m-%d %H:%M')"
  } >"${dest}/info.txt"
  git -C "${wt}" diff HEAD --binary >"${dest}/uncommitted.patch" || return 1
  [[ -s "${dest}/uncommitted.patch" ]] || rm -f "${dest}/uncommitted.patch"
  untracked="$(cd "${wt}" && git ls-files -o --exclude-standard | grep -vxF "${GENERATED_PATHS}" || true)"
  if [[ -n "${untracked}" ]]; then
    (cd "${wt}" && printf '%s\n' "${untracked}" | tar -czf "${dest}/untracked.tar.gz" -T -) || return 1
  fi
  unpushed_args "${wt}" "${review}" "${pr_head}"
  if [[ "$(git -C "${wt}" rev-list --count "${UNPUSHED_ARGS[@]}")" -gt 0 ]]; then
    if [[ "${branch}" != "-" ]]; then
      git -C "${wt}" bundle create "${dest}/commits.bundle" "${branch}" --not --remotes >/dev/null 2>&1 || return 1
    else
      git -C "${wt}" bundle create "${dest}/commits.bundle" HEAD --not --remotes >/dev/null 2>&1 || return 1
    fi
  fi
  echo "  saved to ${dest}"
}

archive_gone_worktree() {
  local repo="$1" container="$2" wt="$3" branch="$4" head="$5" pr="$6" gd="${container}/.git" dest
  dest="${ARCHIVE_ROOT}/${repo}-$(basename "${wt}")-$(date +%Y-%m-%dt%H%M)"
  mkdir -p "${dest}" || return 1
  {
    echo "worktree  ${wt} (folder already gone)"
    echo "branch    ${branch}"
    echo "head      ${head}"
    echo "pr        ${pr}"
    echo "archived  $(date '+%Y-%m-%d %H:%M')"
    echo "restore   git fetch ${dest}/commits.bundle ${branch}:${branch}, in a clone of the remote"
  } >"${dest}/info.txt"
  git --git-dir="${gd}" bundle create "${dest}/commits.bundle" "refs/heads/${branch}" --not --remotes >/dev/null 2>&1 || return 1
  if ! git --git-dir="${gd}" bundle verify "${dest}/commits.bundle" >/dev/null 2>&1; then
    echo "  the bundle in ${dest} did not verify"
    return 1
  fi
  echo "  saved to ${dest}"
}

show_gone_worktree() {
  local gd="$1" wt="$2" branch="$3" reason="$4" projects="$5" pr_head="$6" pr_url="$7" p lines total
  echo "  folder    ${wt} (already gone)"
  echo "  branch    ${branch}"
  echo "  why       ${reason}"
  [[ "${pr_url}" == "-" ]] || echo "  pr        ${pr_url}"
  if [[ "${DOCKER}" -eq 1 && "${projects}" != "-" ]]; then
    for p in ${projects//,/ }; do
      echo "  docker    $(project_summary "${p}")"
    done
  fi
  gone_args "${gd}" "${branch}" "${pr_head}"
  lines="$(git --git-dir="${gd}" log --format='%h %cr  %s' "${GONE_ARGS[@]}" 2>/dev/null || true)"
  if [[ -n "${lines}" ]]; then
    total="$(printf '%s\n' "${lines}" | wc -l | tr -d ' ')"
    echo "  commits not on the remote (${total}):"
    printf '%s\n' "${lines}" | head -10 | sed 's/^/    /'
    [[ "${total}" -gt 10 ]] && echo "    ... and $((total - 10)) more"
  fi
  return 0
}

view_gone_worktree() {
  local gd="$1" branch="$2" pr_head="$3"
  gone_args "${gd}" "${branch}" "${pr_head}"
  git --git-dir="${gd}" -c color.ui=always log --stat "${GONE_ARGS[@]}" 2>/dev/null | ${PAGER:-less -R} >/dev/tty
}

show_worktree() {
  local wt="$1" branch="$2" reason="$3" projects="$4" review="$5" pr_head="$6" pr_url="$7" p lines total
  echo "  folder    ${wt}"
  echo "  branch    ${branch/#-/detached}"
  echo "  why       ${reason}"
  [[ "${pr_url}" == "-" ]] || echo "  pr        ${pr_url}"
  echo "  disk      $(du -sh "${wt}" 2>/dev/null | cut -f1 | tr -d ' ')"
  if [[ "${DOCKER}" -eq 1 && "${projects}" != "-" ]]; then
    for p in ${projects//,/ }; do
      echo "  docker    $(project_summary "${p}")"
    done
  fi
  lines="$(dirty_lines "${wt}")"
  if [[ -n "${lines}" ]]; then
    total="$(printf '%s\n' "${lines}" | wc -l | tr -d ' ')"
    echo "  uncommitted (${total}):"
    printf '%s\n' "${lines}" | head -15 | sed 's/^/    /'
    [[ "${total}" -gt 15 ]] && echo "    ... and $((total - 15)) more"
  fi
  unpushed_args "${wt}" "${review}" "${pr_head}"
  lines="$(git -C "${wt}" log --format='%h %cr  %s' "${UNPUSHED_ARGS[@]}" 2>/dev/null || true)"
  if [[ -n "${lines}" ]]; then
    total="$(printf '%s\n' "${lines}" | wc -l | tr -d ' ')"
    echo "  commits not on the remote (${total}):"
    printf '%s\n' "${lines}" | head -10 | sed 's/^/    /'
    [[ "${total}" -gt 10 ]] && echo "    ... and $((total - 10)) more"
  fi
  return 0
}

view_worktree() {
  local wt="$1" review="$2" pr_head="$3"
  unpushed_args "${wt}" "${review}" "${pr_head}"
  {
    git -C "${wt}" -c color.ui=always diff HEAD
    git -C "${wt}" ls-files -o --exclude-standard | sed 's/^/untracked: /'
    git -C "${wt}" -c color.ui=always log -p "${UNPUSHED_ARGS[@]}"
  } 2>/dev/null | ${PAGER:-less -R} >/dev/tty
}

remove_safe_worktrees() {
  local container repo wt name branch head action reason pr_num pr_state age dirty unpushed projects pr_head pr_url
  while IFS=$'\t' read -r container repo wt name branch head action reason pr_num pr_state age dirty unpushed projects pr_head pr_url <&3; do
    [[ "${action}" == "delete" ]] || continue
    echo "  ${repo}/${name}"
    if delete_worktree "${container}" "${wt}" "${branch}" "${projects}"; then
      REMOVED_AUTO=$((REMOVED_AUTO + 1))
      echo "${repo}/${name}" >>"${TMP}/removed"
    fi
  done 3<"${TMP}/worktrees.tsv"
}

remove_safe_orphans() {
  local p action reason
  while IFS=$'\t' read -r p action reason <&3; do
    [[ "${action}" == "delete" ]] || continue
    echo "  Compose project ${p}"
    remove_project "${p}"
    ORPHANS_REMOVED=$((ORPHANS_REMOVED + 1))
    echo "Compose project ${p}" >>"${TMP}/removed"
  done 3<"${TMP}/orphans.tsv"
}

ASK_TOTAL="$(awk -F'\t' '$7 == "ask"' "${TMP}/worktrees.tsv" | wc -l | tr -d ' ')"
ASK_ORPHANS="$(awk -F'\t' '$2 == "ask"' "${TMP}/orphans.tsv" | wc -l | tr -d ' ')"
QUIT=0
WT_ANSWER=()
ORPHAN_ANSWER=()
CHOSEN_WT=0
CHOSEN_ORPHANS=0

if [[ "${INTERACTIVE}" -eq 0 ]]; then
  echo "Removing what is safe to remove"
  remove_safe_worktrees
  remove_safe_orphans
fi

if [[ $((ASK_TOTAL + ASK_ORPHANS)) -gt 0 && "${INTERACTIVE}" -eq 0 ]]; then
  echo ""
  if [[ "${UNATTENDED}" -eq 1 ]]; then
    why=unattended
  else
    why="no terminal"
  fi
  echo "wt-prune: ${why}, so $(plural $((ASK_TOTAL + ASK_ORPHANS)) item) that need an answer stay"
  QUIT=1
fi

if [[ $((ASK_TOTAL + ASK_ORPHANS)) -gt 0 && "${INTERACTIVE}" -eq 1 ]]; then
  echo "wt-prune: preparing $(plural $((ASK_TOTAL + ASK_ORPHANS)) question)"
  line=0
  while IFS=$'\t' read -r container repo wt name branch head action reason pr_num pr_state age dirty unpushed projects pr_head pr_url <&3; do
    line=$((line + 1))
    [[ "${action}" == "ask" ]] || continue
    review=0
    if [[ "${branch}" == "-" && "${name}" =~ ${PR_RE} ]]; then
      review=1
    fi
    if [[ -d "${wt}" ]]; then
      show_worktree "${wt}" "${branch}" "${reason}" "${projects}" "${review}" "${pr_head}" "${pr_url}" >"${TMP}/detail.${line}"
    else
      show_gone_worktree "${container}/.git" "${wt}" "${branch}" "${reason}" "${projects}" "${pr_head}" "${pr_url}" >"${TMP}/detail.${line}"
    fi
  done 3<"${TMP}/worktrees.tsv"
  line=0
  while IFS=$'\t' read -r p action reason <&3; do
    line=$((line + 1))
    [[ "${action}" == "ask" ]] || continue
    {
      echo "  why       ${reason}"
      echo "  docker    $(project_summary "${p}")"
      awk -F'\t' -v p="${p}" '$2 == p { printf "    volume %s (%s)\n", $1, $3 }' "${TMP}/volumes.tsv"
    } >"${TMP}/orphan.${line}"
  done 3<"${TMP}/orphans.tsv"
fi

index=0
line=0
while IFS=$'\t' read -r container repo wt name branch head action reason pr_num pr_state age dirty unpushed projects pr_head pr_url <&3; do
  line=$((line + 1))
  [[ "${action}" == "ask" ]] || continue
  index=$((index + 1))
  if [[ "${QUIT}" -eq 1 ]]; then
    UNANSWERED=$((UNANSWERED + 1))
    continue
  fi
  review=0
  if [[ "${branch}" == "-" && "${name}" =~ ${PR_RE} ]]; then
    review=1
  fi
  echo ""
  echo "[${index}/${ASK_TOTAL}] ${repo}/${name}"
  cat "${TMP}/detail.${line}"
  while true; do
    printf '  [d]elete  [a]rchive, then delete  [k]eep  [v]iew changes  [q]uit: '
    read -r choice </dev/tty || choice=q
    case "${choice}" in
      d | a)
        WT_ANSWER[${line}]="${choice}"
        CHOSEN_WT=$((CHOSEN_WT + 1))
        break
        ;;
      k)
        KEPT_ASKED=$((KEPT_ASKED + 1))
        break
        ;;
      v)
        if [[ -d "${wt}" ]]; then
          view_worktree "${wt}" "${review}" "${pr_head}"
        else
          view_gone_worktree "${container}/.git" "${branch}" "${pr_head}"
        fi
        ;;
      q)
        KEPT_ASKED=$((KEPT_ASKED + 1))
        QUIT=1
        break
        ;;
      *) echo "  answer d, a, k, v, or q" ;;
    esac
  done
done 3<"${TMP}/worktrees.tsv"

index=0
line=0
while IFS=$'\t' read -r p action reason <&3; do
  line=$((line + 1))
  [[ "${action}" == "ask" ]] || continue
  index=$((index + 1))
  [[ "${QUIT}" -eq 1 ]] && continue
  echo ""
  echo "[${index}/${ASK_ORPHANS}] Compose project ${p}"
  cat "${TMP}/orphan.${line}"
  while true; do
    printf '  [d]elete  [k]eep  [q]uit: '
    read -r choice </dev/tty || choice=q
    case "${choice}" in
      d)
        ORPHAN_ANSWER[${line}]=d
        CHOSEN_ORPHANS=$((CHOSEN_ORPHANS + 1))
        break
        ;;
      k) break ;;
      q)
        QUIT=1
        break
        ;;
      *) echo "  answer d, k, or q" ;;
    esac
  done
done 3<"${TMP}/orphans.tsv"

if [[ "${INTERACTIVE}" -eq 1 ]]; then
  if [[ $((ASK_TOTAL + ASK_ORPHANS)) -gt 0 ]]; then
    echo ""
  fi
  echo "Removing what is safe to remove"
  remove_safe_worktrees
  if [[ "${CHOSEN_WT}" -gt 0 ]]; then
    echo "Removing what you chose"
  fi
  line=0
  while IFS=$'\t' read -r container repo wt name branch head action reason pr_num pr_state age dirty unpushed projects pr_head pr_url <&3; do
    line=$((line + 1))
    choice="${WT_ANSWER[${line}]:-}"
    [[ -n "${choice}" ]] || continue
    review=0
    if [[ "${branch}" == "-" && "${name}" =~ ${PR_RE} ]]; then
      review=1
    fi
    if [[ "${choice}" == "a" ]]; then
      echo "  ${repo}/${name}, saving the work first"
      if [[ -d "${wt}" ]]; then
        archiver=(archive_worktree "${repo}" "${wt}" "${branch}" "${head}" "${pr_num}" "${review}" "${pr_head}")
      else
        archiver=(archive_gone_worktree "${repo}" "${container}" "${wt}" "${branch}" "${head}" "${pr_num}")
      fi
      if ! "${archiver[@]}"; then
        echo "  could not save the work, so the worktree stays"
        echo "${wt}" >>"${TMP}/failed"
      elif delete_worktree "${container}" "${wt}" "${branch}" "${projects}"; then
        REMOVED_ASKED=$((REMOVED_ASKED + 1))
        ARCHIVED=$((ARCHIVED + 1))
      fi
    else
      echo "  ${repo}/${name}"
      if delete_worktree "${container}" "${wt}" "${branch}" "${projects}"; then
        REMOVED_ASKED=$((REMOVED_ASKED + 1))
      fi
    fi
  done 3<"${TMP}/worktrees.tsv"
  if [[ "${CHOSEN_ORPHANS}" -gt 0 ]] || awk -F'\t' '$2 == "delete" { found = 1 } END { exit !found }' "${TMP}/orphans.tsv"; then
    echo "Removing Compose projects with no worktree"
  fi
  remove_safe_orphans
  line=0
  while IFS=$'\t' read -r p action reason <&3; do
    line=$((line + 1))
    [[ -n "${ORPHAN_ANSWER[${line}]:-}" ]] || continue
    echo "  Compose project ${p}"
    remove_project "${p}"
    ORPHANS_REMOVED=$((ORPHANS_REMOVED + 1))
  done 3<"${TMP}/orphans.tsv"
fi

DISK_AFTER="$(df -k "${CONTAINERS[0]}" | awk 'NR == 2 { print $4 }')"
docker_totals >"${TMP}/docker-after.tsv"
KEPT_ACTIVE="$(awk -F'\t' '$7 == "keep" && $8 != "stable worktree"' "${TMP}/worktrees.tsv" | wc -l | tr -d ' ')"

echo ""
echo "Summary"
printf '  removed   %s (%s needed no answer, %s you chose), %s with no worktree\n' \
  "$(plural $((REMOVED_AUTO + REMOVED_ASKED)) worktree)" "${REMOVED_AUTO}" "${REMOVED_ASKED}" \
  "$(plural "${ORPHANS_REMOVED}" "Compose project")"
if [[ "${ARCHIVED}" -gt 0 ]]; then
  printf '  archived  %s to %s\n' "$(plural "${ARCHIVED}" worktree)" "${ARCHIVE_ROOT}"
fi
printf '  kept      %s active, %s by your choice, %s unanswered\n' "${KEPT_ACTIVE}" "${KEPT_ASKED}" "${UNANSWERED}"
HELD="$(awk -F'\t' '$7 == "hold"' "${TMP}/worktrees.tsv" | wc -l | tr -d ' ')"
if [[ "${HELD}" -gt 0 ]]; then
  printf '  held      %s safe to remove, until a later run\n' "$(plural "${HELD}" worktree)"
fi
if [[ -s "${TMP}/failed" ]]; then
  printf '  failed    %s, still on disk:\n' "$(plural "$(wc -l <"${TMP}/failed" | tr -d ' ')" worktree)"
  sed 's/^/              /' "${TMP}/failed"
fi
printf '  disk      %s free space gained (the folders measured %s)\n' \
  "$(human $(((DISK_AFTER - DISK_BEFORE) * 1024)))" "$(human $((FOLDER_KB * 1024)))"
if [[ "${DOCKER}" -eq 1 ]]; then
  awk -F'\t' 'NR == FNR { before[$1] = $2; next } ($1 in before) { printf "%s\t%.0f\n", $1, before[$1] - $2 }' \
    "${TMP}/docker-before.tsv" "${TMP}/docker-after.tsv" | while IFS=$'\t' read -r type freed; do
    [[ "${type}" == "Build Cache" ]] && continue
    printf '  docker    %-14s %s freed\n' "${type}" "$(human "${freed}")"
  done
fi
if [[ "${UNATTENDED}" -eq 1 ]]; then
  unattended_report "Removed" "${TMP}/removed"
fi
exit
}
