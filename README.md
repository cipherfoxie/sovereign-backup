# sovereign-backup

> Multi-host age-encrypted backup tool. Pure bash. No daemon, no container, no agent on the wire. Tar + age + a systemd timer.

[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.x-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![systemd](https://img.shields.io/badge/systemd-timer-FCC624.svg?logo=systemd&logoColor=black)](https://www.freedesktop.org/wiki/Software/systemd/)
[![age](https://img.shields.io/badge/encryption-age-9333ea.svg)](https://age-encryption.org/)
[![arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-blue.svg)](#tested-on)
[![Zero Dependencies](https://img.shields.io/badge/runtime%20deps-bash%20%2B%20age%20%2B%20tar-success.svg)](#design-constraints)
[![Security](https://img.shields.io/badge/security-SECURITY.md-red.svg)](SECURITY.md)
[![Write-up](https://img.shields.io/badge/write--up-sovgrid.org-76b900.svg)](https://sovgrid.org/blog/strategy-backup-and-disaster-recovery/)

## What

`sovereign-backup` runs as root, reads a host-specific YAML config, tars the listed paths, pipes the stream through a compressor (zstd, pigz, or gzip), pipes the result through `age` for encryption, and writes the encrypted archive to one or two destinations (local NVMe and an optional USB stick). A daily systemd timer runs the local target. The USB target is triggered manually when the stick is in.

```bash
sudo sovereign-backup --dry-run --verbose
# 02:00:01 [INFO]  sovereign-backup 0.1.0, host=sparki, target=local
# 02:00:01 [INFO]  DRY-RUN MODE
# 02:00:01 [INFO]  would archive sources (relative to /):
# 02:00:01 [INFO]      data/config
# 02:00:01 [INFO]      data/scripts
# 02:00:01 [INFO]      ...
# 02:00:01 [INFO]  would write to:
# 02:00:01 [INFO]      local: /data/backups
# 02:00:01 [INFO]  compressor would be: zstd -c -T0 -3

sudo sovereign-backup --target usb     # write to USB only (stick must be in)
sudo sovereign-backup --target both    # local + USB in one run
sudo sovereign-restore --list          # show every archive in local + USB
sudo sovereign-restore --verify <file> # decrypt + tar test, no extraction
sudo sovereign-restore --latest        # decrypt + extract newest local backup
```

## Why

Most backup tools optimize for the wrong constraint. They assume an unreliable network and design around delta sync, deduplication, retention policies expressed in YAML schemas, and a daemon that runs all day. For one operator, three hosts, two destinations (NVMe + a USB stick that lives in a drawer), and an age-encrypted threat model, that machinery is overhead.

This tool is what happens when the actual operation, "tar a few directories, encrypt to one age recipient, write the file, prune old files", is written without ceremony. The code fits in one bash script that any operator can audit. The config is a YAML file with twelve recognized keys. The state is the filesystem. There is no daemon, no API, no UI, no log database, no client-server split. There is `tar | compressor | age > file`, wrapped in error handling, locking, and a hook for the rare case you need one.

For the homelab and sovereign-stack operator who already runs systemd and just wants one file per night and one USB-pull per month, this is the smaller path.

## vs other backup tools

| | sovereign-backup | BorgBackup | Restic | Duplicity | rsync + cron |
|---|---|---|---|---|---|
| **Project ethos** | minimal, audit in 15 min | dedupe-first, repo-format | dedupe + cloud destinations | gpg + remote sync | the original DIY |
| **Encryption** | age (recipient pubkey) | repokey or keyfile | AES-256, internal key mgmt | GPG | none, manual |
| **Code size** | ~600 LOC bash | ~70k LOC Python | ~60k LOC Go | ~30k LOC Python | 0 LOC |
| **Deduplication** | no, one archive per run | yes, chunk-level | yes, chunk-level | yes, incremental | no |
| **Recovery without the tool** | yes: `age -d \| tar x` | no, repo format | no, repo format | gpg + duplicity needed | yes |
| **Daemon required** | no | no | no | no | no |
| **Multi-host config** | per-host YAML, autodetect by `hostname` | per-repo | per-repo | per-config | per-cron |
| **USB-stick workflow** | first-class (label-mount-write-unmount) | manual | manual | manual | manual |
| **Pre / post hooks** | yes | yes (in repo config) | yes | yes | cron-level only |
| **Compression** | zstd / pigz / gzip (auto) | zstd / lz4 / none | zstd | bz2 / gzip | none |
| **Compatible with offline-key model** | yes (recipient on host, identity in safe) | requires repo-pass on host | requires repo-pass on host | gpg passphrase on host | none |
| **Out-of-the-box systemd** | yes (service + timer) | no, you write it | no, you write it | no | the cron one |
| **What you lose** | dedup, incremental | simplicity | simplicity | simplicity | encryption, structure |
| **Audit time, full source** | 15 min | hours | hours | hours | n/a |

`sovereign-backup` is the right pick when you want: encryption with the public-key model, USB-friendly workflow, recovery that works with stock tools (`age` and `tar` from any distro) ten years from now, and a tool small enough to read in one sitting. Pick Borg or Restic if you need deduplication and your backup volume is large enough to justify it. Pick Duplicity if you already use GPG. Pick rsync if encryption is not on your threat model.

## Design constraints

These are non-negotiable and define the project scope.

1. **Pure bash + standard POSIX tools.** No Python, Node, Go, Rust runtime. Required: bash 4+, `age`, `tar`, and one of `zstd`, `pigz`, `gzip`. Already on every Linux host that runs an editor.

2. **Config-driven, host-aware.** `/etc/sovereign-backup/<hostname>.yaml` is autodetected via `hostname -s`. Three hosts can share a repo and each gets its own config without touching code.

3. **Single age recipient strategy.** ONE shared age public key across all hosts. ONE private identity kept offline by the maintainer. Every host encrypts to the same recipient. Recovery on any host with the identity present.

4. **Two destinations.** Local (NVMe, daily timer) and USB (label-detected, manual trigger). The USB stick uses ext4 with mount-on-demand at `/mnt/sov-backup`, mount only if the script mounted it, and unmount cleanly when done.

5. **No friend trigger, no maintainer-only mode.** The script is root-only. There is no suid helper, no friend-facing CLI, no daemon that can be invoked over the network. The only way a backup runs is the systemd timer or a maintainer SSH session.

6. **Smart-restart unsafe.** The script does not stop services before archiving. The encrypted snapshot reflects the source paths as they exist at tar time. For most homelab data (configs, repos, blobs), this is fine. For running databases, use `pre_hook` to dump or pause.

7. **Atomic lock via mkdir.** `/run/sovereign-backup/lock` is created with the atomic `mkdir` primitive. Stale-PID detection breaks abandoned locks. `--once` overrides for deliberate manual runs.

8. **Hooks for the 10% who need them.** `pre_hook` fires before tar. `post_hook` fires only after a successful encrypted write. Both are validated as absolute paths, regular files, executable, and root-owned before invocation.

9. **Logging to journalctl plus tail-friendly file.** Structured journal lines plus `/var/log/sovereign-backup.log` for `tail -f` over an SSH session.

10. **No external dependencies, no telemetry, no phone-home.** The only network the script touches is whatever the optional hooks decide to hit.

## Install

```bash
git clone https://github.com/cipherfoxie/sovereign-backup.git
cd sovereign-backup
sudo ./install.sh
```

`install.sh` autodetects the hostname and copies the matching config from `config/<hostname>.yaml`. If no host config exists, it falls back to the annotated example. Existing configs are never overwritten; a `.new` file is dropped next to them for manual diff.

Then:

```bash
# 1. Place the age recipient (public key) at the configured path
sudo install -m 644 my-recipient.pub /etc/sovereign-backup/age-recipient

# 2. Review the config
sudo nano /etc/sovereign-backup/$(hostname -s).yaml

# 3. Test
sudo sovereign-backup --list
sudo sovereign-backup --dry-run --verbose

# 4. Enable the daily timer
sudo systemctl enable --now sovereign-backup.timer
systemctl list-timers sovereign-backup
```

## Config

See `config/sovereign-backup.yaml.example` for the annotated reference. Minimal:

```yaml
host: myhost
sources:
  - /etc
  - /home/me/notes
destinations:
  local: /var/backups
age_recipient: /etc/sovereign-backup/age-recipient
retention:
  local_days: 14
```

Full:

```yaml
host: sparki
sources:
  - /data/config
  - /data/projects
exclusions:
  - "*/node_modules"
  - "*/.git/objects/pack"
destinations:
  local: /data/backups
  usb_label: SOVEREIGN-BACKUP
  usb_subdir: sparki/backups
retention:
  local_days: 14
  usb_days: 90
age_recipient: /data/secrets/age/age-recipient
compressor: auto
pre_hook: /usr/local/bin/sb-pre
post_hook: /usr/local/bin/sb-post
schedule:
  local_calendar: "*-*-* 02:00:00"
  local_random_delay: 30min
```

## USB workflow

The USB stick should carry an ext4 partition labeled `SOVEREIGN-BACKUP` (the label is configurable). When the stick is plugged in:

```bash
sudo sovereign-backup --target usb     # writes to /mnt/sov-backup/<host>/backups/, unmounts cleanly
sudo sovereign-backup --target both    # writes to both local and USB
```

The script mounts the stick only if it is not already mounted, and unmounts it only if it mounted it itself. If you have the stick mounted manually for inspection, the script will write and leave it mounted.

## Restore

```bash
sudo sovereign-restore --list                       # local + USB (if mounted), sorted by date
sudo sovereign-restore --verify <file>              # decrypt + tar test, no extraction
sudo sovereign-restore --latest                     # restore newest local backup to /tmp/sovereign-restore-<ts>
sudo sovereign-restore <file> /tmp/restored         # specific file, specific target
sudo sovereign-restore <file> /                     # restore to root (requires interactive YES)
```

The age identity (private key) must be at `/data/secrets/age/age-identity` or wherever `SOVEREIGN_BACKUP_IDENTITY` points. For day-to-day, keep that file offline and only copy it onto the host when a restore is actually needed.

## Logs

```bash
journalctl -u sovereign-backup.service -e          # last run
journalctl -u sovereign-backup.service -f          # follow live
tail -f /var/log/sovereign-backup.log              # tail-friendly mirror
systemctl list-timers sovereign-backup             # when next
```

## Tested on

- Ubuntu 26.04 LTS, AMD64, Lenovo Legion Pro 7 Gen 10 (Legi)
- Ubuntu 25.10, ARM64, NVIDIA DGX Spark (Sparki)
- Debian 13, AMD64, FlokiNET VPS (Floki)

Should work on anything with bash 4+, `age`, and `tar` 1.30+.

## Roadmap

- [ ] CI: shellcheck + smoke tests on a Ubuntu / Debian matrix
- [ ] Optional `--include-from` / `--exclude-from` for path lists in external files
- [ ] Documented `pre_hook` examples: pg_dump pause, sqlite VACUUM INTO, Nostr notify, Floki pull
- [ ] Backup verification timer (decrypt + tar-list the newest archive once a week)

Pull requests welcome. Keep it sovereign, keep it small.

## Won't do (anti-roadmap)

These will be refused in PRs because they break design constraints:

- No web UI (use the journal and the filesystem)
- No daemon or long-running process (systemd is the scheduler)
- No Python / Go / Rust runtime (pure bash is the point)
- No deduplication or chunk store (use Borg or Restic if you need that)
- No cloud-destination support (use Restic if you need that; pre_hook can do it from outside)
- No telemetry, no phone-home, no update-check for sovereign-backup itself
- No multi-host orchestration (each host runs its own timer, use ansible if you want to push configs)
- No backup-of-backup chain logic (out of scope; let the operator decide)

## License

MIT. See [LICENSE](LICENSE).

## Origin

I built this in May 2026 to replace a Sparki-only script (`/data/projects/sovereign-backup/backup.sh`) that had served well for a year but did not generalize. Two new hosts joined the stack (Legi as a friend-laptop, Floki as a VPS) and they all needed the same encryption model with different source lists and different USB realities. Rather than fork the script three times, I rewrote it once with a per-host YAML and the USB workflow promoted to first-class. The original Sparki script taught me what the right shape was; this is the second-system version that finally is the right shape.
