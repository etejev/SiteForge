# Start here

SiteForge is a native macOS website editor. The
[project status](docs/IMPLEMENTATION_STATUS.md) records what has been
verified. The [work queue](docs/CODEX_QUEUE.md) sets the current priority.

- Use [AGENTS.md](AGENTS.md) and the [specification](docs/SiteForge-Specification.md)
  for development. The [handoff](docs/CODEX_HANDOFF.md) points to the latest
  integration evidence.
- Use **SiteForge Settings → Advanced → Open Testing** to verify changes.
  Start with affected or exact tests. The candidate's **Start UI Smoke Test**
  runs a short editor check once that build is available. Start **Full
  Verification** for major changes, a broad UI redesign, or before an
  owner-requested commit or push.
- See [Testing](docs/TESTING.md) for prerequisites, commands, logs and run ownership.
  On the Mac, `./sf verify` opens the native Testing window. Press
  **Start Full Verification** to start the run.

Development runs through Codex on this Mac. Retired dispatch workflows are
[archived](docs/coordination/archive/). The installed app is updated after
the relevant candidate passes verification.
