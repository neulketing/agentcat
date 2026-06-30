# dooyou

Tiny macOS menu bar monitor with a running mascot for local AI-agent activity.

The main mascot, `두유`, is based on a Coton de Tulear puppy. The dashboard keeps
the visible mascot set intentionally small: `두유`, `고양이`, and `거북이`, each
with its own role and motion language instead of simple color variants.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools or Xcode with Swift 5.9+

## Install From Source

```bash
git clone <repo-url>
cd dooyou
./script/build_and_run.sh
```

## Local Run

```bash
./script/build_and_run.sh
```

## Start At Login

Install the app into `/Applications/dooyou.app` and enable the per-user LaunchAgent:

```bash
./script/install_login_item.sh
```

Disable login launch:

```bash
./script/uninstall_login_item.sh
```

## Connect Providers And Tools

Open the menu bar popover or dashboard to check built-in Claude, Codex, and GLM
connection status. Claude and Codex default to CLI plus API setup. GLM defaults
to `ZAI_API_KEY` API setup plus local `glm-*` usage detection. The dashboard also
supports custom connectors for more tools:

- Basic install: Claude, Codex, and other CLIs are optional. If they are not
  installed, dooyou starts normally and marks them as unavailable instead of
  failing setup.
- Auto discovery: when a supported CLI exists on `PATH`, dooyou shows it in the
  dashboard and enables a login button for that tool.
- CLI: opens Terminal and runs the configured login or launch command.
- API key: stores the key in the macOS login Keychain under `local.dooyou.api-key`.
- MCP: stores a local MCP command or MCP/documentation URL and exposes it from
  the dashboard.
- Local data: optionally points a connector at a local transcript/cache folder.

The app reads local Claude/Codex transcript caches when they exist. On a fresh
computer with no local sessions yet, the dashboard shows connection status first
instead of assuming those local files are present.

Custom connector definitions are stored at
`~/Library/Application Support/dooyou/connectors.json`. API key values are never
written to that JSON file.

## Package For Sharing

Create a zip at `dist/release/dooyou-macos.zip`:

```bash
./script/package_release.sh
```

The zip contains:

- `dooyou.app`
- `install-dooyou.command`
- `INSTALL.txt`

On another Mac, unzip the file and double-click `install-dooyou.command`. The
installer copies `dooyou.app` to `/Applications`, starts it at login, and enables
Remote Login for the current macOS user so future updates can be installed
remotely.

After Remote Login is enabled, future updates can be pushed from this repo:

```bash
./script/install_remote.sh <ssh-host> [ssh-user]
```

This package is suitable for local testing and direct sharing with trusted users.
Public distribution still needs Developer ID signing, hardened runtime,
notarization, and stapling so Gatekeeper trusts the download without manual
override.
