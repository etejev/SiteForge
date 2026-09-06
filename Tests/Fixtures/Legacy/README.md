# Legacy project-package goldens

`schema-v5-blank-document.json` is an immutable canonical document emitted by the schema-v5 encoder at `70e7c42`. It exercises schema-v6 adaptation without introducing Button or Link nodes into historical data. Its document, page, and root identities must survive migration unchanged.

These Base64 files are immutable byte-for-byte SiteForge package-v1 fixtures whose canonical payload uses a supported historical document schema. They were produced once from the documented `SFPKG001` container layout, not through the current production encoder, and are decoded to raw package bytes by the migration tests.

| Fixture | Purpose | Decoded package SHA-256 |
|---|---|---|
| `schema-v1-empty.siteforge.b64` | Legacy document with an empty page list | `b5a46c3ddc705b978324e17a5e0b9912155950b2a7c05b36e07117bae4d98576` |
| `schema-v1-rootless.siteforge.b64` | Legacy page with stable identity but no roots or nodes | `ef1455c5eb9055ec97fb5d41562686226e9db040313a4609e769cc5f7f44694d` |
| `schema-v2-minimum.siteforge.b64` | Schema-v2 document with explicit current-at-the-time page metadata and no authored guides | `c2ebf92c01924cccd9fe6db5a48bbe4d23a6273d03526f41ed5f744efcbe7739` |
| `schema-v4-legacy-surface.siteforge.b64` | Historical schema-v4 package using the pre-SF-AUTHORING-012 defaulted `style.fill = surface` representation | `3ab14ab513e8932395579540750016e3a73f4742e9d463574c6443b3f4303b12` |

The source metadata is fixed at 2026-07-19 for schemas 1 and 2 and 2026-08-13 for the schema-v4 historical style fixture. All packages use format/version 1 and deterministic UUID namespaces. Changing any decoded byte requires an explicit compatibility review, new checksum, and retained prior fixture.
