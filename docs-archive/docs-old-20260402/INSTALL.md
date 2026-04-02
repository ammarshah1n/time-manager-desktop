# Install Timed

## Fast path

1. Open the latest GitHub Release.
2. Download `timed-vX.Y.Z-macos.zip`.
3. Unzip it.
4. Drag `timed.app` into `/Applications`.
5. Launch `Timed`.

## First launch

- Open `Timed`.
- If macOS asks for Calendar permission, allow it if you want approved study blocks to sync to Apple Calendar.
- Open `Timed > Settings…` with `Cmd+,` if the Codex CLI is not at the default path.
- Import school work from Seqta or TickTick, then ask Timed what to do next.

## AI trust note

- Timed does not call a hosted AI API directly.
- It shells out to the local Codex executable path configured in Settings.
- That means your planner and quiz prompts are only as private as the Codex backend you choose to install.
- If you switch the executable to a different wrapper or remote backend, review that tool's privacy and network behaviour first.

## Local install from source

```bash
swift build -c release
bash scripts/package_app.sh
bash scripts/install_app.sh
```

The packaging script creates an ad-hoc signed bundle at `dist/timed.app`.

## Notarized distribution

For broader macOS distribution beyond local or trusted devices:

```bash
TIMED_NOTARY_PROFILE=timed-notary bash scripts/notarize_app.sh
```

That script submits the packaged app with `notarytool`, staples the ticket, and runs `spctl` assessment on the result.
