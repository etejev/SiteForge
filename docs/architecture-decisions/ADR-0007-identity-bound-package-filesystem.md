# ADR-0007 — Identity-bound package and recovery filesystem boundary

- Status: Accepted
- Date: 2026-07-19
- Owners: Product / Engineering
- Requirements: SF-0301-004, SF-0301-005, SF-0306-003, SF-0306-004, SF-1504-003, SF-1504-004, SF-1603-004, SF-1604-004, SF-1702-004
- Findings: M0-P0-02, M0-P0-03, M0-P0-04, filesystem portion of M0-P1-06, M0-P2-10, M0-P2-14

## Context

ADR-0001 selected a deterministic single-file package and ADR-0002 required open/save conflicts to preserve external edits. The original implementation checked paths before reopening them, fingerprinted a package with a second path read, and performed an unconditional final rename. Those boundaries could mix package bytes from one file object with a fingerprint from another, redirect work through a symlink swap, or overwrite a destination changed after conflict validation. Recovery cleanup also needed strong proof that an artifact belonged to the active project.

This decision is bounded to local macOS package and recovery I/O. Security-scoped bookmarks, App Sandbox entitlements, and file coordination for user-selected locations remain assigned to `SF-CORRECTION-005`.

## Decision drivers

- A parsed package and its durable fingerprint must describe one validated file object.
- No path component or final member may redirect I/O through a symbolic link.
- A changed device/inode or changed bytes must fail before SiteForge consumes the external version.
- Failure, interruption, and conflict must preserve external bytes and the canonical in-memory state.
- Input size and metadata work must stay bounded for oversized and sparse files.
- Existing confidentiality metadata must not be silently broadened or discarded.
- Recovery create, replace, and delete must operate only on app-owned storage and project-owned artifacts.
- Race tests must be deterministic and must not depend on scheduling sleeps.

## Decision

`IdentityBoundPackageFileSystem` is the sole byte-level boundary used by `ProjectPackageStore`.

### Validated read snapshot

The parent directory is opened with macOS `O_NOFOLLOW_ANY`, and the final member is opened relative to that descriptor with `O_NOFOLLOW`. Only regular files are accepted. Before allocation, descriptor size is checked against the unchanged 8-MiB package limit. Bytes are read in 64-KiB chunks; a second `fstat` must match the initial device, inode, size, modification time, and change time.

The immutable result contains the exact bytes, SHA-256 digest, byte count, device/inode identity, owner, group, mode, link count, extended ACL text, and bounded approved extended attributes. Package parsing and lifecycle durable state consume that same result. No path is reopened merely to fingerprint previously validated bytes.

### Conditional replacement

Every write creates an exclusive same-directory staging file with mode `0600`, writes and synchronizes deterministic package bytes, applies the approved security metadata, and synchronizes again. Creation commits with `RENAME_EXCL`. Replacement requires the exact previously captured digest, byte count, device, and inode, plus unchanged security metadata immediately before commit. It commits with macOS `RENAME_SWAP`, validates that the displaced object is the expected object, rolls the swap back on mismatch, removes only the proven expected object, and synchronizes the directory.

The opened parent directory identity is revalidated against the destination path before commit. If a path or ancestor is deleted, recreated, replaced, or changed to a symlink, the operation fails without following the replacement or modifying its target. Advisory locks are not treated as a correctness boundary.

### Ownership and confidentiality metadata

New durable and recovery files use owner-only `0600` permissions. Existing durable replacement is permitted only for a regular, single-link file owned by the current effective user. Replacement preserves owner, group, POSIX mode, the complete extended ACL, and this explicit extended-attribute allowlist:

- `app.siteforge.project-identity`
- `com.apple.FinderInfo`
- `com.apple.metadata:_kMDItemUserTags`
- `com.apple.quarantine`

Other extended attributes are not copied implicitly. Attribute-name, attribute-value, and ACL processing are bounded. A policy update requires an ADR amendment and tests.

### Recovery ownership

Recovery storage is the app-owned directory selected by the lifecycle layer, normally below Application Support and injected as a repository-local fixture in tests. The directory must be owned by the current effective user and have no group/world permissions. Recovery files must additionally be owner-restricted, single-link regular files whose validated package project identity matches the recovery key. Delete requires the exact validated candidate fingerprint; unlink failure retains candidate state and returns a typed actionable error. Unrelated, malformed, mismatched, replaced, or symlinked artifacts are preserved.

## Alternatives considered

1. **Path checks plus `Data(contentsOf:)` and `Data.write`.** Rejected because each reopen creates a check/use gap and unbounded fingerprinting bypasses package limits.
2. **Content digest without filesystem identity.** Rejected because delete/recreate with identical bytes is still a different file object and can cross ownership or lifecycle boundaries.
3. **Advisory `flock`.** Rejected as the correctness boundary because other processes need not honor it and it does not bind ancestor path resolution.
4. **Unconditional atomic rename.** Rejected because atomicity alone does not make expected-version validation and replacement conditional.
5. **`NSFileCoordinator` alone.** Deferred to the user-selected access work in `SF-CORRECTION-005`; coordination supports cooperative applications but does not replace descriptor identity and no-follow validation against non-cooperating changes.

## Consequences

### Positive

- Open cannot adopt one package while recording another file's fingerprint.
- Replacement rejects concurrent external changes at the commit boundary and preserves their bytes.
- Symbolic links, ancestor swaps, hard links, foreign ownership, and oversized sparse files have explicit bounded outcomes.
- Existing POSIX and approved macOS confidentiality metadata survives replacement.
- Recovery collision and deletion behavior is typed, retryable, and identity-bound.

### Negative or risky

- The implementation uses macOS-specific descriptor and rename APIs and must remain isolated behind the package store.
- Replacement performs additional metadata reads, synchronization, and post-swap validation.
- The xattr allowlist is intentionally conservative and may need an explicit future compatibility decision.
- This boundary does not claim protection from a privileged process, kernel/filesystem failure, or a process continuously racing after a completed commit.
- App Sandbox scopes, persistent bookmarks, and coordinated user-selected file access are not solved by this ADR.

## Verification

`IdentityBoundFileSystemTests` uses actor barriers at snapshot capture, destination validation, post-swap validation, and recovery deletion. Eleven tests cover source replacement and symlink swap, destination replacement, same-byte delete/recreate with a new inode, destination and ancestor symlink swaps, same-inode modification before commit and after atomic swap, rollback of a changed displaced object, oversized sparse files, hard links and foreign-owner policy, real mode/ACL/xattr preservation, malformed and mismatched recovery collisions, permission-denied deletion with retained-candidate retry, and exact lifecycle/disk preservation. Existing tests retain interruption, static-symlink, deterministic-package, diagnostic-redaction, autosave, reopen, and recovery coverage. `./sf verify` passes with 104 unit tests and 14 UI tests.

## Reversal

The package codec and lifecycle use typed snapshots rather than raw Darwin calls, so a later implementation may replace the internal filesystem mechanism while retaining the same identity and conditional-commit contract. A future package-directory format, coordinated file-access service, or stronger platform primitive must preserve these adversarial tests and provide an explicit migration/ADR.
