#!/bin/zsh
set -euo pipefail

[[ $# -eq 1 ]] || {
  print -u2 "Usage: write-portable-checksum.sh <archive>"
  exit 2
}

archive=${1:A}
[[ -f "$archive" ]] || {
  print -u2 "Archive does not exist: $archive"
  exit 1
}

archive_directory=${archive:h}
archive_name=${archive:t}
(
  cd "$archive_directory"
  shasum -a 256 "$archive_name" > "$archive_name.sha256"
)
