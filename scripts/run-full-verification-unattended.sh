#!/bin/zsh
set -uo pipefail

ROOT=${0:A:h:h}
RUN_ROOT="$ROOT/.codex-loop/full-verification"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG_PATH="$RUN_ROOT/verify-$STAMP.log"
STATE_PATH="$RUN_ROOT/verify-$STAMP.state"
RESULT_PATH="$RUN_ROOT/verify-$STAMP.result"
CURRENT_PATH="$RUN_ROOT/current"

mkdir -p "$RUN_ROOT"

write_state() {
  local run_state=$1 phase=$2 detail=$3 progress=${4:-0}
  local temporary="$STATE_PATH.tmp"
  print -r -- "$run_state" > "$temporary"
  print -r -- "$phase" >> "$temporary"
  print -r -- "$detail" >> "$temporary"
  print -r -- "$progress" >> "$temporary"
  mv -f "$temporary" "$STATE_PATH"
}

run_stage() {
  local phase=$1 detail=$2 progress=$3
  shift 3
  write_state RUNNING "$phase" "$detail" "$progress"
  print -r -- "\n[$(date '+%Y-%m-%d %H:%M:%S')] $phase" | tee -a "$LOG_PATH"
  "$@" 2>&1 | tee -a "$LOG_PATH"
  return ${pipestatus[1]}
}

record_stage_result() {
  local key=$1 code=$2
  print -r -- "stage_${key}_exit_code=$code" >> "$RESULT_PATH"
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] stage_result key=$key exit_code=$code" >> "$LOG_PATH"
  if (( code != 0 && overall == 0 )); then overall=$code; fi
}

print -r -- "$STAMP" > "$CURRENT_PATH"
print -r -- "runner_pid=$$" > "$RESULT_PATH"
print -r -- "log=$LOG_PATH" >> "$RESULT_PATH"
print -r -- "state=$STATE_PATH" >> "$RESULT_PATH"
write_state RUNNING "Preparing full verification" "Keep this Mac awake and unlocked for UI automation." 2

nohup xcrun swift "$ROOT/scripts/full-verification-progress.swift" "$STATE_PATH" "$LOG_PATH" \
  > "$RUN_ROOT/progress-$STAMP.log" 2>&1 &

completed=0
finish_interrupted() {
  (( completed )) && return
  write_state ISSUES "Full verification interrupted" "The verifier ended before ./sf verify produced a final result." 100
  print -r -- "status=INTERRUPTED" >> "$RESULT_PATH"
  print -r -- "exit_code=130" >> "$RESULT_PATH"
  print -r -- "finished_at=$(date -Iseconds)" >> "$RESULT_PATH"
}
interrupt_and_exit() {
  finish_interrupted
  completed=1
  exit 130
}
trap finish_interrupted EXIT
trap interrupt_and_exit INT TERM HUP

overall=0
if run_stage "Full verification" "Repository checks, build, unit/integration tests, and macOS UI automation are running." 12 \
  "$ROOT/sf" verify; then
  stage_exit=0
else
  stage_exit=$?
fi
record_stage_result verify "$stage_exit"

if (( overall == 0 )); then
  write_state PASSED "Full verification passed" "Repository checks, build, and the complete test suite finished successfully." 100
  print -r -- "status=PASSED" >> "$RESULT_PATH"
else
  write_state ISSUES "Verification completed with issues" "Every independently runnable stage was attempted. Open the log for exact diagnostics." 100
  print -r -- "status=COMPLETED_WITH_ISSUES" >> "$RESULT_PATH"
fi

print -r -- "exit_code=$overall" >> "$RESULT_PATH"
print -r -- "finished_at=$(date -Iseconds)" >> "$RESULT_PATH"
completed=1
# Every independently runnable stage is attempted, while callers still receive
# the first real failing stage code after the complete result has been written.
exit "$overall"
