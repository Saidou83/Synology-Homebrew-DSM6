# Homebrew on Synology DSM 6 — boot-persistent setup

Install Homebrew on DSM 6 (tested on DSM 6.2.4) in a way that survives
reboots cleanly — no manual restarts, no fragile `sleep N` + Task
Scheduler guesswork.

This builds on the original trick for getting Homebrew running on DSM at
all, credited below, and focuses on the part that trick doesn't cover:
**keeping the install working correctly after a reboot.**

> **Note:** the popular [MrCee/Synology-Homebrew](https://github.com/MrCee/Synology-Homebrew)
> automated installer is **DSM 7+ only**. If you're on DSM 6, that
> installer won't work for you — this repo is for you.

The goal here is Homebrew itself, working and boot-persistent. The zsh
shell and Tailscale scripts included in `optional/` are unrelated
extras from my own setup — feel free to ignore them entirely.

## Why this exists

Homebrew requires a real path at `/home/linuxbrew/.linuxbrew` (not a
symlink) to download prebuilt binaries instead of compiling from source
— and DSM has no C compiler, so source builds aren't really an option.
Getting Homebrew installed at all requires two workarounds, credited to
the original Synology community forum thread (see [Credits](#credits)):

1. **A fake `ldd` command** — DSM doesn't ship `ldd`, but Homebrew's
   installer needs it to check the glibc version.
2. **A bind mount of `/home`** to your actual homes share — DSM has no
   `/home`, and a plain symlink isn't enough because Homebrew resolves
   real paths.

Neither of these survives a reboot on its own:

- The bind mount at `/home` disappears, so Homebrew (and anything
  installed through it) becomes unreachable at its expected path.
- DSM doesn't have `/etc/os-release`, which some tools — including
  Homebrew itself — expect and will warn about.

**Task Scheduler's "boot-up" trigger is not a reliable fix for this.**
It fires early in boot, independent of whether volumes are actually
mounted yet — the common workaround is `sleep 300` or similar, which is
a guess that breaks whenever boot time varies.

**`/usr/local/etc/rc.d/` is the right hook point.** Scripts placed here
are run by DSM's own init system, in filename-sorted order, only after
volumes are mounted — no sleep/guessing required.

## What's in here

| Script | Purpose |
|---|---|
| `bootstrap.sh` | Entry point for the `curl \| bash` one-liner — downloads the repo and dispatches to install.sh/uninstall.sh |
| `install.sh` | Installer: runs the core steps below, then optionally offers the extras |
| `uninstall.sh` | Uninstaller: reverses everything, step by step, with a confirmation before each destructive action |
| `setup/ldd-shim.sh` | One-time: create the fake `ldd` needed by Homebrew's installer |
| `rc.d/S00-generate-os-release.sh` | Boot: generate `/etc/os-release` from DSM's own version file |
| `rc.d/S01-homebrew-mount.sh` | Boot: bind-mount your homes share to `/home` |
| `optional/S10-force-zsh.sh` | *(optional, unrelated to Homebrew)* Boot: re-apply a custom login shell |
| `optional/S11-tailscaled.sh` | *(optional, unrelated to Homebrew)* Boot: example of running a Homebrew-installed background service — uses Tailscale |

## Installing Homebrew

### Option A: one-liner (recommended)

No `git clone` needed — this downloads the repo to a temp directory and
runs the installer, the same way Homebrew's own installer works.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Saidou83/homebrew-synology-dsm6/main/bootstrap.sh)" -- --install
```

Runs the core install (ldd shim → mount → Homebrew → boot-persistence
scripts), then asks at the very end, separately, whether you also want
the optional zsh/Tailscale extras. Answer "no" to both if you just want
Homebrew.

### Option B: clone first, then run locally

```sh
git clone https://github.com/Saidou83/homebrew-synology-dsm6.git
cd homebrew-synology-dsm6
sudo sh install.sh
```

Same installer as Option A — useful if you want to read or edit the
scripts before running them.

Both options are safe to re-run if something goes wrong partway
through.

### Option C: manual, step by step

If you'd rather see and control each step yourself:

**1. Create the `ldd` shim**

```sh
sudo sh setup/ldd-shim.sh
```

**2. Bind-mount your homes share to `/home`**

```sh
sudo mkdir -p /home
sudo mount -o bind /volume1/homes /home
```

(adjust `/volume1/homes` if your homes share lives elsewhere)

**3. Install Homebrew**

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

When prompted for an install location, choose `/home/linuxbrew/.linuxbrew`.

**4. Edit `rc.d/S01-homebrew-mount.sh` for your setup**

It has an "EDIT THIS" section near the top for your homes share path.
`S00-generate-os-release.sh` needs no editing.

**5. Install the rc.d scripts**

```sh
sudo cp rc.d/*.sh /usr/local/etc/rc.d/
sudo chmod +x /usr/local/etc/rc.d/*.sh
```

**6. Test without rebooting**

```sh
sudo /usr/local/etc/rc.d/S00-generate-os-release.sh start
sudo /usr/local/etc/rc.d/S01-homebrew-mount.sh start

mount | grep /home
cat /etc/os-release
$(brew --prefix)/bin/brew --version   # or: /home/linuxbrew/.linuxbrew/bin/brew --version
```

**7. Reboot and confirm**

```sh
sudo reboot
```

After it comes back up:

```sh
mount | grep /home
brew --version
```

Homebrew should be fully usable with zero manual steps after reboot.

## Re-running / idempotency

Both `install.sh` and every rc.d script are safe to run more than once:

- The `/home` mount, Homebrew install check, and Tailscale daemon start
  all check current state first and skip if already done.
- The `ldd` shim, `/etc/os-release`, and the rc.d script files
  themselves are simply overwritten with the same content each time —
  harmless, but note this means **manual edits made directly to the
  installed copies in `/usr/local/etc/rc.d/` will be overwritten** if
  you re-run `install.sh`. Edit the source scripts in this repo instead,
  then re-run.

## Optional extras

These are **not required for Homebrew** — they're two unrelated
conveniences from my own DS412 setup, included in case they're useful.
Both live in `optional/` and are skipped by default.

### `S10-force-zsh.sh` — persist a custom login shell

DSM's Package Center / User settings UI doesn't let you set a user's
login shell to a Homebrew-installed zsh, and DSM can reset shell
settings under some conditions. This script re-applies your chosen
shell on every boot.

Requires `/bin/zsh` to exist (usually a symlink to the real binary —
check with `ls -la /bin/zsh` and create it first if missing, e.g.
`sudo ln -s /usr/local/bin/zsh /bin/zsh` or point it at your Homebrew
zsh).

Edit the `TARGET_USER` variable near the top, then:

```sh
sudo cp optional/S10-force-zsh.sh /usr/local/etc/rc.d/
sudo chmod +x /usr/local/etc/rc.d/S10-force-zsh.sh
sudo /usr/local/etc/rc.d/S10-force-zsh.sh start
```

### `S11-tailscaled.sh` — run a Homebrew-installed background service at boot

An example of the general pattern for keeping any Homebrew-installed
daemon running after a reboot (check binary exists → ensure state/
socket dirs exist → launch with output redirected to a log file →
background it). Uses Tailscale as the concrete example, but the same
shape works for most other `brew`-installed services.

If you opt into this via `install.sh`, it will run `brew install
tailscale` automatically if it isn't already installed, install and
start `S11-tailscaled.sh`, and run `tailscale up` once for you
(you'll be shown an auth URL to visit if this device isn't already on
your tailnet). Nothing further to do afterwards — the daemon
reconnects automatically from saved state on every boot.

If installing manually (Option C, or if you skipped this during
`install.sh` and want to add it later):

```sh
sudo -u <your-user> /home/linuxbrew/.linuxbrew/bin/brew install tailscale
sudo cp optional/S11-tailscaled.sh /usr/local/etc/rc.d/
sudo chmod +x /usr/local/etc/rc.d/S11-tailscaled.sh
sudo /usr/local/etc/rc.d/S11-tailscaled.sh start
sudo /home/linuxbrew/.linuxbrew/bin/tailscale --socket=/var/run/tailscale/tailscaled.sock up
```

(Homebrew refuses to run as root — install the formula as your normal
user, not via `sudo brew ...` directly.)

## Uninstalling

One-liner (no clone needed):

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Saidou83/homebrew-synology-dsm6/main/bootstrap.sh)" -- --uninstall
```

Or, from a local clone:

```sh
sudo sh uninstall.sh
```

Walks through removing each piece one at a time — the optional extras
(if installed), the core rc.d scripts, the `/home` bind mount, the
`ldd` shim, and `/etc/os-release` — asking for confirmation before each
step. Nothing happens without an explicit "yes."

The last step optionally runs Homebrew's own official uninstaller,
which removes Homebrew itself and everything installed through it
(formulae, casks, caches). This is skipped by default — say no if you
just want to remove the DSM 6 boot-persistence layer but keep Homebrew
and your installed packages as-is.

Unmounting `/home` does **not** delete any files — your actual homes
share and anything under it (including your Homebrew install) is left
untouched on disk; it just becomes unreachable at `/home/...` until
mounted again.

## Credits

- The core `ldd` shim + bind mount trick originates from this Synology
  community forum thread:
  https://community.synology.com/enu/forum/1/post/153781
- For DSM 7+, see the fully automated installer:
  https://github.com/MrCee/Synology-Homebrew

## License

MIT — see [LICENSE](LICENSE).
