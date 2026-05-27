#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
default_prompt_file="$script_dir/../references/plan_review_prompt.md"
default_output_schema_file="$script_dir/../references/plan_review_output_schema.json"

plan_file=""
prompt_file="$default_prompt_file"
output_schema_file="$default_output_schema_file"
context_text=""
min_severity="${CODEX_PLAN_REVIEW_MIN_SEVERITY:-LOW}"
findings_out=""
json_out=""
repo_root=""
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
raw_output_file=""
stderr_file=""
prompt_input_file=""
raw_dest=""
stderr_dest=""
timeout_seconds="${CODEX_PLAN_REVIEW_TIMEOUT_SECONDS:-900}"
heartbeat_seconds="${CODEX_PLAN_REVIEW_HEARTBEAT_SECONDS:-20}"
max_payload_bytes="${CODEX_PLAN_REVIEW_MAX_PAYLOAD_BYTES:-250000}"
codex_bin="${CODEX_PLAN_REVIEW_CODEX_BIN:-codex}"
codex_profile="${CODEX_PLAN_REVIEW_PROFILE:-}"
print_json="false"
allow_readonly_tools="false"
allow_dirty="false"

usage() {
  cat <<'USAGE'
Usage: plan_review.sh --plan-file PATH [--context-text "TEXT"] [--min-severity BLOCKER|P1|P2|LOW] [--blocking-only] [--allow-readonly-tools] [--allow-dirty] [--max-payload-bytes N] [--findings-out PATH] [--json-out PATH] [--print-json]

Runs a bounded Codex review of a Markdown implementation plan.
Defaults to a fast, shell-disabled review of the supplied plan and repo context.
Use --allow-readonly-tools only when the plan genuinely needs independent read-only repo inspection.
Use --allow-dirty only when unrelated local changes are intentional review context.
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
  printf '%s' "${value:-plan}"
}

default_findings_out() {
  local timestamp
  local findings_dir
  local default_reports_root
  timestamp=$(date +%Y%m%d_%H%M%S)
  default_reports_root="${CODEX_HOME:-${HOME:-$tmp_root/.codex}}"
  findings_dir="${CODEX_PLAN_REVIEW_FINDINGS_DIR:-$default_reports_root/reports/plan_review}"
  printf '%s/%s_%s.md' "$findings_dir" "$timestamp" "$(slugify "$(basename "$plan_file")")"
}

build_debug_paths() {
  local base_path="${findings_out%.md}"
  if [[ "$base_path" == "$findings_out" ]]; then
    base_path="$findings_out"
  fi
  raw_dest="${base_path}.raw.txt"
  stderr_dest="${base_path}.stderr.txt"
}

persist_file() {
  local source_path="$1"
  local dest_path="$2"

  mkdir -p "$(dirname "$dest_path")"
  cp "$source_path" "$dest_path"
}

log_phase() {
  printf '[plan-review] %s\n' "$1" >&2
}

branch_name() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown'
}

normalize_severity_value() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

validate_min_severity() {
  min_severity=$(normalize_severity_value "$min_severity")
  case "$min_severity" in
    BLOCKER|P1|P2|LOW)
      ;;
    *)
      echo "Minimum severity must be one of: BLOCKER, P1, P2, LOW." >&2
      exit 2
      ;;
  esac
}

build_plan_text() {
  python3 - "$plan_file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
    print(f"{line_no:04d}: {line}")
PY
}

build_referenced_files_report() {
  python3 - "$plan_file" "$repo_root" <<'PY'
import pathlib
import re
import sys

plan_path = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2]).resolve()
text = plan_path.read_text(encoding="utf-8")
extensions = r"(?:py|md|json|ya?ml|sh|txt|toml|ini|cfg|lock)"
tokens = []
tokens.extend(re.findall(r"`([^`]+)`", text))
tokens.extend(match.group(1) for match in re.finditer(r"(?<![A-Za-z0-9_./-])([A-Za-z0-9_./-]+\." + extensions + r")(?=$|[\s),:;])", text))

seen = set()
for token in tokens:
    value = token.strip().strip(".,:;()[]{}\"'")
    if not value or "://" in value or "\n" in value:
        continue
    value = re.sub(r":\d+(?::\d+)?$", "", value)
    if value.startswith("$") or value.startswith("-"):
        continue
    path = pathlib.Path(value)
    try:
        if path.is_absolute():
            resolved = path.resolve()
            rel = resolved.relative_to(repo_root)
        else:
            rel = path
            resolved = (repo_root / rel).resolve()
            resolved.relative_to(repo_root)
    except Exception:
        continue
    rel_text = str(rel).replace("\\", "/")
    if rel_text in seen:
        continue
    seen.add(rel_text)
    if resolved.is_file():
        try:
            line_count = len(resolved.read_text(encoding="utf-8", errors="replace").splitlines())
        except Exception:
            line_count = "unknown"
        print(f"{rel_text} (exists, {line_count} lines)")
    else:
        print(f"{rel_text} (missing)")
PY
}

build_repo_context() {
  local status_text
  local referenced_files
  status_text=$(git status --short)
  referenced_files=$(build_referenced_files_report)
  if [[ -z "$status_text" ]]; then
    status_text="(clean)"
  fi
  if [[ -z "$referenced_files" ]]; then
    referenced_files="(none detected)"
  fi

  printf '# Repo context\n'
  printf 'Repo root: %s\n' "$repo_root"
  printf 'Branch: %s\n' "$(branch_name)"
  printf 'HEAD: %s\n' "$(git rev-parse --short HEAD 2>/dev/null || printf unknown)"
  printf '\n## Git status --short\n%s\n' "$status_text"
  printf '\n## Referenced files detected from plan\n%s\n' "$referenced_files"
}

validate_dirty_state() {
  if [[ "$allow_dirty" == "true" ]]; then
    return 0
  fi

  python3 - "$repo_root" "$plan_file" <<'PY'
import pathlib
import subprocess
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
plan_file = pathlib.Path(sys.argv[2]).resolve()
try:
    allowed_plan = str(plan_file.relative_to(repo_root)).replace("\\", "/")
except ValueError:
    allowed_plan = None

raw = subprocess.check_output(
    ["git", "status", "--porcelain=v1", "-z", "--untracked-files=all"],
    cwd=repo_root,
)
parts = [part.decode("utf-8", "replace") for part in raw.split(b"\0") if part]
dirty = []
index = 0
while index < len(parts):
    entry = parts[index]
    status = entry[:2]
    path = entry[3:] if len(entry) > 3 else ""
    if path and path != allowed_plan:
        dirty.append(path)
    if status[0] in {"R", "C"} or status[1] in {"R", "C"}:
        index += 2
    else:
        index += 1

if dirty:
    print("\n".join(dirty))
    raise SystemExit(1)
PY
}

build_full_prompt() {
  local prompt_text
  local severity_block=""
  local tools_block

  prompt_text=$(cat "$prompt_file")
  tools_block="Shell tools are disabled for this review. Review the supplied plan and bounded repo context only."
  if [[ "$allow_readonly_tools" == "true" ]]; then
    tools_block="Read-only shell tools are available. Use only targeted commands needed to verify concrete plan claims."
  fi

  if [[ "$min_severity" != "LOW" ]]; then
    severity_block=$'# Severity focus\n'
    severity_block+="Report only findings with severity at or above $min_severity. "
    severity_block+="Do not include lower-severity findings in the JSON for this run."$'\n\n'
  fi

  if [[ -n "$context_text" ]]; then
    printf '# Change context\n%s\n\n' "$context_text"
  fi
  printf '# Review mode\n%s\n\n' "$tools_block"
  printf '%s' "$severity_block"
  build_repo_context
  printf '\n\n# Plan file\nPath: %s\n\n' "$plan_file"
  printf '```markdown\n%s\n```\n\n' "$(build_plan_text)"
  printf '%s\n' "$prompt_text"
}

run_codex_exec() {
  local prompt_path="$1"
  shift

  python3 - "$timeout_seconds" "$heartbeat_seconds" "$raw_output_file" "$stderr_file" "$prompt_path" "$@" <<'PY'
import os
import pathlib
import signal
import subprocess
import sys
import threading
import time

timeout = int(sys.argv[1])
heartbeat_seconds = int(sys.argv[2])
stdout_path = pathlib.Path(sys.argv[3])
stderr_path = pathlib.Path(sys.argv[4])
prompt_path = pathlib.Path(sys.argv[5])
cmd = sys.argv[6:]
prompt_text = prompt_path.read_text(encoding="utf-8")

start = time.monotonic()
last_activity = start
last_heartbeat = start
stdout_chunks = []
stderr_chunks = []
proc = subprocess.Popen(
    cmd,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    start_new_session=True,
)

def terminate_process_group(sig, grace_seconds=2):
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, sig)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()

def persist_streams():
    stdout_path.write_text("".join(stdout_chunks), encoding="utf-8")
    stderr_path.write_text("".join(stderr_chunks), encoding="utf-8")

def finalize_streams():
    stdout_thread.join(timeout=2)
    stderr_thread.join(timeout=2)

def exit_after_cleanup(status):
    finalize_streams()
    persist_streams()
    raise SystemExit(status)

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
try:
    proc.stdin.write(prompt_text)
    proc.stdin.close()
except BrokenPipeError:
    pass

def handle_signal(signum, _frame):
    terminate_process_group(signal.SIGTERM, grace_seconds=1)
    exit_after_cleanup(128 + signum)

signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)

try:
    while True:
        now = time.monotonic()
        elapsed = time.monotonic() - start
        remaining = timeout - elapsed
        if remaining <= 0:
            terminate_process_group(signal.SIGTERM)
            exit_after_cleanup(124)

        status = proc.poll()
        if status is not None:
            proc.wait()
            exit_after_cleanup(status)

        if proc.poll() is None and (now - last_heartbeat) >= heartbeat_seconds:
            print(
                "Codex plan review still running "
                f"({int(time.monotonic() - start)}s elapsed, "
                f"{int(time.monotonic() - last_activity)}s since last child output)...",
                file=sys.stderr,
                flush=True,
            )
            last_heartbeat = now

        time.sleep(min(1, max(0.1, remaining)))
except KeyboardInterrupt:
    terminate_process_group(signal.SIGTERM, grace_seconds=1)
    exit_after_cleanup(130)
PY
}

validate_review_json() {
  local json_path="$1"

  jq -e '
    (.summary | type == "string")
    and (.findings | type == "array")
    and all(
      .findings[];
      (.severity == "BLOCKER" or .severity == "P1" or .severity == "P2" or .severity == "LOW")
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

  filtered_path=$(make_temp_file "plan-review-filtered")
  python3 - "$json_path" "$filtered_path" "$min_severity" <<'PY'
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
threshold = sys.argv[3]
rank = {"BLOCKER": 0, "P1": 1, "P2": 2, "LOW": 3}
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

persist_failure_outputs() {
  if [[ -f "$raw_output_file" ]]; then
    persist_file "$raw_output_file" "$raw_dest"
  fi
  if [[ -f "$stderr_file" ]]; then
    persist_file "$stderr_file" "$stderr_dest"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-file)
      plan_file="$2"
      shift 2
      ;;
    --context-text)
      context_text="$2"
      shift 2
      ;;
    --prompt-file)
      prompt_file="$2"
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
    --allow-readonly-tools)
      allow_readonly_tools="true"
      shift
      ;;
    --allow-dirty)
      allow_dirty="true"
      shift
      ;;
    --max-payload-bytes)
      max_payload_bytes="$2"
      shift 2
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

if [[ -z "$plan_file" ]]; then
  echo "Missing required --plan-file PATH." >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$plan_file" ]]; then
  echo "Plan file not found: $plan_file" >&2
  exit 2
fi

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
  echo "jq is required to validate structured plan-review output." >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for plan-review execution and rendering." >&2
  exit 2
fi

if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds <= 0 )); then
  echo "CODEX_PLAN_REVIEW_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

if ! [[ "$heartbeat_seconds" =~ ^[0-9]+$ ]] || (( heartbeat_seconds <= 0 )); then
  echo "CODEX_PLAN_REVIEW_HEARTBEAT_SECONDS must be a positive integer." >&2
  exit 2
fi

if ! [[ "$max_payload_bytes" =~ ^[0-9]+$ ]]; then
  echo "CODEX_PLAN_REVIEW_MAX_PAYLOAD_BYTES / --max-payload-bytes must be a non-negative integer." >&2
  exit 2
fi
validate_min_severity

repo_root=$(git rev-parse --show-toplevel)
plan_file_dir=$(cd "$(dirname "$plan_file")" && pwd -P)
plan_file="$plan_file_dir/$(basename "$plan_file")"
prompt_file_dir=$(cd "$(dirname "$prompt_file")" && pwd -P)
prompt_file="$prompt_file_dir/$(basename "$prompt_file")"
output_schema_file_dir=$(cd "$(dirname "$output_schema_file")" && pwd -P)
output_schema_file="$output_schema_file_dir/$(basename "$output_schema_file")"
cd "$repo_root"

if ! dirty_paths=$(validate_dirty_state); then
  printf '[plan-review] Refusing to review with unrelated dirty paths.\n' >&2
  printf '%s\n' "$dirty_paths" | sed 's/^/[plan-review]   /' >&2
  printf '[plan-review] Commit/stash unrelated changes, move the plan to a clean worktree, or pass --allow-dirty when those paths are intentional context.\n' >&2
  exit 2
fi

if [[ -z "$findings_out" ]]; then
  findings_out=$(default_findings_out)
fi
build_debug_paths

raw_output_file=$(make_temp_file "plan-review-output")
stderr_file=$(make_temp_file "plan-review-stderr")
prompt_input_file=$(make_temp_file "plan-review-prompt")

cleanup() {
  if [[ -n "$raw_output_file" && -f "$raw_output_file" ]]; then
    rm -f "$raw_output_file"
  fi
  if [[ -n "$stderr_file" && -f "$stderr_file" ]]; then
    rm -f "$stderr_file"
  fi
  if [[ -n "$prompt_input_file" && -f "$prompt_input_file" ]]; then
    rm -f "$prompt_input_file"
  fi
}

trap cleanup EXIT

log_phase "Building bounded plan-review prompt."
full_prompt=$(build_full_prompt)
payload_bytes="$(printf '%s' "$full_prompt" | wc -c | awk '{print $1}')"
printf '%s' "$full_prompt" >"$prompt_input_file"
printf '[plan-review] Review payload: %s bytes. Plan: %s\n' "$payload_bytes" "$plan_file" >&2
if [[ "$min_severity" != "LOW" ]]; then
  printf '[plan-review] Minimum severity: %s\n' "$min_severity" >&2
fi
if [[ "$allow_readonly_tools" == "true" ]]; then
  printf '[plan-review] Read-only shell tools enabled for this plan review.\n' >&2
fi
if [[ "$allow_dirty" == "true" ]]; then
  printf '[plan-review] Unrelated dirty paths allowed for this plan review.\n' >&2
fi

if (( max_payload_bytes > 0 && payload_bytes > max_payload_bytes )); then
  printf '[plan-review] Review payload is %s bytes, above limit %s.\n' "$payload_bytes" "$max_payload_bytes" >&2
  printf '[plan-review] Narrow the plan/evidence, raise --max-payload-bytes, or use a more targeted review.\n' >&2
  exit 2
fi

CODEX_PLAN_REVIEW_SANDBOX="read-only"
CODEX_PLAN_REVIEW_MODEL="${CODEX_PLAN_REVIEW_MODEL:-}"
CODEX_PLAN_REVIEW_REASONING="${CODEX_PLAN_REVIEW_REASONING:-medium}"

cmd=("$codex_bin" exec --output-schema "$output_schema_file")
if [[ -n "$codex_profile" ]]; then
  cmd+=(-p "$codex_profile")
fi
cmd+=(-s "$CODEX_PLAN_REVIEW_SANDBOX")
if [[ -n "$CODEX_PLAN_REVIEW_MODEL" ]]; then
  cmd+=(-m "$CODEX_PLAN_REVIEW_MODEL")
fi
cmd+=(-c 'service_tier="fast"')
if [[ -n "$CODEX_PLAN_REVIEW_REASONING" ]]; then
  cmd+=(-c "model_reasoning_effort=\"$CODEX_PLAN_REVIEW_REASONING\"")
fi
cmd+=(-c "include_apply_patch_tool=false")
if [[ "$allow_readonly_tools" != "true" ]]; then
  cmd+=(-c "features.shell_tool=false")
fi

printf '[plan-review] Running Codex plan review with profile=%s model=%s reasoning=%s sandbox=%s tools=%s...\n' \
  "${codex_profile:-none}" \
  "${CODEX_PLAN_REVIEW_MODEL:-default}" \
  "$CODEX_PLAN_REVIEW_REASONING" \
  "$CODEX_PLAN_REVIEW_SANDBOX" \
  "$([[ "$allow_readonly_tools" == "true" ]] && printf readonly || printf disabled)" >&2
printf '[plan-review] Heartbeat interval: %ss. Findings path: %s\n' "$heartbeat_seconds" "$findings_out" >&2

if run_codex_exec "$prompt_input_file" "${cmd[@]}"; then
  :
else
  status=$?
  persist_failure_outputs
  if [[ "$status" -eq 124 ]]; then
    printf '[plan-review] Codex plan review timed out after %s seconds. Raw output saved to %s and stderr to %s\n' "$timeout_seconds" "$raw_dest" "$stderr_dest" >&2
  elif [[ "$status" -eq 130 ]]; then
    printf '[plan-review] Codex plan review was interrupted. Raw output saved to %s and stderr to %s\n' "$raw_dest" "$stderr_dest" >&2
  else
    printf '[plan-review] Codex plan review failed with exit %s. Raw output saved to %s and stderr to %s\n' "$status" "$raw_dest" "$stderr_dest" >&2
  fi
  exit "$status"
fi

log_phase "Validating schema-conformant plan-review output."
if ! validate_review_json "$raw_output_file"; then
  persist_failure_outputs
  printf '[plan-review] Codex plan review returned invalid JSON. Raw output saved to %s and stderr to %s\n' "$raw_dest" "$stderr_dest" >&2
  exit 3
fi

filter_review_json_by_min_severity "$raw_output_file"
if ! validate_review_json "$raw_output_file"; then
  persist_failure_outputs
  printf '[plan-review] Filtered plan-review output failed schema validation. Raw output saved to %s and stderr to %s\n' "$raw_dest" "$stderr_dest" >&2
  exit 3
fi

log_phase "Rendering and persisting findings."
persist_success_outputs "$raw_output_file"
printf '[plan-review] Saved findings to %s\n' "$findings_out" >&2
if [[ -n "$json_out" ]]; then
  printf '[plan-review] Saved JSON to %s\n' "$json_out" >&2
fi
