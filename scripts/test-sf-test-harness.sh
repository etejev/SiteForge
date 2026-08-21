#!/bin/zsh
set -euo pipefail

# Focused regression checks for sf's capability-aware UI test lifecycle. They
# use only a temporary PATH shim: no real Xcode process is launched.
ROOT=${0:A:h:h}
TMP=$(mktemp -d "${TMPDIR%/}/siteforge-sf-harness.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"

write_fake() {
  local name=$1 body=$2
  print -r -- "$body" > "$TMP/bin/$name"
  chmod +x "$TMP/bin/$name"
}

write_fake xcodebuild '#!/bin/zsh
print -- "xcodebuild invoked" >> "$SITEFORGE_HARNESS_MARKER"
exit "${SITEFORGE_FAKE_XCODE_STATUS:-0}"'

write_fake ps '#!/bin/zsh
if [[ "${SITEFORGE_FAKE_PS_MODE:-success}" == denied ]]; then
  print -u2 "operation not permitted"
  exit 1
fi
count=0
[[ -f "$SITEFORGE_FAKE_PS_STATE" ]] && count=$(<"$SITEFORGE_FAKE_PS_STATE")
count=$((count + 1))
print -- "$count" > "$SITEFORGE_FAKE_PS_STATE"
# The capability probe is the first invocation. The second is stale cleanup;
# later calls emulate the process exiting after TERM.
if (( count == 2 )); then
  print "123 /tmp/SiteForge/DerivedData/SiteForgeUITests-Runner"
  print "456 /Applications/Unrelated.app/Contents/MacOS/Unrelated"
fi'

run_case() {
  local mode=$1
  local xcode_status=$2
  local marker="$TMP/$mode.marker"
  local output="$TMP/$mode.output"
  set +e
  PATH="$TMP/bin:$PATH" SITEFORGE_FAKE_PS_MODE="$mode" SITEFORGE_FAKE_XCODE_STATUS="$xcode_status" \
    SITEFORGE_HARNESS_MARKER="$marker" SITEFORGE_FAKE_PS_STATE="$TMP/$mode.ps-count" SITEFORGE_DERIVED_DATA="/tmp/SiteForge/DerivedData" \
    "$ROOT/sf" test quick >"$output" 2>&1
  local result=$?
  set -e
  [[ -f "$marker" ]] || { print -u2 "xcodebuild was not invoked for $mode"; return 1; }
  print -- "$result:$output"
}

# A successful ps preserves narrow repository-derived-data matching and never
# selects the unrelated process emitted by the shim.
success=$(run_case success 0)
[[ ${success%%:*} == 0 ]]
grep -q "Terminating stale SiteForge UI-test processes: 123" "${success#*:}"
! grep -q "456" "${success#*:}"

# Permission denial must not abort before xcodebuild, while a real xcodebuild
# failure still propagates unchanged and the capability warning is concise.
denied=$(run_case denied 19)
[[ ${denied%%:*} == 19 ]]
grep -q "process enumeration is unavailable" "${denied#*:}"
[[ $(grep -c "process enumeration is unavailable" "${denied#*:}") == 1 ]]

print "sf UI-test harness regression checks passed"
