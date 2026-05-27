#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
default_prompt_file="$script_dir/../references/review_prompt.md"
default_output_schema_file="$script_dir/../references/review_output_schema.json"

prompt_file="$default_prompt_file"
output_schema_file="$default_output_schema_file"
context_text=""
target_mode="uncommitted"
base_ref="${CODEX_LOCAL_REVIEW_BASE:-origin/main}"
commit_sha=""
title="${CODEX_LOCAL_REVIEW_TITLE:-}"
min_severity="${CODEX_LOCAL_REVIEW_MIN_SEVERITY:-LOW}"
findings_out=""
json_out=""
repo_root=""
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
raw_output_file=""
stderr_file=""
timeout_seconds="${CODEX_LOCAL_REVIEW_TIMEOUT_SECONDS:-900}"
heartbeat_seconds="${CODEX_LOCAL_REVIEW_HEARTBEAT_SECONDS:-20}"
max_patch_bytes="${CODEX_LOCAL_REVIEW_MAX_PATCH_BYTES:-500000}"
codex_bin="${CODEX_LOCAL_REVIEW_CODEX_BIN:-codex}"
codex_profile="${CODEX_LOCAL_REVIEW_PROFILE:-}"
print_json="false"
exclude_paths=()
review_pathspecs=()

review_mode_label=""
review_changed_files=""
review_patch=""
raw_dest=""
stderr_dest=""

usage() {
  cat <<'USAGE'
Usage: local_review.sh [--uncommitted | --tracked-head | --base-ref REF | --commit SHA] [--context-text "TEXT"] [--title "TITLE"] [--prompt-file PATH] [--exclude-path PATH_OR_GLOB] [--max-patch-bytes N] [--min-severity P1|P2|P3|LOW] [--blocking-only] [--findings-out PATH] [--json-out PATH] [--print-json]

Runs local Codex review against an explicit git diff instead of the native `review` backend.
Saves Markdown findings to a file and prints Markdown to stdout by default, or JSON with --print-json.
Defaults to --uncommitted when no target is provided.
Use --exclude-path for deterministic generated files after their own checks pass.
Use --max-patch-bytes 0 to disable the patch payload size guard.
Use --blocking-only as a shortcut for --min-severity P2.
USAGE
}

make_temp_file() {
  local prefix="$1"
  mktemp "${tmp_root}/${prefix}.XXXXXX"
}

slugify() {
  local value="$1"
  value=${value//\//-}
  value=${value// /-}
  value=${value//:/-}
  value=${value//[^A-Za-z0-9._-]/-}
  printf '%s' "${value:-review}"
}

target_slug() {
  case "$target_mode" in
    uncommitted)
      printf 'uncommitted'
      ;;
    tracked_head)
      printf 'tracked-head'
      ;;
    base)
      printf 'base-%s' "$(slugify "$base_ref")"
      ;;
    commit)
      printf 'commit-%s' "$(slugify "${commit_sha:0:12}")"
      ;;
    *)
      printf 'review'
      ;;
  esac
}

default_findings_out() {
  local timestamp
  local findings_dir
  timestamp=$(date +%Y%m%d_%H%M%S)
  findings_dir="${CODEX_LOCAL_REVIEW_FINDINGS_DIR:-$repo_root/.codex/reports/local_review}"
  printf '%s/%s_%s.md' "$findings_dir" "$timestamp" "$(target_slug)"
}

persist_file() {
  local source_path="$1"
  local dest_path="$2"

  mkdir -p "$(dirname "$dest_path")"
  cp "$source_path" "$dest_path"
}

log_phase() {
  printf '[local-review] %s\n' "$1" >&2
}

branch_name() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown'
}

unique_lines() {
  awk 'NF && !seen[$0]++'
}

normalize_severity_value() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

validate_min_severity() {
  min_severity=$(normalize_severity_value "$min_severity")
  case "$min_severity" in
    P1|P2|P3|LOW)
      ;;
    *)
      echo "Minimum severity must be one of: P1, P2, P3, LOW." >&2
      exit 2
      ;;
  esac
}

is_binary_untracked_file() {
  local path="$1"
  local added=""
  local removed=""

  read -r added removed _ < <(git diff --no-index --numstat -- /dev/null "$path" 2>/dev/null || true)
  [[ "$added" == "-" && "$removed" == "-" ]]
}

path_is_excluded() {
  local path="$1"

  if ((${#exclude_paths[@]} == 0)); then
    return 1
  fi

  python3 - "$path" "${exclude_paths[@]}" <<'PY'
import fnmatch
import sys

path = sys.argv[1].replace("\\", "/")
for pattern in sys.argv[2:]:
    pattern = pattern.strip().replace("\\", "/")
    if not pattern:
        continue
    directory = pattern.rstrip("/")
    if path == pattern or path == directory:
        raise SystemExit(0)
    if pattern.endswith("/") and path.startswith(pattern):
        raise SystemExit(0)
    if path.startswith(directory + "/") and not any(ch in directory for ch in "*?["):
        raise SystemExit(0)
    if fnmatch.fnmatch(path, pattern):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

filter_excluded_paths() {
  local path

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if path_is_excluded "$path"; then
      continue
    fi
    printf '%s\n' "$path"
  done
}

build_review_pathspecs() {
  review_pathspecs=()
  if ((${#exclude_paths[@]} == 0)); then
    return
  fi

  review_pathspecs+=(".")
  local path
  for path in "${exclude_paths[@]}"; do
    [[ -n "$path" ]] || continue
    review_pathspecs+=(":(exclude)$path")
  done
}

git_diff() {
  if ((${#review_pathspecs[@]} == 0)); then
    git diff "$@"
  else
    git diff "$@" -- "${review_pathspecs[@]}"
  fi
}

git_show() {
  if ((${#review_pathspecs[@]} == 0)); then
    git show "$@"
  else
    git show "$@" -- "${review_pathspecs[@]}"
  fi
}

build_uncommitted_changed_files() {
  {
    git_diff --cached --name-only
    git_diff --name-only
    git ls-files --others --exclude-standard
  } | unique_lines | filter_excluded_paths
}

build_uncommitted_patch() {
  local staged_diff
  local unstaged_diff
  local had_untracked="false"
  local path

  staged_diff=$(git_diff --cached --no-color)
  unstaged_diff=$(git_diff --no-color)

  printf '# Staged diff\n'
  if [[ -n "$staged_diff" ]]; then
    printf '%s\n' "$staged_diff"
  else
    printf '(none)\n'
  fi

  printf '\n# Unstaged diff\n'
  if [[ -n "$unstaged_diff" ]]; then
    printf '%s\n' "$unstaged_diff"
  else
    printf '(none)\n'
  fi

  printf '\n# Untracked files as new-file patches\n'
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    had_untracked="true"
    if is_binary_untracked_file "$path"; then
      printf 'Binary file omitted from patch diff: %s\n\n' "$path"
      continue
    fi
    git diff --no-index --no-color -- /dev/null "$path" || true
    printf '\n'
  done < <(git ls-files --others --exclude-standard | filter_excluded_paths)

  if [[ "$had_untracked" != "true" ]]; then
    printf '(none)\n'
  fi
}

build_tracked_head_changed_files() {
  git_diff --name-only HEAD | unique_lines
}

build_tracked_head_patch() {
  git_diff --no-color HEAD
}

build_review_material() {
  case "$target_mode" in
    uncommitted)
      review_mode_label="local working tree vs HEAD"
      review_changed_files=$(build_uncommitted_changed_files)
      review_patch=$(build_uncommitted_patch)
      ;;
    tracked_head)
      review_mode_label="tracked changes vs HEAD"
      review_changed_files=$(build_tracked_head_changed_files)
      review_patch=$(build_tracked_head_patch)
      ;;
    base)
      review_mode_label="branch diff vs $base_ref"
      review_changed_files=$(git_diff --name-only "$base_ref...HEAD" | unique_lines)
      review_patch=$(git_diff --no-color "$base_ref...HEAD")
      ;;
    commit)
      review_mode_label="commit review"
      review_changed_files=$(git_show --name-only --format='' "$commit_sha" | unique_lines)
      review_patch=$(git_show --no-color --format=medium --patch "$commit_sha")
      ;;
    *)
      echo "Unsupported target mode: $target_mode" >&2
      exit 2
      ;;
  esac
}

build_debug_paths() {
  local base_path="${findings_out%.md}"
  if [[ "$base_path" == "$findings_out" ]]; then
    base_path="$findings_out"
  fi
  raw_dest="${base_path}.raw.txt"
  stderr_dest="${base_path}.stderr.txt"
}

build_empty_review_json() {
  local summary="$1"
  python3 - "$summary" <<'PY'
import json
import sys

print(json.dumps({"summary": sys.argv[1], "findings": []}, ensure_ascii=False))
PY
}

build_full_prompt() {
  local prompt_text
  local target_block
  local changed_files_text
  local severity_block=""

  prompt_text=$(cat "$prompt_file")
  changed_files_text="${review_changed_files:-}"
  if [[ -z "$changed_files_text" ]]; then
    changed_files_text="(none)"
  fi

  target_block=$'# Review target\n'
  target_block+="Mode: $review_mode_label"$'\n'
  target_block+="Branch: $(branch_name)"$'\n'
  case "$target_mode" in
    base)
      target_block+="Base: $base_ref"$'\n'
      ;;
    commit)
      target_block+="Commit: $commit_sha"$'\n'
      ;;
  esac
  if [[ -n "$title" ]]; then
    target_block+="Title: $title"$'\n'
  fi
  if ((${#exclude_paths[@]} > 0)); then
    target_block+="Excluded paths: ${exclude_paths[*]}"$'\n'
  fi
  if [[ "$min_severity" != "LOW" ]]; then
    severity_block=$'# Severity focus\n'
    severity_block+="Report only findings with severity at or above $min_severity. "
    severity_block+="Do not include lower-severity findings in the JSON for this run."$'\n\n'
  fi

  if [[ -n "$context_text" ]]; then
    printf '# Change context\n%s\n\n%s\n%s# Changed files\n%s\n\n# Patch diff\n```diff\n%s\n```\n\n%s\n' \
      "$context_text" \
      "$target_block" \
      "$severity_block" \
      "$changed_files_text" \
      "$review_patch" \
      "$prompt_text"
  else
    printf '%s\n%s# Changed files\n%s\n\n# Patch diff\n```diff\n%s\n```\n\n%s\n' \
      "$target_block" \
      "$severity_block" \
      "$changed_files_text" \
      "$review_patch" \
      "$prompt_text"
  fi
}

run_codex_exec() {
  local full_prompt="$1"
  shift

  python3 - "$timeout_seconds" "$heartbeat_seconds" "$raw_output_file" "$stderr_file" "$@" "$full_prompt" <<'PY'
import pathlib
import subprocess
import sys
import threading
import time

timeout = int(sys.argv[1])
heartbeat_seconds = int(sys.argv[2])
stdout_path = pathlib.Path(sys.argv[3])
stderr_path = pathlib.Path(sys.argv[4])
cmd = sys.argv[5:]

start = time.monotonic()
last_activity = start
last_heartbeat = start
stdout_chunks = []
stderr_chunks = []
proc = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def finalize_streams():
    # Do not let reader-thread teardown block the wrapper indefinitely.
    stdout_thread.join(timeout=2)
    stderr_thread.join(timeout=2)

def pump_stream(stream, sink, label):
    global last_activity
    for line in iter(stream.readline, ""):
        sink.append(line)
        last_activity = time.monotonic()
        stripped = line.rstrip()
        if stripped:
            print(f"[codex {label}] {stripped}", file=sys.stderr, flush=True)
    stream.close()

stdout_thread = threading.Thread(
    target=pump_stream,
    args=(proc.stdout, stdout_chunks, "stdout"),
    daemon=True,
)
stderr_thread = threading.Thread(
    target=pump_stream,
    args=(proc.stderr, stderr_chunks, "stderr"),
    daemon=True,
)
stdout_thread.start()
stderr_thread.start()

while True:
    now = time.monotonic()
    elapsed = time.monotonic() - start
    remaining = timeout - elapsed
    if remaining <= 0:
        proc.kill()
        proc.wait()
        finalize_streams()
        stdout_path.write_text("".join(stdout_chunks), encoding="utf-8")
        stderr_path.write_text("".join(stderr_chunks), encoding="utf-8")
        raise SystemExit(124)

    status = proc.poll()
    if status is not None:
        proc.wait()
        finalize_streams()
        stdout_path.write_text("".join(stdout_chunks), encoding="utf-8")
        stderr_path.write_text("".join(stderr_chunks), encoding="utf-8")
        raise SystemExit(status)

    if proc.poll() is None and (now - last_heartbeat) >= heartbeat_seconds:
        print(
            "Codex review still running "
            f"({int(time.monotonic() - start)}s elapsed, "
            f"{int(time.monotonic() - last_activity)}s since last child output)...",
            file=sys.stderr,
            flush=True,
        )
        last_heartbeat = now

    time.sleep(min(1, max(0.1, remaining)))
PY
}

validate_review_json() {
  local json_path="$1"

  jq -e '
    (.summary | type == "string")
    and (.findings | type == "array")
    and all(
      .findings[];
      (.severity == "P1" or .severity == "P2" or .severity == "P3" or .severity == "LOW")
      and (.file | type == "string")
      and (
        (.line == null)
        or (
          (.line | type == "number")
          and (.line >= 1)
          and ((.line % 1) == 0)
        )
      )
      and (.title | type == "string")
      and (.description | type == "string")
      and (.recommendation | type == "string")
    )
  ' "$json_path" >/dev/null 2>&1
}

filter_review_json_by_min_severity() {
  local json_path="$1"
  local filtered_path

  if [[ "$min_severity" == "LOW" ]]; then
    return 0
  fi

  filtered_path=$(make_temp_file "local-codex-review-filtered")
  python3 - "$json_path" "$filtered_path" "$min_severity" <<'PY'
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
threshold = sys.argv[3]
rank = {"P1": 1, "P2": 2, "P3": 3, "LOW": 4}
threshold_rank = rank[threshold]

data = json.loads(source.read_text(encoding="utf-8"))
findings = data.get("findings") or []
kept = [
    finding
    for finding in findings
    if rank.get(str(finding.get("severity") or "").upper(), 99) <= threshold_rank
]
filtered_count = len(findings) - len(kept)
data["findings"] = kept

summary = str(data.get("summary") or "").strip()
note = (
    f"Minimum severity {threshold} applied; "
    f"omitted {filtered_count} lower-severity finding(s)."
)
data["summary"] = f"{summary} {note}".strip()

dest.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
PY
  mv "$filtered_path" "$json_path"
}

persist_success_outputs() {
  local json_path="$1"
  local rendered_findings

  rendered_findings=$(render_markdown_from_json "$json_path" "$min_severity")
  mkdir -p "$(dirname "$findings_out")"
  printf '%s\n' "$rendered_findings" >"$findings_out"

  if [[ -n "$json_out" ]]; then
    persist_file "$json_path" "$json_out"
  fi

  if [[ "$print_json" == "true" ]]; then
    printf '%s\n' "$(cat "$json_path")"
  else
    printf '%s\n' "$rendered_findings"
  fi
}

recover_valid_review_output() {
  local status="$1"
  local reason="$2"

  if [[ ! -f "$raw_output_file" ]] || ! validate_review_json "$raw_output_file"; then
    return 1
  fi

  log_phase "Recovered schema-valid review output after $reason."
  filter_review_json_by_min_severity "$raw_output_file"
  persist_success_outputs "$raw_output_file"
  if [[ -f "$stderr_file" ]]; then
    persist_file "$stderr_file" "$stderr_dest"
  fi
  printf '[local-review] Recovered findings after %s; returning exit %s.\n' "$reason" "$status" >&2
  return 0
}

render_markdown_from_json() {
  local json_path="$1"
  local severity_floor="$2"

  python3 - "$json_path" "$severity_floor" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

severity_floor = sys.argv[2]
summary = str(data.get("summary") or "").strip()
findings = data.get("findings") or []

if not findings:
    if severity_floor == "LOW":
        print("No findings above LOW.")
    else:
        print(f"No findings at or above {severity_floor}.")
    if summary:
        print()
        print(f"Summary: {summary}")
    raise SystemExit(0)

for index, finding in enumerate(findings, start=1):
    severity = str(finding.get("severity") or "LOW").strip()
    title = str(finding.get("title") or "Untitled finding").strip()
    file_path = str(finding.get("file") or "unknown").strip()
    line = finding.get("line")
    location = file_path if line in (None, "") else f"{file_path}:{line}"
    description = str(finding.get("description") or "").strip()
    recommendation = str(finding.get("recommendation") or "").strip()

    print(f"{index}. [{severity}] {title}")
    print(f"   Location: {location}")
    if description:
        print(f"   Why: {description}")
    if recommendation:
        print(f"   Fix: {recommendation}")
    if index != len(findings):
        print()

if summary:
    print()
    print(f"Summary: {summary}")
PY
}

persist_failure_outputs() {
  local raw_dest="$1"
  local stderr_dest="$2"

  if [[ -f "$raw_output_file" ]]; then
    persist_file "$raw_output_file" "$raw_dest"
  fi
  if [[ -f "$stderr_file" ]]; then
    persist_file "$stderr_file" "$stderr_dest"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uncommitted)
      target_mode="uncommitted"
      commit_sha=""
      shift
      ;;
    --tracked-head)
      target_mode="tracked_head"
      commit_sha=""
      shift
      ;;
    --base-ref)
      target_mode="base"
      base_ref="$2"
      commit_sha=""
      shift 2
      ;;
    --commit)
      target_mode="commit"
      commit_sha="$2"
      shift 2
      ;;
    --context-text)
      context_text="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
    --prompt-file)
      prompt_file="$2"
      shift 2
      ;;
    --exclude-path)
      exclude_paths+=("$2")
      shift 2
      ;;
    --max-patch-bytes)
      max_patch_bytes="$2"
      shift 2
      ;;
    --min-severity)
      min_severity="$2"
      shift 2
      ;;
    --blocking-only)
      min_severity="P2"
      shift
      ;;
    --findings-out)
      findings_out="$2"
      shift 2
      ;;
    --json-out|--events-json-out)
      json_out="$2"
      shift 2
      ;;
    --print-json)
      print_json="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$prompt_file" ]]; then
  echo "Prompt file not found: $prompt_file" >&2
  exit 2
fi

if [[ ! -f "$output_schema_file" ]]; then
  echo "Output schema file not found: $output_schema_file" >&2
  exit 2
fi

if [[ "$codex_bin" == */* ]]; then
  if [[ ! -x "$codex_bin" ]]; then
    echo "Configured Codex binary is not executable: $codex_bin" >&2
    exit 2
  fi
elif ! command -v "$codex_bin" >/dev/null 2>&1; then
  echo "codex CLI is not installed or not on PATH." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to validate structured review output." >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for review execution and rendering." >&2
  exit 2
fi

if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds <= 0 )); then
  echo "CODEX_LOCAL_REVIEW_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

if ! [[ "$heartbeat_seconds" =~ ^[0-9]+$ ]] || (( heartbeat_seconds <= 0 )); then
  echo "CODEX_LOCAL_REVIEW_HEARTBEAT_SECONDS must be a positive integer." >&2
  exit 2
fi

if ! [[ "$max_patch_bytes" =~ ^[0-9]+$ ]]; then
  echo "CODEX_LOCAL_REVIEW_MAX_PATCH_BYTES / --max-patch-bytes must be a non-negative integer." >&2
  exit 2
fi
validate_min_severity

repo_root=$(git rev-parse --show-toplevel)
prompt_file_dir=$(cd "$(dirname "$prompt_file")" && pwd -P)
prompt_file="$prompt_file_dir/$(basename "$prompt_file")"
output_schema_file_dir=$(cd "$(dirname "$output_schema_file")" && pwd -P)
output_schema_file="$output_schema_file_dir/$(basename "$output_schema_file")"
cd "$repo_root"
build_review_pathspecs

if [[ -z "$findings_out" ]]; then
  findings_out=$(default_findings_out)
fi
build_debug_paths

raw_output_file=$(make_temp_file "local-codex-review-output")
stderr_file=$(make_temp_file "local-codex-review-stderr")

cleanup() {
  if [[ -n "$raw_output_file" && -f "$raw_output_file" ]]; then
    rm -f "$raw_output_file"
  fi
  if [[ -n "$stderr_file" && -f "$stderr_file" ]]; then
    rm -f "$stderr_file"
  fi
}

trap cleanup EXIT

if [[ "$target_mode" == "commit" && -z "$commit_sha" ]]; then
  echo "Missing commit SHA for --commit." >&2
  exit 2
fi

build_review_material

patch_bytes="$(printf '%s' "$review_patch" | wc -c | awk '{print $1}')"
log_phase "Collected review target ($target_mode)."
printf '[local-review] Review payload: %s changed files, %s patch bytes.\n' \
  "$(printf '%s\n' "$review_changed_files" | awk 'NF {count += 1} END {print count + 0}')" \
  "$patch_bytes" >&2

if ((${#exclude_paths[@]} > 0)); then
  printf '[local-review] Excluded paths: %s\n' "${exclude_paths[*]}" >&2
fi
if [[ "$min_severity" != "LOW" ]]; then
  printf '[local-review] Minimum severity: %s\n' "$min_severity" >&2
fi

if [[ -z "${review_changed_files//[$'\t\r\n ']}" ]]; then
  empty_summary=""
  case "$target_mode" in
    uncommitted) empty_summary="no local changes" ;;
    tracked_head) empty_summary="no tracked diff against HEAD" ;;
    base) empty_summary="no diff against $base_ref" ;;
    commit) empty_summary="commit has no patch content" ;;
  esac
  build_empty_review_json "$empty_summary" >"$raw_output_file"
else
  if (( max_patch_bytes > 0 && patch_bytes > max_patch_bytes )); then
    printf '[local-review] Review payload is %s bytes, above limit %s.\n' "$patch_bytes" "$max_patch_bytes" >&2
    printf '[local-review] Exclude deterministic generated files with --exclude-path or override with --max-patch-bytes 0.\n' >&2
    exit 2
  fi

  log_phase "Building bounded review prompt."
  full_prompt=$(build_full_prompt)

  CODEX_LOCAL_REVIEW_SANDBOX="${CODEX_LOCAL_REVIEW_SANDBOX:-read-only}"
  CODEX_LOCAL_REVIEW_MODEL="${CODEX_LOCAL_REVIEW_MODEL:-}"
  CODEX_LOCAL_REVIEW_REASONING="${CODEX_LOCAL_REVIEW_REASONING:-medium}"

  cmd=("$codex_bin" exec --output-schema "$output_schema_file")
  if [[ -n "$codex_profile" ]]; then
    cmd+=(-p "$codex_profile")
  fi
  cmd+=(-s "$CODEX_LOCAL_REVIEW_SANDBOX")
  if [[ -n "$CODEX_LOCAL_REVIEW_MODEL" ]]; then
    cmd+=(-m "$CODEX_LOCAL_REVIEW_MODEL")
  fi
  cmd+=(-c 'service_tier="fast"')
  if [[ -n "$CODEX_LOCAL_REVIEW_REASONING" ]]; then
    cmd+=(-c "model_reasoning_effort=\"$CODEX_LOCAL_REVIEW_REASONING\"")
  fi
  cmd+=(-c "features.shell_tool=false" -c "include_apply_patch_tool=false")

  printf '[local-review] Running local Codex review with profile=%s model=%s reasoning=%s sandbox=%s...\n' \
    "${codex_profile:-none}" \
    "${CODEX_LOCAL_REVIEW_MODEL:-default}" \
    "$CODEX_LOCAL_REVIEW_REASONING" \
    "$CODEX_LOCAL_REVIEW_SANDBOX" >&2
  printf '[local-review] Heartbeat interval: %ss. Findings path: %s\n' "$heartbeat_seconds" "$findings_out" >&2
  if run_codex_exec "$full_prompt" "${cmd[@]}"; then
    :
  else
    status=$?
    if recover_valid_review_output "$status" "subprocess exit $status"; then
      exit 0
    fi
    persist_failure_outputs "$raw_dest" "$stderr_dest"
    if [[ "$status" -eq 124 ]]; then
      printf '[local-review] Codex review timed out after %s seconds. Raw output saved to %s and stderr to %s\n' "$timeout_seconds" "$raw_dest" "$stderr_dest" >&2
    elif [[ "$status" -eq 130 ]]; then
      printf '[local-review] Codex review was interrupted. Raw output saved to %s and stderr to %s\n' "$raw_dest" "$stderr_dest" >&2
    else
      printf '[local-review] Codex review failed with exit %s. Raw output saved to %s and stderr to %s\n' "$status" "$raw_dest" "$stderr_dest" >&2
    fi
    exit "$status"
  fi
fi

log_phase "Validating schema-conformant review output."
if ! validate_review_json "$raw_output_file"; then
  persist_failure_outputs "$raw_dest" "$stderr_dest"
  printf '[local-review] Codex review returned invalid JSON. Raw output saved to %s and stderr to %s\n' "$raw_dest" "$stderr_dest" >&2
  exit 3
fi

filter_review_json_by_min_severity "$raw_output_file"
if ! validate_review_json "$raw_output_file"; then
  persist_failure_outputs "$raw_dest" "$stderr_dest"
  printf '[local-review] Filtered review output failed schema validation. Raw output saved to %s and stderr to %s\n' "$raw_dest" "$stderr_dest" >&2
  exit 3
fi

log_phase "Rendering and persisting findings."
persist_success_outputs "$raw_output_file"
printf '[local-review] Saved findings to %s\n' "$findings_out" >&2
if [[ -n "$json_out" ]]; then
  printf '[local-review] Saved JSON to %s\n' "$json_out" >&2
fi
