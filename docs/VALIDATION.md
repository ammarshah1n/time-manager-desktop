# Validation

This repo is validated with the native Swift toolchain and packaging scripts that ship with the app.

## Commands

```bash
swift build -c release
swift test
bash scripts/render_screenshots.sh
bash scripts/package_app.sh
codesign --verify --deep --strict dist/timed.app
```

## Latest result

- `swift build -c release`: pass
- `swift test`: pass
- `bash scripts/render_screenshots.sh`: pass
- `bash scripts/package_app.sh`: pass
- `codesign --verify --deep --strict dist/timed.app`: pass

## Coverage notes

- Seqta due-date parsing: covered
- TickTick CSV parsing: covered
- Deduplication: covered
- Completed-task ranking exclusion: covered
- Schedule window cap: covered
- ICS generation: covered
- Prompt boost subject: covered
- Chat persistence: covered

## Output artefacts

- Packaged app: `dist/timed.app`
- Latest release zip: `dist/timed-v0.1.1-macos.zip`
- Screenshot assets: `docs/assets/`
