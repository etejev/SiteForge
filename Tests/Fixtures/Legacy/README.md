# Legacy project-package goldens

These Base64 files are immutable byte-for-byte SiteForge package-v1 fixtures whose canonical payload uses document schema v1. They were produced once from the documented `SFPKG001` container layout, not through the current production encoder, and are decoded to raw package bytes by the migration tests.

| Fixture | Purpose | Decoded package SHA-256 |
|---|---|---|
| `schema-v1-empty.siteforge.b64` | Legacy document with an empty page list | `b5a46c3ddc705b978324e17a5e0b9912155950b2a7c05b36e07117bae4d98576` |
| `schema-v1-rootless.siteforge.b64` | Legacy page with stable identity but no roots or nodes | `ef1455c5eb9055ec97fb5d41562686226e9db040313a4609e769cc5f7f44694d` |

The source metadata is fixed at 2026-07-19, package format/version 1, document schema 1, and deterministic UUIDs in the `11…`, `21…`, and `31…` namespaces. Changing any decoded byte requires an explicit compatibility review, new checksum, and retained prior fixture.
