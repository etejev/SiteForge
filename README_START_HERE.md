# SiteForge Codex Starter Kit

This folder is designed to become the root of the SiteForge Git repository.

## First use

1. Copy the contents into the SiteForge repository root.
2. Keep the specification files in `docs/`.
3. Initialize Git and create a private GitHub repository if desired.
4. Run `./sf status`.
5. Run `./sf next` to let Codex take one ready work item, or `./sf loop 3` for up to three verified iterations.

## Everyday commands

```text
./sf dev
./sf verify
./sf watch
./sf next
./sf loop 5
./sf status
```

`./sf watch` continuously rebuilds and tests after source changes. `./sf loop` lets Codex edit the repository in bounded iterations. It stops for an owner decision, failed verification, an empty queue, or the requested iteration limit.

## Safety model

Codex receives workspace-write access, not unrestricted machine access. Repository instructions prohibit releases, signing, notarization, purchases, external publication, and credential handling without owner authorization.

The unsigned-alpha GitHub workflow creates a temporary workflow artifact only. It does not publish a GitHub Release.

