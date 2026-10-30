#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: wt-clone.sh <source> <destination> [link-root]

Copies a file or a directory into a milestone worktree. It uses a
copy-on-write clone where the filesystem supports one, and a plain copy
everywhere else.

It reports the mode it chose on stderr:

  clone   source and destination share one clone-capable volume
  copy    anything else, and the reason

It checks the filesystem before it copies. macOS cp -c falls back to a
plain copy without saying so, and cp --reflink=auto does the same on
Linux. A caller that expects a clone would then consume the full size of
the source without warning.

Clone-capable filesystems: apfs on macOS. On Linux the script probes the
destination volume with a real reflink instead of reading the filesystem
name, because an xfs volume built with -m reflink=0 carries the name
without the feature. The Linux clone runs cp --reflink=always, which
fails loudly rather than falling back.

A symlinked source is resolved first, so the destination holds a real
file or directory rather than a link back into the source tree. The
script copies a symlink inside the source as a symlink, because a pnpm
store needs its internal links. It refuses one that resolves outside the
source, and names the link and its target. A relative link that resolves
inside link-root is allowed too, because it resolves to the same place
when the destination sits at the same depth in a sibling of link-root.

The destination must not exist, and a symlink there is refused even when
it dangles. The script also refuses a symlinked directory in the
destination's path, and names that component.

The copy lands in a temporary sibling and is renamed into place, so a
failed copy leaves no partial destination to block a retry. The rename
neither follows nor overwrites the destination, so a destination that
appears during the copy is left as it is. The script then checks that
the staged path is gone, and that the destination is the object it
staged. On macOS a directory that appears during the copy still takes
the rename inside it. The script removes what it wrote there. Exit
status is 0 only when the copy reached the destination.
USAGE
  exit 0
fi

if [[ $# -ne 2 && $# -ne 3 ]]; then
  echo "error: expected 2 or 3 arguments, got $#" >&2
  echo "usage: wt-clone.sh <source> <destination> [link-root]" >&2
  exit 2
fi

SOURCE="$1"
DEST="$2"
LINK_ROOT="${3:-}"

if [[ ! -e "${SOURCE}" ]]; then
  echo "error: source missing: ${SOURCE}" >&2
  exit 1
fi

if [[ -L "${DEST}" ]]; then
  echo "error: destination is a symlink, refusing to write through it: ${DEST}" >&2
  exit 1
fi

if [[ -e "${DEST}" ]]; then
  echo "error: destination exists, refusing to overwrite: ${DEST}" >&2
  exit 1
fi

DEST_PARENT="$(dirname "${DEST}")"

if [[ ! -d "${DEST_PARENT}" ]]; then
  echo "error: destination directory missing: ${DEST_PARENT}" >&2
  exit 1
fi

check_parent_components() {
  local dir="$1" prefix="" component
  local -a parts
  [[ "${dir}" == /* ]] || dir="${PWD}/${dir}"
  IFS='/' read -r -a parts <<< "${dir}"
  for component in "${parts[@]}"; do
    [[ -n "${component}" && "${component}" != "." ]] || continue
    prefix="${prefix}/${component}"
    if [[ -L "${prefix}" ]]; then
      echo "error: a symlinked directory leads to the destination, refusing to write through it" >&2
      echo "error: ${prefix} -> $(readlink "${prefix}")" >&2
      return 1
    fi
  done
  return 0
}

if ! check_parent_components "${DEST_PARENT}"; then
  exit 1
fi

resolve_source() {
  local path="$1" target levels=0
  while [[ -L "${path}" ]]; do
    levels=$((levels + 1))
    if [[ "${levels}" -gt 40 ]]; then
      echo "error: too many symlink levels: $1" >&2
      exit 1
    fi
    target="$(readlink "${path}")"
    if [[ "${target}" == /* ]]; then
      path="${target}"
    else
      path="$(dirname "${path}")/${target}"
    fi
  done
  if [[ -d "${path}" ]]; then
    (cd -P "${path}" && pwd -P)
  else
    printf '%s/%s\n' "$(cd -P "$(dirname "${path}")" && pwd -P)" "$(basename "${path}")"
  fi
}

if ! SOURCE="$(resolve_source "${SOURCE}")"; then
  exit 1
fi

NORMALISED=""

normalise_path() {
  local path="$1" component out=""
  local -a parts
  IFS='/' read -r -a parts <<< "${path}"
  for component in "${parts[@]}"; do
    case "${component}" in
      "" | ".") ;;
      "..") out="${out%/*}" ;;
      *) out="${out}/${component}" ;;
    esac
  done
  NORMALISED="${out:-/}"
}

check_source_links() {
  local root="$1" link target resolved
  [[ -d "${root}" ]] || return 0
  while IFS= read -r link; do
    target="$(readlink "${link}")"
    if [[ "${target}" == /* ]]; then
      resolved="${target}"
    else
      resolved="${link%/*}/${target}"
    fi
    normalise_path "${resolved}"
    case "${NORMALISED}" in
      "${root}" | "${root}"/*) continue ;;
    esac
    if [[ -n "${LINK_ROOT}" && "${target}" != /* ]]; then
      case "${NORMALISED}" in
        "${LINK_ROOT}"/*) continue ;;
      esac
    fi
    echo "error: a symlink in the source resolves outside it, refusing to clone it" >&2
    echo "error: ${link} -> ${target}" >&2
    echo "error: it resolves to ${NORMALISED}, which is outside ${root}" >&2
    return 1
  done < <(find "${root}" -type l)
  return 0
}

if [[ -n "${LINK_ROOT}" ]]; then
  LINK_ROOT="$(cd -P "${LINK_ROOT}" && pwd -P)"
fi

if ! check_source_links "${SOURCE}"; then
  exit 1
fi

device_id() {
  case "$(uname -s)" in
    Darwin) stat -f '%d' "$1" ;;
    *) stat -c '%d' "$1" ;;
  esac
}

object_id() {
  case "$(uname -s)" in
    Darwin) stat -f '%d:%i' "$1" ;;
    *) stat -c '%d:%i' "$1" ;;
  esac
}

filesystem_type() {
  local path="$1" mount_point
  mount_point="$(df -P "${path}" | awk 'NR==2 {out=$6; for (i=7; i<=NF; i++) out=out" "$i; print out}')"
  case "$(uname -s)" in
    Darwin)
      mount | awk -v mp="${mount_point}" '
        index($0, " on " mp " (") {
          split($0, parts, "(")
          split(parts[2], kind, ",")
          print kind[1]
          exit
        }'
      ;;
    *) stat -f -c '%T' "${path}" ;;
  esac
}

supports_reflink() {
  local dir="$1" probe status=0
  probe="$(mktemp -d "${dir}/.wt-clone-probe.XXXXXX")" || return 1
  printf 'probe' > "${probe}/a"
  cp --reflink=always "${probe}/a" "${probe}/b" >/dev/null 2>&1 || status=1
  rm -rf "${probe}"
  return "${status}"
}

SOURCE_DEVICE="$(device_id "${SOURCE}")"
DEST_DEVICE="$(device_id "${DEST_PARENT}")"
SOURCE_FS="$(filesystem_type "${SOURCE}")"

MODE=copy
REASON=""

if [[ "${SOURCE_DEVICE}" != "${DEST_DEVICE}" ]]; then
  REASON="different volumes (${SOURCE_FS} device ${SOURCE_DEVICE} to device ${DEST_DEVICE})"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ "${SOURCE_FS}" == "apfs" ]]; then
    MODE=clone
  else
    REASON="filesystem ${SOURCE_FS:-unknown} does not support cloning"
  fi
elif supports_reflink "${DEST_PARENT}"; then
  MODE=clone
else
  REASON="filesystem ${SOURCE_FS:-unknown} does not support reflinks"
fi

if [[ "${MODE}" == "clone" ]]; then
  case "$(uname -s)" in
    Darwin) CP_ARGS=(-Rpc) ;;
    *) CP_ARGS=(-a --reflink=always) ;;
  esac
else
  case "$(uname -s)" in
    Darwin) CP_ARGS=(-Rp) ;;
    *) CP_ARGS=(-a) ;;
  esac
  echo "wt-clone: warning: clone impossible, falling back to a plain copy" >&2
  echo "wt-clone: warning: reason: ${REASON}" >&2
fi

STAGE_DIR="$(mktemp -d "${DEST_PARENT}/.wt-clone.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT
trap 'rm -rf "${STAGE_DIR}"; exit 130' INT TERM
STAGE="${STAGE_DIR}/$(basename "${DEST}")"

if ! cp "${CP_ARGS[@]}" -- "${SOURCE}" "${STAGE}"; then
  echo "error: ${MODE} failed: ${SOURCE} -> ${DEST}" >&2
  exit 1
fi

if [[ -e "${DEST}" || -L "${DEST}" ]]; then
  echo "error: destination appeared during the ${MODE}: ${DEST}" >&2
  exit 1
fi

STAGE_ID="$(object_id "${STAGE}")"

case "$(uname -s)" in
  Darwin) MV_ARGS=(-n -h) ;;
  *) MV_ARGS=(-n -T) ;;
esac

if ! mv "${MV_ARGS[@]}" -- "${STAGE}" "${DEST}"; then
  echo "error: ${MODE} could not be renamed into place: ${DEST}" >&2
  exit 1
fi

if [[ -e "${STAGE}" || -L "${STAGE}" ]]; then
  echo "error: the destination appeared during the ${MODE}, so the rename was refused" >&2
  echo "error: ${DEST} is not ours, and it stays as it is" >&2
  exit 1
fi

if [[ ! -e "${DEST}" || -L "${DEST}" ]]; then
  echo "error: ${MODE} reported success but ${DEST} is missing or a symlink" >&2
  exit 1
fi

if [[ "$(object_id "${DEST}")" != "${STAGE_ID}" ]]; then
  DESCENDED="${DEST}/$(basename "${DEST}")"
  echo "error: the destination appeared during the ${MODE}, so the ${MODE} landed inside it" >&2
  if [[ -e "${DESCENDED}" ]] \
     && [[ "$(object_id "${DESCENDED}" 2>/dev/null || true)" == "${STAGE_ID}" ]]; then
    rm -rf -- "${DESCENDED}"
    echo "error: removed ${DESCENDED}, which this ${MODE} wrote in the wrong place" >&2
  else
    echo "error: ${DEST} holds something this script did not stage, and it stays as it is" >&2
  fi
  exit 1
fi

echo "wt-clone: ${MODE}: ${SOURCE} -> ${DEST} (${SOURCE_FS})" >&2
