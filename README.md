# Homebrew on Synology DSM 6 — boot-persistent setup

A collection of `/usr/local/etc/rc.d/` scripts to make a Homebrew install
on DSM 6 (tested on DSM 6.2.4) survive reboots cleanly — no manual
restarts, no fragile `sleep N` + Task Scheduler guesswork.

This builds on the original trick for getting Homebrew running on DSM at
all, credited below, and focuses on the part that trick doesn't cover:
**keeping everything running correctly after a reboot.**

> **Note:** the popular [MrCee/Synology-Homebrew](https://github.com/MrCee/Synology-Homebrew)
> automated installer is **DSM 7+ only**. If you're on DSM 6, that
> installer won't work for you — this repo is for you.

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

Once Homebrew is installed, a few things don't survive a reboot unless
you handle them explicitly:

- The bind mount at `/home` disappears.
- Anything you started manually in a terminal session (like `tailscaled`)
  dies when the session ends, unless properly daemonized.
- DSM doesn't have `/etc/os-release`, which some tools expect.
- A custom login shell (e.g. zsh from Homebrew) can get reset.

**Task Scheduler's "boot-up" trigger is not reliable for this.** It
fires early in boot, independent of whether volumes are actually
mounted yet — the common workaround is `sleep 300` or similar, which is
a guess that breaks whenever boot time varies.

**`/usr/local/etc/rc.d/` is the right hook point.** Scripts placed here
are run by DSM's own init system, in filename-sorted order, only after
volumes are mounted — no sleep/guessing required, and correct ordering
between scripts is guaranteed by naming them `S00`, `S01`, `S02`, etc.

## What's in here

| Script | Purpose |
|---|---|
| `install.sh` | One-liner installer that runs every step below, with prompts |
| `setup/ldd-shim.sh` | One-time: create the fake `ldd` needed by Homebrew's installer |
| `rc.d/S00-force-zsh.sh` | Boot: re-apply a custom login shell (e.g. Homebrew zsh) |
| `rc.d/S00b-generate-os-release.sh` | Boot: generate `/etc/os-release` from DSM's own version file |
| `rc.d/S01-homebrew-mount.sh` | Boot: bind-mount your homes share to `/home` |
| `rc.d/S02-tailscaled.sh` | Boot: start a Homebrew-installed `tailscaled` (example service; adapt for others) |

## Installation

### Option A: one-liner (recommended)

Prompts you for your homes share path, username, Homebrew prefix, and
whether to set up Tailscale, then does everything below in one go.

```sh
git clone https://github.com/<you>/synology-homebrew-dsm6.git
cd synology-homebrew-dsm6
sudo sh install.sh
```

It's safe to re-run if something goes wrong partway through.

### Option B: manual, step by step

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

**4. Edit the rc.d scripts for your setup**

Each script in `rc.d/` has an "EDIT THIS" section near the top —
username, volume path, Homebrew prefix, etc. Check each one before
installing.

**5. Install the rc.d scripts**

```sh
sudo cp rc.d/*.sh /usr/local/etc/rc.d/
sudo chmod +x /usr/local/etc/rc.d/*.sh
```

**6. Test without rebooting**

```sh
sudo /usr/local/etc/rc.d/S00-force-zsh.sh start
sudo /usr/local/etc/rc.d/S00b-generate-os-release.sh start
sudo /usr/local/etc/rc.d/S01-homebrew-mount.sh start
sudo /usr/local/etc/rc.d/S02-tailscaled.sh start

mount | grep /home
cat /etc/os-release
ps aux | grep tailscaled
```

**7. Reboot and confirm**

```sh
sudo reboot
```

After it comes back up:

```sh
mount | grep /home
ps aux | grep tailscaled
echo $SHELL
```

Everything should be up with zero manual steps.

## Adapting `S02-tailscaled.sh` for other services

The Tailscale script is really just an example of "start a
Homebrew-installed background service on boot." The same pattern (check
binary exists → ensure state/socket dirs exist → launch with output
redirected to a log file → background it) works for most other daemons
you install via `brew`.

## Credits

- The core `ldd` shim + bind mount trick originates from this Synology
  community forum thread:
  https://community.synology.com/enu/forum/1/post/153781
- For DSM 7+, see the fully automated installer:
  https://github.com/MrCee/Synology-Homebrew

## License

MIT — see [LICENSE](LICENSE).
