#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
review_script="$script_dir/local_review.sh"

if [[ ! -x "$review_script" ]]; then
  echo "Missing executable review script: $review_script" >&2
  exit 2
fi

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/local-review-test.XXXXXX")
cleanup() {
  if [[ -d "$tmp_root" ]]; then
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

repo_dir="$tmp_root/repo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init >/dev/null
git -C "$repo_dir" config user.name "Codex Test"
git -C "$repo_dir" config user.email "codex@example.com"
printf 'base\n' >"$repo_dir/example.txt"
git -C "$repo_dir" add example.txt
git -C "$repo_dir" commit -m "init" >/dev/null
printf 'base\nchange\n' >"$repo_dir/example.txt"

fake_codex="$tmp_root/fake_codex.sh"
cat >"$fake_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${FAKE_CODEX_MODE:-valid}"
schema_seen="false"
shell_disabled="false"
apply_patch_disabled="false"
fast_tier_enabled="false"
medium_reasoning_enabled="false"
profile_value="none"
prompt_arg_seen="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-schema)
      schema_seen="true"
      shift 2
      ;;
    -p)
      profile_value="${2:-}"
      shift 2
      ;;
    -c)
      case "${2:-}" in
        features.shell_tool=false)
          shell_disabled="true"
          ;;
        include_apply_patch_tool=false)
          apply_patch_disabled="true"
          ;;
        service_tier=\"fast\")
          fast_tier_enabled="true"
          ;;
        model_reasoning_effort=\"medium\")
          medium_reasoning_enabled="true"
          ;;
      esac
      shift 2
      ;;
    *)
      if [[ "$1" == *"# Review target"* ]]; then
        prompt_arg_seen="true"
      fi
      shift
      ;;
  esac
done

if [[ "$mode" == "stdin_block" ]]; then
  if [[ "$schema_seen" != "true" || "$shell_disabled" != "true" || "$apply_patch_disabled" != "true" || "$fast_tier_enabled" != "true" || "$medium_reasoning_enabled" != "true" || "$profile_value" != "none" || "$prompt_arg_seen" != "false" ]]; then
    echo "missing bounded-review arguments" >&2
    exit 91
  fi
  sleep 30
  exit 0
fi

prompt_text="$(cat)"
stdin_prompt_seen="false"
if [[ "$prompt_text" == *"# Review target"* && "$prompt_text" == *"# Patch diff"* && "$prompt_text" == *"example.txt"* ]]; then
  stdin_prompt_seen="true"
fi

if [[ "$schema_seen" != "true" || "$shell_disabled" != "true" || "$apply_patch_disabled" != "true" || "$fast_tier_enabled" != "true" || "$medium_reasoning_enabled" != "true" || "$profile_value" != "none" || "$prompt_arg_seen" != "false" || "$stdin_prompt_seen" != "true" ]]; then
  echo "missing bounded-review arguments or stdin prompt" >&2
  exit 91
fi

case "$mode" in
  valid)
    printf '%s\n' '{"summary":"review ok","findings":[{"severity":"P2","file":"example.txt","line":2,"title":"Example issue","description":"Found one issue.","recommendation":"Fix the issue."}]}'
    ;;
  mixed)
    printf '%s\n' '{"summary":"mixed review","findings":[{"severity":"P2","file":"example.txt","line":2,"title":"Blocking issue","description":"Found one blocking issue.","recommendation":"Fix the issue."},{"severity":"P3","file":"example.txt","line":2,"title":"Nonblocking issue","description":"Found one nonblocking issue.","recommendation":"Consider a follow-up."}]}'
    ;;
  invalid)
    printf '%s\n' 'not-json'
    ;;
  recover)
    printf '%s\n' '{"summary":"recovered review","findings":[]}'
    echo "synthetic stderr" >&2
    exit 7
    ;;
  timeout_child)
    if [[ -z "${FAKE_CODEX_CHILD_PID_FILE:-}" ]]; then
      echo "missing FAKE_CODEX_CHILD_PID_FILE" >&2
      exit 95
    fi
    (sleep 30) &
    printf '%s\n' "$!" >"$FAKE_CODEX_CHILD_PID_FILE"
    wait "$!"
    ;;
  *)
    echo "unknown FAKE_CODEX_MODE=$mode" >&2
    exit 92
    ;;
esac
EOF
chmod +x "$fake_codex"

assert_contains() {
  local path="$1"
  local expected="$2"
  if ! grep -Fq "$expected" "$path"; then
    echo "Expected to find '$expected' in $path" >&2
    exit 1
  fi
}

run_valid_case() {
  local stdout_path="$tmp_root/valid.stdout"
  local stderr_path="$tmp_root/valid.stderr"
  local findings_path="$tmp_root/valid-findings.md"
  local json_path="$tmp_root/valid.json"

  (
    cd "$repo_dir"
    CODEX_LOCAL_REVIEW_CODEX_BIN="$fake_codex" \
    CODEX_LOCAL_REVIEW_HEARTBEAT_SECONDS=1 \
    FAKE_CODEX_MODE=valid \
    "$review_script" --tracked-head --print-json --findings-out "$findings_path" --json-out "$json_path"
  ) >"$stdout_path" 2>"$stderr_path"

  jq -e '.summary == "review ok" and (.findings | length == 1)' "$stdout_path" >/dev/null
  jq -e '.summary == "review ok" and (.findings | length == 1)' "$json_path" >/dev/null
  assert_contains "$findings_path" "[P2] Example issue"
  assert_contains "$stderr_path" "Collected review target (tracked_head)."
  assert_contains "$stderr_path" "Running local Codex review with profile=none model=default reasoning=medium sandbox=read-only"
}

run_invalid_case() {
  local stdout_path="$tmp_root/invalid.stdout"
  local stderr_path="$tmp_root/invalid.stderr"
  local findings_path="$tmp_root/invalid-findings.md"
  local raw_path="${findings_path%.md}.raw.txt"
  local child_stderr_path="${findings_path%.md}.stderr.txt"

  set +e
  (
    cd "$repo_dir"
    CODEX_LOCAL_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=invalid \
    "$review_script" --tracked-head --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"
  status=$?
  set -e

  if [[ "$status" -ne 3 ]]; then
    echo "Expected invalid JSON exit 3, got $status" >&2
    exit 1
  fi

  assert_contains "$stderr_path" "returned invalid JSON"
  assert_contains "$raw_path" "not-json"
  [[ -f "$child_stderr_path" ]]
}

run_recovery_case() {
  local stdout_path="$tmp_root/recover.stdout"
  local stderr_path="$tmp_root/recover.stderr"
  local findings_path="$tmp_root/recover-findings.md"
  local child_stderr_path="${findings_path%.md}.stderr.txt"

  (
    cd "$repo_dir"
    CODEX_LOCAL_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=recover \
    "$review_script" --tracked-head --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"

  assert_contains "$stdout_path" "No findings above LOW."
  assert_contains "$stderr_path" "Recovered schema-valid review output after subprocess exit 7."
  assert_contains "$child_stderr_path" "synthetic stderr"
}

run_blocking_only_case() {
  local stdout_path="$tmp_root/blocking.stdout"
  local stderr_path="$tmp_root/blocking.stderr"
  local findings_path="$tmp_root/blocking-findings.md"
  local json_path="$tmp_root/blocking.json"

  (
    cd "$repo_dir"
    CODEX_LOCAL_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=mixed \
    "$review_script" --tracked-head --blocking-only --print-json --findings-out "$findings_path" --json-out "$json_path"
  ) >"$stdout_path" 2>"$stderr_path"

  jq -e '.summary | contains("Minimum severity P2 applied")' "$stdout_path" >/dev/null
  jq -e '(.findings | length == 1) and .findings[0].severity == "P2"' "$stdout_path" >/dev/null
  jq -e '(.findings | length == 1) and .findings[0].severity == "P2"' "$json_path" >/dev/null
  assert_contains "$findings_path" "[P2] Blocking issue"
  if grep -Fq "Nonblocking issue" "$findings_path"; then
    echo "Blocking-only findings should omit nonblocking issue" >&2
    exit 1
  fi
  assert_contains "$stderr_path" "Minimum severity: P2"
}

run_timeout_kills_process_group_case() {
  local stdout_path="$tmp_root/timeout.stdout"
  local stderr_path="$tmp_root/timeout.stderr"
  local findings_path="$tmp_root/timeout-findings.md"
  local child_pid_path="$tmp_root/child.pid"

  set +e
  (
    cd "$repo_dir"
    CODEX_LOCAL_REVIEW_CODEX_BIN="$fake_codex" \
    CODEX_LOCAL_REVIEW_TIMEOUT_SECONDS=1 \
    FAKE_CODEX_MODE=timeout_child \
    FAKE_CODEX_CHILD_PID_FILE="$child_pid_path" \
    "$review_script" --tracked-head --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"
  status=$?
  set -e

  if [[ "$status" -ne 124 ]]; then
    echo "Expected timeout exit 124, got $status" >&2
    exit 1
  fi

  assert_contains "$stderr_path" "timed out after 1 seconds"
  if [[ ! -s "$child_pid_path" ]]; then
    echo "Expected fake child pid file" >&2
    exit 1
  fi
  sleep 1
  if kill -0 "$(cat "$child_pid_path")" 2>/dev/null; then
    echo "Expected timeout to terminate fake Codex child process group" >&2
    exit 1
  fi
}

run_stdin_backpressure_timeout_case() {
  python3 - "$review_script" "$repo_dir" "$fake_codex" "$tmp_root" <<'PY'
import os
import pathlib
import signal
import subprocess
import sys
import time

review_script = pathlib.Path(sys.argv[1])
repo_dir = pathlib.Path(sys.argv[2])
fake_codex = pathlib.Path(sys.argv[3])
tmp_root = pathlib.Path(sys.argv[4])

(repo_dir / "example.txt").write_text("base\n" + ("x" * 1_000_000) + "\n", encoding="utf-8")

stdout_path = tmp_root / "stdin-block.stdout"
stderr_path = tmp_root / "stdin-block.stderr"
findings_path = tmp_root / "stdin-block-findings.md"

env = os.environ.copy()
env.update(
    {
        "CODEX_LOCAL_REVIEW_CODEX_BIN": str(fake_codex),
        "CODEX_LOCAL_REVIEW_MAX_PATCH_BYTES": "0",
        "CODEX_LOCAL_REVIEW_TIMEOUT_SECONDS": "1",
        "FAKE_CODEX_MODE": "stdin_block",
    }
)

with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open("w", encoding="utf-8") as stderr:
    proc = subprocess.Popen(
        [str(review_script), "--tracked-head", "--findings-out", str(findings_path)],
        cwd=repo_dir,
        env=env,
        stdout=stdout,
        stderr=stderr,
        start_new_session=True,
        text=True,
    )
    try:
        status = proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        raise SystemExit("wrapper did not enforce timeout while child ignored stdin")

if status != 124:
    raise SystemExit(f"expected timeout exit 124, got {status}")

stderr_text = stderr_path.read_text(encoding="utf-8")
if "timed out after 1 seconds" not in stderr_text:
    raise SystemExit("missing timeout message for stdin backpressure case")

time.sleep(1)
if proc.poll() is None:
    raise SystemExit("wrapper process still running after timeout")
PY
}

run_valid_case
run_invalid_case
run_recovery_case
run_blocking_only_case
run_timeout_kills_process_group_case
run_stdin_backpressure_timeout_case

printf 'local_review.sh tests passed\n'
