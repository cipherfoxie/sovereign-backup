# Changelog

All notable changes documented here. Format inspired by Keep a Changelog.

## [0.1.0], 2026-05-30

Initial release. The v2 rewrite of the Sparki-only backup script as a generic multi-host tool.

### Added
- Core script `bin/sovereign-backup`: pure-bash multi-host backup with age encryption
- Core script `bin/sovereign-restore`: list, verify, restore (latest or specific file)
- `--dry-run`, `--once`, `--verbose`, `--list`, `--version`, `--help`, `--config`, `--target` CLI flags
- YAML config loader supporting `host`, `sources`, `exclusions`, `destinations.{local,usb_label,usb_subdir}`, `retention.{local_days,usb_days}`, `age_recipient`, `compressor`, `pre_hook`, `post_hook`, `schedule.*` keys
- Per-host config autodetect via `hostname -s`
- Three shipped configs: sparki (DGX Spark, ARM64), legi (Lenovo Legion, AMD64), floki (VPS, AMD64)
- Two destinations: local (NVMe, daily timer) and USB (manual trigger, ext4 mount-on-demand at `/mnt/sov-backup`)
- USB mount lifecycle: mount only if not already mounted, unmount only if we mounted it
- Compressor auto-pick: zstd > pigz > gzip, with override
- Atomic lockfile via `mkdir`, with stale-PID detection and break logic
- Pre-hook and post-hook execution with root-owned-script validation
- Retention by mtime in days, with prune step after a successful write
- Tmp-then-rename for the encrypted archive so a half-written file never appears under the final name
- systemd `sovereign-backup.service` and `sovereign-backup.timer` (daily 02:00 plus 30min jitter)
- Hardened systemd unit: `ProtectSystem=strict`, `NoNewPrivileges`, `SystemCallFilter`, minimal capabilities
- `install.sh` for idempotent root install, never clobbers existing config, picks correct host config automatically
- Smoke-test suite under `tests/smoke.sh` covering 14 cases (CLI surface, config loader, hook validation, lock behaviour, restore list and verify)

### Security
- Hook paths validated as absolute, regular file, executable, root-owned (when run as root)
- age recipient file pattern-checked (`age1...` or `ssh-...`) before any tar starts
- YAML parser is non-evaluating: no `eval`, no command substitution from config values
- Comment stripping aware of single- and double-quoted strings to preserve `#` inside values
- Lockfile race-free via atomic `mkdir`
- Archives tarred relative to `/` so restoration into any target dir is safe

### Differences from the v1 Sparki script
- Generic instead of host-coded: config drives every host-specific value
- USB workflow promoted to first-class with label-based mount-on-demand
- Multi-destination (local + USB in a single run via `--target both`)
- Compressor auto-picks zstd when available (was hard-coded pigz fallback to gzip)
- Hooks validated for root ownership (was unchecked)
- Atomic mkdir lock (was no lock at all)
- Restore script supports verify and latest modes (was list + extract only)

### Tested on
- Ubuntu 26.04 LTS, AMD64 (Lenovo Legion Pro 7 Gen 10)
- Ubuntu 25.10, ARM64 (NVIDIA DGX Spark)
- Debian 13, AMD64 (FlokiNET VPS)

### Documentation
- `README.md` with design constraints, comparison table, full install + config docs
- `SECURITY.md` threat model + scope boundaries
- `AGENTS.md` multi-agent contract for AI-assisted contributions
- `TASKS.md` roadmap with explicit anti-roadmap (refused-by-design features)
- This `CHANGELOG.md`
