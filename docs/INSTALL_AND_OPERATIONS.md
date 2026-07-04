# Install And Operations

## Local Development Run

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM executable, stages `dist/dooyou.app`, copies
resource bundles, ad-hoc signs the app, kills an older `dooyou` process, and
launches the app bundle.

Useful modes:

```bash
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## Install On This Mac

```bash
./script/build_and_run.sh --install
```

`./script/install_login_item.sh` is the direct installer path used by that mode.

This builds the app, copies it to `/Applications/dooyou.app`, writes
`~/Library/LaunchAgents/local.dooyou.plist`, bootstraps the LaunchAgent, and
starts DOOYOU.

The LaunchAgent runs:

```text
/Applications/dooyou.app/Contents/MacOS/dooyou
```

It also sets:

- `RunAtLoad = true`
- `KeepAlive = true`
- logs under `~/Library/Logs/dooyou/`

That means DOOYOU starts at login and relaunches if the process exits. To stop
it permanently on this Mac, unload the LaunchAgent:

```bash
./script/uninstall_login_item.sh
```

## Package For Another Mac

```bash
./script/package_release.sh
```

The package is written to:

```text
dist/release/dooyou-macos.zip
```

It contains:

- `dooyou.app`
- `install-dooyou.command`
- `INSTALL.txt`

The installer copies the app to `/Applications`, registers the same `KeepAlive`
LaunchAgent, enables Remote Login for the current macOS user, and prints the
Tailscale SSH target when available.

## Remote Install

Remote install works only after the target Mac has Remote Login enabled and is
reachable over the network or Tailscale.

```bash
./script/install_remote.sh <ssh-host> [ssh-user]
```

If `tailscale ping` returns `no reply` and `ssh` times out, the usual causes are:

- the target Mac is asleep or offline;
- Tailscale is not running or the device is not connected;
- macOS Remote Login is off;
- the current user is not allowed for SSH;
- the target is on a different Tailnet or ACL blocks it.

The first install on a new Mac should usually be done by Taildrop or file copy
plus `install-dooyou.command`. After that, `install_remote.sh` can update it.

## Distribution Status

Current packages are suitable for trusted local testing. Public distribution
still needs Developer ID signing, hardened runtime, notarization, and stapling
so Gatekeeper trusts the app without a manual override.
