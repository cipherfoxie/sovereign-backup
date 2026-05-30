# AGENTS, multi-agent contract for sovereign-backup

This file is the contract any AI agent (Claude, Qwen, Mistral, opencode, Continue, Zed-agent) must read before editing the repo.

## Project ethos

`sovereign-backup` is intentionally small. **Resist feature bloat.** Before adding any feature, ask: does this break design constraint 1 to 10 in the README? If yes, decline. If no, add it. Most "needed" features have a one-line shell wrapper or a hook script as the correct solution.

## Models available
- Default for daily work: `qwen3:8b` (local Ollama)
- Heavy lift, refactor, deep analysis: `sparki/qwen3.6-35b` (Sparki via Tailscale)
- Hard reasoning, security review: Claude (manual, not in CI)

## MCP tools enabled
- `kb`, search local Knowledge-Base
- `mem0`, persistent personal memory
- `sovgrid-ai`, search sovgrid.org blog
- `context7`, current library docs

## Rules

1. **Pure bash only.** No Python, Node, Go, Rust. Standard POSIX tools (`find`, `grep`, `sed`, `awk`, `date`) plus `age`, `tar`, and a compressor. Already on every Linux host.

2. **No em-dashes (U+2014) in any user-facing string.** Use comma, period, or parens. This includes README, SECURITY.md, log output, and code comments visible in source mirrors. Pre-commit grep target: `grep -rP '\x{2014}' .` must return zero.

3. **No "Generated with Claude Code" / "Co-Authored-By: Claude" trailers** in commits intended for GitHub. Local Gitea: agent trailers are OK and encouraged for multi-agent audit.

4. **TASKS.md is canonical.** Every commit references an SB-### task or adds one.

5. **Read in this order**: `README.md` for the design constraints, this file for ground rules, `SECURITY.md` for the threat model, `TASKS.md` for current work, `git log -5` for context.

6. **shellcheck clean.** Before any commit touching `bin/sovereign-backup` or `bin/sovereign-restore`: run `shellcheck bin/*`. Zero warnings is the gate. Some `# shellcheck disable=` comments are present for known-safe patterns; do not introduce new ones without a comment justifying them.

7. **Smoke tests must pass.** Run `bash tests/smoke.sh` before commit. 14 of 14 ok.

8. **Test on a real source path before commit.** Use `--dry-run --verbose` against a sandbox config. Confirm the source list, exclusion list, and chosen compressor look right.

9. **Question the user before destructive ops.** No silent `rm`, no force-push, no schema drop, no overwriting of an existing host config in `install.sh`.

10. **Recipient and identity files are sacred.** Never log them, never echo them, never write them to a tmp file. The recipient is a public key and safe to display; the identity is private and must not appear in any output. If you grep for sensitive shapes in the code, age identities start with `AGE-SECRET-KEY-`.

## Commit-message format

```
SB-### short imperative subject

Optional body. Why, not what.

Co-Authored-By: <agent-name> <agent@legi.local>
```

Agent-trailer naming convention:
- `qwen3-8b@legi.local`
- `mistral-7b@legi.local`
- `sparki-qwen36@sparki.local`
- `claude-code@anthropic`

## Tools/IDE setup
- **Zed**: opens repo, default model qwen3:8b
- **VSCodium + Continue**: same provider list
- **opencode TUI**: same providers + MCPs
- **shellcheck**: `apt install shellcheck` if not present
- **age**: `apt install age` for local tests; the smoke tests gracefully skip the verify case if age is missing
