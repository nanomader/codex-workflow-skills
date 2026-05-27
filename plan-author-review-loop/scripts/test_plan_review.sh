#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
review_script="$script_dir/plan_review.sh"

if [[ ! -x "$review_script" ]]; then
  echo "Missing executable review script: $review_script" >&2
  exit 2
fi

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/plan-review-test.XXXXXX")
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

plan_path="$repo_dir/PLAN.md"
cat >"$plan_path" <<'EOF'
# Objective

Change example.txt safely.

# Tests

Run `true`.
EOF

fake_codex="$tmp_root/fake_codex.sh"
cat >"$fake_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${FAKE_CODEX_MODE:-mixed}"
schema_seen="false"
shell_disabled="false"
apply_patch_disabled="false"
fast_tier_enabled="false"
medium_reasoning_enabled="false"
sandbox_value=""
profile_value="none"

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
    -s)
      sandbox_value="${2:-}"
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
      shift
      ;;
  esac
done

if [[ "$schema_seen" != "true" || "$apply_patch_disabled" != "true" || "$fast_tier_enabled" != "true" || "$medium_reasoning_enabled" != "true" || "$sandbox_value" != "read-only" || "$profile_value" != "none" ]]; then
  echo "missing bounded-plan-review arguments" >&2
  exit 91
fi

case "$mode" in
  mixed)
    if [[ "$shell_disabled" != "true" ]]; then
      echo "shell should be disabled by default" >&2
      exit 92
    fi
    printf '%s\n' '{"summary":"mixed review","findings":[{"severity":"P2","file":"PLAN.md","line":5,"title":"Missing caller test","description":"The plan only names a helper-level test.","recommendation":"Add a caller-level smoke test."},{"severity":"LOW","file":"PLAN.md","line":1,"title":"Tighten title","description":"The title could be clearer.","recommendation":"Rename the objective."}]}'
    ;;
  allow_tools)
    if [[ "$shell_disabled" == "true" ]]; then
      echo "shell should be available when --allow-readonly-tools is used" >&2
      exit 93
    fi
    printf '%s\n' '{"summary":"readonly tool review ok","findings":[]}'
    ;;
  invalid)
    printf '%s\n' 'not-json'
    ;;
  valid_then_error)
    printf '%s\n' '{"summary":"valid output before error","findings":[]}'
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
    exit 94
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

run_blocking_only_case() {
  local stdout_path="$tmp_root/blocking.stdout"
  local stderr_path="$tmp_root/blocking.stderr"
  local findings_path="$tmp_root/blocking-findings.md"
  local json_path="$tmp_root/blocking.json"

  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=mixed \
    "$review_script" --plan-file "$plan_path" --blocking-only --print-json --findings-out "$findings_path" --json-out "$json_path"
  ) >"$stdout_path" 2>"$stderr_path"

  jq -e '.summary | contains("Minimum severity P2 applied")' "$stdout_path" >/dev/null
  jq -e '(.findings | length == 1) and .findings[0].severity == "P2"' "$stdout_path" >/dev/null
  jq -e '(.findings | length == 1) and .findings[0].severity == "P2"' "$json_path" >/dev/null
  assert_contains "$findings_path" "[P2] Missing caller test"
  if grep -Fq "Tighten title" "$findings_path"; then
    echo "Blocking-only findings should omit LOW issue" >&2
    exit 1
  fi
  assert_contains "$stderr_path" "Running Codex plan review with profile=none model=default reasoning=medium sandbox=read-only tools=disabled"
}

run_allow_tools_case() {
  local stdout_path="$tmp_root/allow.stdout"
  local stderr_path="$tmp_root/allow.stderr"
  local findings_path="$tmp_root/allow-findings.md"

  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=allow_tools \
    "$review_script" --plan-file "$plan_path" --allow-readonly-tools --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"

  assert_contains "$stdout_path" "No findings above LOW."
  assert_contains "$stderr_path" "tools=readonly"
}

run_invalid_case() {
  local stdout_path="$tmp_root/invalid.stdout"
  local stderr_path="$tmp_root/invalid.stderr"
  local findings_path="$tmp_root/invalid-findings.md"
  local raw_path="${findings_path%.md}.raw.txt"

  set +e
  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=invalid \
    "$review_script" --plan-file "$plan_path" --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"
  status=$?
  set -e

  if [[ "$status" -ne 3 ]]; then
    echo "Expected invalid JSON exit 3, got $status" >&2
    exit 1
  fi

  assert_contains "$stderr_path" "returned invalid JSON"
  assert_contains "$raw_path" "not-json"
}

run_payload_guard_case() {
  local stdout_path="$tmp_root/payload.stdout"
  local stderr_path="$tmp_root/payload.stderr"
  local findings_path="$tmp_root/payload-findings.md"

  set +e
  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=mixed \
    "$review_script" --plan-file "$plan_path" --max-payload-bytes 1 --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"
  status=$?
  set -e

  if [[ "$status" -ne 2 ]]; then
    echo "Expected payload guard exit 2, got $status" >&2
    exit 1
  fi

  assert_contains "$stderr_path" "above limit 1"
}

run_nonzero_valid_json_fails_case() {
  local stdout_path="$tmp_root/nonzero.stdout"
  local stderr_path="$tmp_root/nonzero.stderr"
  local findings_path="$tmp_root/nonzero-findings.md"
  local raw_path="${findings_path%.md}.raw.txt"

  set +e
  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=valid_then_error \
    "$review_script" --plan-file "$plan_path" --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"
  status=$?
  set -e

  if [[ "$status" -ne 7 ]]; then
    echo "Expected nonzero child exit 7, got $status" >&2
    exit 1
  fi

  assert_contains "$stderr_path" "failed with exit 7"
  assert_contains "$raw_path" "valid output before error"
}

run_dirty_state_guard_case() {
  local stdout_path="$tmp_root/dirty.stdout"
  local stderr_path="$tmp_root/dirty.stderr"
  local findings_path="$tmp_root/dirty-findings.md"

  printf 'base\ndirty\n' >"$repo_dir/example.txt"
  set +e
  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=mixed \
    "$review_script" --plan-file "$plan_path" --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"
  status=$?
  set -e
  git -C "$repo_dir" checkout -- example.txt

  if [[ "$status" -ne 2 ]]; then
    echo "Expected dirty state guard exit 2, got $status" >&2
    exit 1
  fi

  assert_contains "$stderr_path" "Refusing to review with unrelated dirty paths"
  assert_contains "$stderr_path" "example.txt"
}

run_allow_dirty_case() {
  local stdout_path="$tmp_root/allow-dirty.stdout"
  local stderr_path="$tmp_root/allow-dirty.stderr"
  local findings_path="$tmp_root/allow-dirty-findings.md"

  printf 'base\ndirty\n' >"$repo_dir/example.txt"
  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    FAKE_CODEX_MODE=mixed \
    "$review_script" --plan-file "$plan_path" --allow-dirty --blocking-only --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"
  git -C "$repo_dir" checkout -- example.txt

  assert_contains "$stdout_path" "[P2] Missing caller test"
  assert_contains "$stderr_path" "Unrelated dirty paths allowed"
}

run_sandbox_env_ignored_case() {
  local stdout_path="$tmp_root/sandbox.stdout"
  local stderr_path="$tmp_root/sandbox.stderr"
  local findings_path="$tmp_root/sandbox-findings.md"

  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    CODEX_PLAN_REVIEW_SANDBOX=workspace-write \
    FAKE_CODEX_MODE=mixed \
    "$review_script" --plan-file "$plan_path" --blocking-only --findings-out "$findings_path"
  ) >"$stdout_path" 2>"$stderr_path"

  assert_contains "$stdout_path" "[P2] Missing caller test"
  assert_contains "$stderr_path" "sandbox=read-only"
}

run_timeout_kills_process_group_case() {
  local stdout_path="$tmp_root/timeout.stdout"
  local stderr_path="$tmp_root/timeout.stderr"
  local findings_path="$tmp_root/timeout-findings.md"
  local child_pid_path="$tmp_root/child.pid"

  set +e
  (
    cd "$repo_dir"
    CODEX_PLAN_REVIEW_CODEX_BIN="$fake_codex" \
    CODEX_PLAN_REVIEW_TIMEOUT_SECONDS=1 \
    FAKE_CODEX_MODE=timeout_child \
    FAKE_CODEX_CHILD_PID_FILE="$child_pid_path" \
    "$review_script" --plan-file "$plan_path" --findings-out "$findings_path"
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

run_interrupt_kills_process_group_case() {
  python3 - "$review_script" "$repo_dir" "$plan_path" "$fake_codex" "$tmp_root" <<'PY'
import os
import pathlib
import signal
import subprocess
import sys
import time

review_script = pathlib.Path(sys.argv[1])
repo_dir = pathlib.Path(sys.argv[2])
plan_path = pathlib.Path(sys.argv[3])
fake_codex = pathlib.Path(sys.argv[4])
tmp_root = pathlib.Path(sys.argv[5])

child_pid_path = tmp_root / "interrupt-child.pid"
stdout_path = tmp_root / "interrupt.stdout"
stderr_path = tmp_root / "interrupt.stderr"
findings_path = tmp_root / "interrupt-findings.md"

env = os.environ.copy()
env.update(
    {
        "CODEX_PLAN_REVIEW_CODEX_BIN": str(fake_codex),
        "FAKE_CODEX_MODE": "timeout_child",
        "FAKE_CODEX_CHILD_PID_FILE": str(child_pid_path),
    }
)

with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open("w", encoding="utf-8") as stderr:
    proc = subprocess.Popen(
        [str(review_script), "--plan-file", str(plan_path), "--findings-out", str(findings_path)],
        cwd=repo_dir,
        env=env,
        stdout=stdout,
        stderr=stderr,
        start_new_session=True,
        text=True,
    )

    deadline = time.time() + 5
    while time.time() < deadline and not child_pid_path.exists():
        if proc.poll() is not None:
            raise SystemExit(f"wrapper exited before child pid was written: {proc.returncode}")
        time.sleep(0.05)

    if not child_pid_path.exists():
        os.killpg(proc.pid, signal.SIGKILL)
        raise SystemExit("fake child pid was not written")

    os.killpg(proc.pid, signal.SIGINT)
    try:
        status = proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        raise SystemExit("wrapper did not exit after SIGINT")

if status not in (130, -signal.SIGINT):
    raise SystemExit(f"expected interrupt status, got {status}")

time.sleep(1)
child_pid = int(child_pid_path.read_text(encoding="utf-8").strip())
try:
    os.kill(child_pid, 0)
except ProcessLookupError:
    pass
else:
    raise SystemExit("expected interrupt to terminate fake Codex child process group")
PY
}

run_blocking_only_case
run_allow_tools_case
run_invalid_case
run_payload_guard_case
run_nonzero_valid_json_fails_case
run_dirty_state_guard_case
run_allow_dirty_case
run_sandbox_env_ignored_case
run_timeout_kills_process_group_case
run_interrupt_kills_process_group_case

printf 'plan_review.sh tests passed\n'
