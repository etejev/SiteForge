# SiteForge

Local verification requires full Xcode and an isolated, pinned image-check
runtime. Before the first `./sf verify` or `./sf testing full`, run
`/bin/zsh scripts/setup-verification-runtime.sh`. This installs only the declared
`scripts/verification-requirements.txt` into ignored `.build/verification-python`;
it does not modify global Python packages. Missing/outdated prerequisites fail
with this setup command before unattended tests launch. A compatible bootstrap
Python may be selected with `SITEFORGE_VERIFICATION_BOOTSTRAP_PYTHON`.
A macOS interactive HTML editor.

Local development and verification commands are documented in
[`docs/TESTING.md`](docs/TESTING.md).
