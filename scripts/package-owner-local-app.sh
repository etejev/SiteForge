#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
/bin/zsh "$ROOT/scripts/verification-python.sh" --check
OUT="$ROOT/.build/owner-local"
DERIVED="$OUT/DerivedData"
mkdir -p "$OUT"
source_fingerprint() {
  /usr/bin/python3 - "$ROOT" <<'PY'
import runpy, sys
from pathlib import Path
root = Path(sys.argv[1])
policy = runpy.run_path(str(root / "scripts/unattended-verification.py"), run_name="siteforge_fingerprint")
print(policy["source_fingerprint"](root))
PY
}
SOURCE_REVISION=$(git -C "$ROOT" rev-parse HEAD)
SOURCE_FINGERPRINT=$(source_fingerprint)
SOURCE_DIRTY=false
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || SOURCE_DIRTY=true
BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOCAL_BUILD_VERSION="$(date -u +%y.%m.%d)"
# This explicitly authorized local build never runs repository checks or tests.
xcodebuild -project "$ROOT/SiteForge.xcodeproj" -target SiteForge -configuration Debug \
  SYMROOT="$DERIVED/Products" OBJROOT="$DERIVED/Intermediates" \
  PRODUCT_BUNDLE_IDENTIFIER=app.siteforge.SiteForge \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  INFOPLIST_KEY_CFBundleDisplayName=SiteForge build
[[ "$(source_fingerprint)" == "$SOURCE_FINGERPRINT" ]] || { print -u2 "Source changed during the build; no artifact was packaged."; exit 1; }
APP="$DERIVED/Products/Debug/SiteForge.app"
[[ -d "$APP" ]] || { print -u2 "OwnerLocal app was not produced."; exit 1; }
# Document-provider/Finder metadata can reappear while a bundle remains inside
# the source folder. Package/sign a clean copy in a unique temporary directory.
PACKAGE_ROOT=$(mktemp -d "${TMPDIR%/}/siteforge-owner-local-package.XXXXXXXX")
trap 'if [[ "$PACKAGE_ROOT" == "${TMPDIR%/}/siteforge-owner-local-package."* ]]; then rm -rf -- "$PACKAGE_ROOT"; fi' EXIT
CLEAN_APP="$PACKAGE_ROOT/SiteForge.app"
ditto --norsrc --noextattr --noacl "$APP" "$CLEAN_APP"
APP="$CLEAN_APP"
RESOURCES="$APP/Contents/Resources/OwnerTesting"
mkdir -p "$RESOURCES"
cp "$ROOT/scripts/unattended-verification.py" "$RESOURCES/unattended-verification.py"
xcrun swiftc -swift-version 6 "$ROOT/scripts/full-verification-progress.swift" \
  -o "$RESOURCES/SiteForgeTestingProgress"
/usr/bin/python3 - "$ROOT" "$SOURCE_FINGERPRINT" "$RESOURCES/installation.json" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[3]).write_text(json.dumps({"version": 1, "sourceRoot": sys.argv[1], "sourceFingerprint": sys.argv[2]}) + "\n")
PY
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $LOCAL_BUILD_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName SiteForge' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SiteForgeSourceRevision string $SOURCE_REVISION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SiteForgeSourceFingerprint string $SOURCE_FINGERPRINT" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SiteForgeSourceDirty bool $SOURCE_DIRTY" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SiteForgeLocalBuildTimestamp string $BUILD_TIMESTAMP" "$APP/Contents/Info.plist"
# Local ad-hoc identity only; no Developer ID, entitlement changes or notarization.
xattr -cr "$APP"
codesign --force --sign - "$APP"
STAGED="$OUT/SiteForge.app"
if [[ -d "$STAGED" ]]; then
  BACKUP="$ROOT/.build/local-app-backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP"
  mv "$STAGED" "$BACKUP/SiteForge OwnerLocal.bundle-backup"
fi
ditto --norsrc --noextattr --noacl "$APP" "$STAGED"
print "Prepared owner-local local app: $STAGED"
print "No tests, publication, distribution signing or installation were performed."
print "Local build: $LOCAL_BUILD_VERSION · source $SOURCE_REVISION · dirty $SOURCE_DIRTY · fingerprint $SOURCE_FINGERPRINT"
if [[ "${1:-}" == "--install" ]]; then
  INSTALLED=/Applications/SiteForge.app
  # Never replace an active bundle: quitting/unsaved-document decisions belong
  # to the real app, not a process-wide termination command.
  ps -axo pid=,command= >/dev/null 2>&1 || { print -u2 "Cannot inspect active app ownership; installation was not attempted."; exit 2; }
  siteforge_process_snapshot=$(ps -axo command=) || { print -u2 "Process ownership became unavailable; installed app unchanged."; exit 2; }
  if print -r -- "$siteforge_process_snapshot" | awk '$1 == "/Applications/SiteForge.app/Contents/MacOS/SiteForge" || $1 == "/System/Volumes/Data/Applications/SiteForge.app/Contents/MacOS/SiteForge" { found=1 } END { exit !found }'; then
    print -u2 "The installed SiteForge app is running. Save your work and quit it normally before updating."; exit 2
  fi
  [[ ! -L "$INSTALLED" ]] || { print -u2 "Refusing to replace a linked application path."; exit 2; }
  if [[ -d "$INSTALLED" ]]; then
    [[ -f "$INSTALLED/Contents/Info.plist" ]] || { print -u2 "Installed bundle metadata is missing; destination unchanged."; exit 2; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED/Contents/Info.plist")" == app.siteforge.SiteForge ]] || {
      print -u2 "The destination is not the intended SiteForge bundle."; exit 2
    }
    INSTALLED_BACKUP="$HOME/Library/Application Support/SiteForge/ApplicationBackups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$INSTALLED_BACKUP"
    # Preserve a recovery copy before changing the installed path.
    ditto --norsrc --noextattr --noacl "$INSTALLED" "$INSTALLED_BACKUP/SiteForge.bundle-backup"
  fi
  INSTALL_STAGE=$(mktemp -d /Applications/.siteforge-owner-install.XXXXXXXX)
  ditto --norsrc --noextattr --noacl "$STAGED" "$INSTALL_STAGE/SiteForge.app"
  codesign --verify --strict "$INSTALL_STAGE/SiteForge.app"
  siteforge_process_snapshot=$(ps -axo command=) || { print -u2 "Cannot confirm final process ownership; prepared update retained at $INSTALL_STAGE."; exit 2; }
  if print -r -- "$siteforge_process_snapshot" | awk '$1 == "/Applications/SiteForge.app/Contents/MacOS/SiteForge" || $1 == "/System/Volumes/Data/Applications/SiteForge.app/Contents/MacOS/SiteForge" { found=1 } END { exit !found }'; then
    print -u2 "SiteForge became active; prepared update retained at $INSTALL_STAGE. Installed app unchanged."; exit 2
  fi
  if [[ -d "$INSTALLED" ]]; then
    mv "$INSTALLED" "$INSTALL_STAGE/Previous.bundle-backup"
  fi
  if ! mv "$INSTALL_STAGE/SiteForge.app" "$INSTALLED"; then
    [[ ! -d "$INSTALL_STAGE/Previous.bundle-backup" ]] || mv "$INSTALL_STAGE/Previous.bundle-backup" "$INSTALLED"
    print -u2 "Installation failed; previous bundle restored."; exit 2
  fi
  print "Installed owner-local regular app: $INSTALLED"
  print "Previous bundle preserved recoverably; no running app or document was terminated."
fi
