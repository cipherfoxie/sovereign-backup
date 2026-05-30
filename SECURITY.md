# Security model

## Threat model

`sovereign-backup` is a root-level tool that reads source paths, runs a tar pipeline through a compressor and `age`, writes an encrypted archive to local disk and optionally a USB stick. The threat surfaces I designed against:

| Risk | Mitigation in v0.1 |
|---|---|
| **age private key compromise** lets the attacker decrypt every archive ever written | The recipient (public key) lives on each host. The identity (private key) is kept offline by the maintainer (paper or air-gapped media). Hosts never see the private key. A compromise of one host does not yield the key. |
| **USB stick theft** | The stick carries only `age`-encrypted archives. Without the offline identity, the contents are not recoverable. The plaintext attack surface on the stick is zero. |
| **Race between two concurrent runs** corrupting the local file or pruning mid-write | Atomic `mkdir /run/sovereign-backup/lock`. Stale-PID detection breaks abandoned locks. `--once` overrides for deliberate manual runs. The pipeline writes to `<file>.tmp` and renames only after `age` exits cleanly, so a half-written archive never appears under the final name. |
| **Tar reading containers mid-transaction** producing an inconsistent snapshot | Acknowledged trade-off. The script does not stop services. For most homelab data (configs, repos, opaque blobs), the snapshot is fine. For running databases, use `pre_hook` to dump the DB into a known-good path before tar runs. |
| **Compromised config file** points `pre_hook` or `post_hook` at a malicious script | Hook paths are validated: must be absolute, no `..`, regular file, executable, root-owned (when EUID is 0). Refused with exit 2 before any tar. A non-root attacker who can write the config cannot smuggle in a non-root-owned hook. |
| **YAML injection** through a tampered config | The parser does not `eval`, does not perform command substitution, does not expand `$VAR`. Quoted strings preserve `#` and the raw value is used as-is. The parser ignores unknown keys rather than throwing, so a hostile config can introduce extra keys but cannot widen behavior. |
| **USB mount as root** | Standard ext4 mount at `/mnt/sov-backup`. No tmpfs, no overlay, no exec disabled (the stick does not run code, only stores files). The script unmounts only what it mounted, so a manually pre-mounted stick stays mounted. |
| **Layered defense: encrypted host disk plus encrypted backup** | Host root disk on Sparki and Legi is LUKS-encrypted. The backup adds a second layer with a different key. A leaked LUKS passphrase does not yield archives; a leaked age identity does not yield the host. |
| **Lockfile in writable dir hijack** | `/run/sovereign-backup` is created via the systemd `RuntimeDirectory=` mechanism, mode 0750, root-owned. Non-root users cannot create or modify the lock. |
| **Archive contains real source-tree paths** | Archives are tarred relative to `/`, so an entry looks like `data/config/foo` (no leading slash). Restoration into any target directory is safe; no symlink-escape via absolute paths. |

## What sovereign-backup does NOT defend against

The following are intentionally out of scope.

1. **Physical seizure of a powered-on host** with the SSH session open and the age recipient readable. The recipient is meant to be readable on the host (it is a public key); the threat there is whatever the attacker can do once they have root. If you need defense in this case, you need a TPM-sealed or HSM-held key path that is outside this tool.
2. **Supply chain attack on the `age` binary** shipped by your distribution. `sovereign-backup` invokes whatever `age` is in PATH. If `age` is backdoored, every archive on the host can be silently leaked. Run `apt install age` from a trusted source; verify package signatures.
3. **OS-level compromise** of the host running the backup. If `dockerd`, `sshd`, or `systemd` itself is rooted, the attacker can read source paths directly and the backup tool has nothing to add. Use the rest of your stack to prevent this.
4. **Compromised pre_hook or post_hook scripts**. The script validates the hook is root-owned at the time of the run. If a root attacker swapped the hook a minute before the timer fires, the validation passes and the malicious hook executes. Hook validation defends against a non-root attacker writing the config, not against a root attacker writing the hook.
5. **Tar reading a file that is being written by another process**. The resulting archive entry is whatever bytes were on disk when tar read them, possibly torn. Use `pre_hook` to stop or snapshot the writer if consistency matters.
6. **Resource exhaustion**. A huge unintended source path (e.g. `/var/lib/docker` accidentally included) fills the destination disk. Set local destinations on a partition that can take the volume, watch disk usage in your monitoring.
7. **Backup poisoning at the source**. If an attacker replaces a source file with malicious content before the backup runs, the backup faithfully archives the malicious content. The backup is a snapshot, not a known-good store.

## Inputs and their trust level

| Input | Trust level | Notes |
|---|---|---|
| Command-line args | High | Limited to a fixed enum, no shell expansion |
| `/etc/sovereign-backup/<host>.yaml` | Medium | Validated, value-typed, no eval, unknown keys ignored |
| Hook scripts | Medium | Validated as root-owned absolute paths before execution |
| Source paths | Authoritative | The operator decides what to back up; the tool tars what it is told |
| age recipient file | Read at run-time | Pattern-checked (`age1...` or `ssh-...`). A wrong recipient produces an unreadable archive, not an information leak |
| age identity file (restore only) | Authoritative | If readable, the script will decrypt. Keep it offline outside of restore windows |

## Backup verification

Verify a backup is recoverable, periodically:

```bash
sudo sovereign-restore --verify $(ls -1t /data/backups/sovereign-backup-*.age | head -1)
```

This decrypts and tar-lists the archive without extracting. Exit 0 means the file is intact end-to-end. A weekly timer for this check is on the roadmap.

## Reporting

Found something? Open an issue on the repo. If sensitive, encrypt to the maintainer's public key (in `keys/` once published).

## Audit notes

- v0.1.0 (2026-05-30): initial release. No external dependencies beyond `age`, `tar`, and a compressor. No `eval`. Atomic `mkdir` lock. Root-owned hook check. Recipient pattern check. Tmp-then-rename for the encrypted file. systemd unit hardened to the extent compatible with reading source paths under root.
