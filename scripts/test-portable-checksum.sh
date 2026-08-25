#!/bin/zsh
set -euo pipefail

# SF-1802-008, SF-1804-008 — a local-alpha checksum must not retain a
# machine-specific path and must remain verifiable after both files move.
ROOT=${0:A:h:h}
fixture=$(mktemp -d "${TMPDIR%/}/siteforge-portable-checksum.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

original_directory="$fixture/original/private/machine/path"
moved_directory="$fixture/moved"
mkdir -p "$original_directory" "$moved_directory"

archive_name=SiteForge-test-unsigned-alpha.zip
archive="$original_directory/$archive_name"
checksum="$archive.sha256"
print -n 'portable release artifact' > "$archive"

/bin/zsh "$ROOT/scripts/write-portable-checksum.sh" "$archive"
checksum_text=$(<"$checksum")
[[ "$checksum_text" == *"  $archive_name" ]] || {
  print -u2 "Checksum does not contain the archive basename."
  exit 1
}
[[ "$checksum_text" != *"$original_directory"* ]] || {
  print -u2 "Checksum leaked its original machine path."
  exit 1
}

mv "$archive" "$moved_directory/$archive_name"
mv "$checksum" "$moved_directory/$archive_name.sha256"
(
  cd "$moved_directory"
  shasum -a 256 -c "$archive_name.sha256" >/dev/null
)

print "Portable local-alpha checksum tests passed."
