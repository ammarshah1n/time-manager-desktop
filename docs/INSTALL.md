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

## Local install from source

```bash
swift build -c release
bash scripts/package_app.sh
bash scripts/install_app.sh
```

The packaging script creates an ad-hoc signed bundle at `dist/timed.app`.
