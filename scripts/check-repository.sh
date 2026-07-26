#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"

failed=0
required=(
  AGENTS.md
  docs/CODEX_QUEUE.md
  docs/IMPLEMENTATION_STATUS.md
  docs/OPEN_DECISIONS.md
  docs/OWNER_ACTIONS.md
  docs/CHANGELOG.md
)

for required_path in "${required[@]}"; do
  if [[ ! -s "$required_path" ]]; then
    print -u2 "Required project-control file is missing or empty: $required_path"
    failed=1
  fi
done

if ! scripts/test-secret-scanner.py || ! scripts/scan-repository-secrets.py .; then
  print -u2 "Repository credential/artifact scanning failed."
  failed=1
fi

if rg -n --hidden -g '!**/.git/**' -g '!**/.build/**' \
  '(TODO|FIXME):?\s*$' SiteForge Tests 2>/dev/null; then
  print -u2 "Empty TODO/FIXME markers are not allowed; include an issue or requirement ID."
  failed=1
fi

if [[ -d .git ]] && ! git diff --check; then
  failed=1
fi

for plist in SiteForge/Info.plist SiteForge/SiteForge.entitlements; do
  if ! plutil -lint "$plist" >/dev/null; then
    print -u2 "Invalid property list: $plist"
    failed=1
  fi
done

if ! scripts/check-traceability.py; then
  failed=1
fi

if ! scripts/check-architecture-boundaries.py; then
  failed=1
fi

if ! scripts/check-authoring-runway.py; then
  failed=1
fi

if ! scripts/check-layout-foundation-evidence.py; then
  failed=1
fi

if ! scripts/check-canvas-renderer-evidence.py; then
  failed=1
fi

if ! scripts/check-selection-model-evidence.py; then
  failed=1
fi

if ! scripts/check-insertion-foundation-evidence.py; then
  failed=1
fi

if ! scripts/check-transform-foundation-evidence.py; then
  failed=1
fi

if ! scripts/select-test-scope.py --self-test; then
  print -u2 "Test-level selection checks failed."
  failed=1
fi

entitlement_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" SiteForge/SiteForge.entitlements 2>/dev/null
}

if [[ "$(entitlement_value com.apple.security.app-sandbox)" != true ]] ||
   [[ "$(entitlement_value com.apple.security.files.user-selected.read-write)" != true ]] ||
   [[ "$(entitlement_value com.apple.security.files.bookmarks.app-scope)" != true ]]; then
  print -u2 "The Release-candidate sandbox entitlement policy is incomplete."
  failed=1
fi

if ! cmp -s SiteForge/SiteForge.entitlements Tests/Fixtures/DistributionPolicy.entitlements; then
  print -u2 "The bundled distribution-policy test fixture has drifted from SiteForge.entitlements."
  failed=1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :UTExportedTypeDeclarations:0:UTTypeIdentifier' SiteForge/Info.plist 2>/dev/null)" != app.siteforge.project-package ]]; then
  print -u2 "The SiteForge project-package document type is missing."
  failed=1
fi

(( failed == 0 )) || exit 1
print "Repository checks passed."
