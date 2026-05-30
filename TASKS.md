# Tasks, sovereign-backup

Pick one, ship it, append the next. No process tax.

## Done

- [x] **SB-001** repo bootstrap (README, AGENTS, LICENSE, SECURITY, structure)
- [x] **SB-002** core script: tar + compressor + age, two destinations
- [x] **SB-003** YAML config loader (top-level scalars + lists + two-level sections)
- [x] **SB-004** per-host config autodetect via `hostname -s`
- [x] **SB-005** USB workflow: label-detect, mount-on-demand, unmount what we mounted
- [x] **SB-006** mkdir lock with stale-PID detection
- [x] **SB-007** pre_hook + post_hook with root-owned validation
- [x] **SB-008** retention pruning by mtime in days
- [x] **SB-009** systemd service + timer (daily 02:00 + jitter)
- [x] **SB-010** install.sh idempotent, no config overwrite, picks per-host config
- [x] **SB-011** restore script: list, verify, latest, file + target
- [x] **SB-012** smoke test suite, 14 cases, no real source paths touched

## Next (small things)

- [ ] **SB-020** CI: GitHub Actions matrix (Ubuntu 24.04 + 26.04, Debian 13), shellcheck, smoke.sh
- [ ] **SB-021** Document `pre_hook` examples: pg_dump pause, sqlite VACUUM INTO, Nostr notify
- [ ] **SB-022** Weekly verification timer: decrypt + tar-list the newest local archive, exit non-zero on failure
- [ ] **SB-023** `--include-from <file>` and `--exclude-from <file>` for path lists in external files
- [ ] **SB-024** `journalctl` structured field output (`SOVB_HOST=`, `SOVB_BYTES=`) for easier grep

## Medium

- [ ] **SB-030** Per-source retention override: some paths weekly, some monthly
- [ ] **SB-031** Resumable USB writes: if the stick gets unplugged mid-write, the next run picks up cleanly (today: the tmp file is removed on EXIT trap, so the next run starts fresh)
- [ ] **SB-032** Optional split-archive mode (write multiple smaller .age files, useful for huge sources or quota limits)

## Stretch

- [ ] **SB-040** Remote-pull mode: a maintainer SSH-pulls a Floki archive to Sparki USB without changing Floki's local config
- [ ] **SB-041** Plugin system: drop a script in `/etc/sovereign-backup/plugins.d/`, gets sourced

## Don't-do (anti-roadmap)

These will be refused in PRs because they break design constraints.

- No web UI (use the journal and the filesystem)
- No daemon, no port, no API (systemd is the scheduler)
- No deduplication or chunk store (use Borg or Restic if you need that)
- No cloud-destination support (a pre_hook can rsync; the tool stays local)
- No Python / Go / Rust runtime (pure bash is the point)
- No telemetry, no phone-home, no update-check for sovereign-backup itself
- No friend-trigger or non-root invocation path (root only, by design)
- No multi-host orchestration (each host runs its own timer; use ansible if you want to push configs)
- No "smart" service-stop logic in the tool itself (pre_hook is the contract)
- No backup-of-backup chain (out of scope; let the operator decide)
