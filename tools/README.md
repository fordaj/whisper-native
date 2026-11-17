# Bundled tools

```mermaid
flowchart LR
    Env[scripts/env.sh] --> Pin[scripts/.common.env<br/>pins]
    Pin --> RS[tools/runner-spawner/v0.0.1.2.6]
    RS --> Binaries[per-platform runner-spawner]
```

Pinned helper binaries, checked into the repository and wired into the
environment cascade as `RUNNER_SPAWNER_BIN` (resolved per-platform by
`scripts/.common.env` + `scripts/.<platform>.env`).

## runner-spawner (fordaj/runner-spawner)

Repository-scoped self-hosted GitHub Actions runner lifecycle manager,
pinned at **v0.0.1.2.6**. Configuration for this repo lives in
`.runner-spawner.json` at the repository root. See the upstream README
for details; the common flow:

```bash
source scripts/env.sh
"$RUNNER_SPAWNER_BIN" --help
"$RUNNER_SPAWNER_BIN" create          # register + install the configured runners
"$RUNNER_SPAWNER_BIN" list|status
```

Refresh the bundle with `tools/runner-spawner/update.sh` (re-downloads the
pinned release and verifies the published checksums). Do not run `create`
unless you intend to register runners against `fordaj/whisper-native`.
