# DOOYOU Folder Map

This folder is the project-level operating map for DOOYOU. It separates product
intent, install flow, connector behavior, and roadmap so the app can grow into a
personal coordination layer without burying decisions inside chat history.

## Repo Structure

- `Sources/dooyou/`: Swift source for the menu bar app, popover, dashboard,
  scanners, preferences, connectors, and mascot rendering.
- `Sources/dooyou/Resources/`: bundled bitmap frames for the main Dooyou mascot.
- `script/`: build, install, package, uninstall, and remote-install entrypoints.
- `dist/`: generated app bundle and release zip output. This folder is not the
  source of truth.
- `.codex/environments/`: local Codex app Run action wired to
  `script/build_and_run.sh`.
- `docs/`: product and operations documentation.

## Documents

- `DOOYOU_SUMMARY.md`: what has been built and the current product shape.
- `INSTALL_AND_OPERATIONS.md`: local install, login persistence, remote install,
  packaging, and Tailscale notes.
- `CONNECTORS_AND_ACCOUNTS.md`: CLI/API/MCP connector behavior and multi-account
  route model.
- `ROADMAP.md`: personal coordinator direction and next product lanes.

## Source Of Truth

The repository source of truth is the SwiftPM package plus these docs. Generated
artifacts under `dist/` can always be recreated with:

```bash
./script/build_and_run.sh --build-only
./script/package_release.sh
```
