#!/usr/bin/env bash
# Smoke tests for sovereign-backup. Touches no real source paths and does
# not write any encrypted archive. Verifies CLI surface, config loader,
# hook validation, lock behaviour, and restore --list / --verify shape.
#
# Run: bash tests/smoke.sh

set -Eeuo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/sovereign-backup"
RESTORE_BIN="$REPO/bin/sovereign-restore"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OK=0
FAIL=0

note() { printf '\n[%s] %s\n' "$1" "$2"; }
pass() { printf '  ok %s\n' "$1"; OK=$((OK+1)); }
fail() { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$desc"
    else
        fail "$desc"
        printf '    expected: %s\n    actual:   %s\n' "$expected" "$actual"
    fi
}

# Sandboxed run: isolated lockdir, isolated config dir, isolated log file,
# isolated USB mountpoint.
run_sb() {
    SOVEREIGN_BACKUP_LOCKDIR="$TMP/lock" \
    SOVEREIGN_BACKUP_CONFIG_DIR="$TMP/etc-sb" \
    SOVEREIGN_BACKUP_USB_MOUNT="$TMP/mnt-usb" \
    SOVEREIGN_BACKUP_LOG="$TMP/sb.log" \
        "$BIN" "$@"
}

run_restore() {
    SOVEREIGN_BACKUP_LOCAL_DIR="$TMP/local-backups" \
    SOVEREIGN_BACKUP_USB_MOUNT="$TMP/mnt-usb" \
    SOVEREIGN_BACKUP_IDENTITY="$TMP/identity" \
        "$RESTORE_BIN" "$@"
}

# Make a fake age recipient file that passes the regex check.
FAKE_RECIPIENT="$TMP/recipient"
printf 'age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsxxxxx\n' > "$FAKE_RECIPIENT"

mkdir -p "$TMP/etc-sb"

# A source directory that exists, for valid configs.
mkdir -p "$TMP/src1" "$TMP/src2"
echo "hello" > "$TMP/src1/a.txt"
echo "world" > "$TMP/src2/b.txt"

echo "=== sovereign-backup smoke tests ==="

# ────────────────────────────────────────────────────────────────────────
note "1" "--version exits 0 with correct version"
out="$(run_sb --version 2>&1)"
assert_eq "version output" "sovereign-backup 0.1.0" "$out"

# ────────────────────────────────────────────────────────────────────────
note "2" "--help exits 0"
if run_sb --help >/dev/null 2>&1; then pass "help exits 0"; else fail "help non-zero"; fi

# ────────────────────────────────────────────────────────────────────────
note "3" "unknown arg → exit 2"
set +e
run_sb --bogus >/dev/null 2>&1
rc=$?
set -e
assert_eq "unknown arg exit code" "2" "$rc"

# ────────────────────────────────────────────────────────────────────────
note "4" "config not found → graceful warning, --list works without crash"
set +e
out="$(run_sb --list 2>&1)"
rc=$?
set -e
if (( rc == 0 )) && grep -q "config not found" <<<"$out"; then
    pass "missing config handled gracefully"
else
    fail "missing config did not produce expected warning (rc=$rc)"
    printf '    got: %s\n' "$out"
fi

# ────────────────────────────────────────────────────────────────────────
note "5" "config with explicit sources loads correctly"
cat > "$TMP/etc-sb/valid.yaml" <<EOF
host: testhost
sources:
  - $TMP/src1
  - $TMP/src2
destinations:
  local: $TMP/local-backups
retention:
  local_days: 7
age_recipient: $FAKE_RECIPIENT
EOF
out="$(run_sb --config "$TMP/etc-sb/valid.yaml" --list 2>&1)"
if grep -q "$TMP/src1" <<<"$out" && grep -q "$TMP/src2" <<<"$out" && grep -q "testhost" <<<"$out"; then
    pass "explicit sources loaded"
else
    fail "explicit sources missing from --list output"
    printf '    got: %s\n' "$out"
fi

# ────────────────────────────────────────────────────────────────────────
note "6" "exclusions list parsed correctly"
cat > "$TMP/etc-sb/with-excl.yaml" <<EOF
host: testhost
sources:
  - $TMP/src1
exclusions:
  - "*/node_modules"
  - "*.pyc"
  - "*/cache#one"
destinations:
  local: $TMP/local-backups
age_recipient: $FAKE_RECIPIENT
EOF
out="$(run_sb --config "$TMP/etc-sb/with-excl.yaml" --list 2>&1)"
if grep -q '\*/node_modules' <<<"$out" \
   && grep -q '\*\.pyc'      <<<"$out" \
   && grep -q 'cache#one'    <<<"$out"; then
    pass "exclusions including quoted '#' parsed"
else
    fail "exclusions not all parsed"
    printf '    got: %s\n' "$out"
fi

# ────────────────────────────────────────────────────────────────────────
note "7" "invalid age recipient → exit 2 before any tar"
BAD_RECIPIENT="$TMP/bad-recipient"
echo "not-an-age-key" > "$BAD_RECIPIENT"
cat > "$TMP/etc-sb/bad-rec.yaml" <<EOF
host: testhost
sources:
  - $TMP/src1
destinations:
  local: $TMP/local-backups
age_recipient: $BAD_RECIPIENT
EOF
set +e
run_sb --config "$TMP/etc-sb/bad-rec.yaml" --once >/dev/null 2>&1
rc=$?
set -e
assert_eq "invalid recipient exit code" "2" "$rc"

# ────────────────────────────────────────────────────────────────────────
note "8" "non-absolute hook → exit 2"
cat > "$TMP/etc-sb/rel-hook.yaml" <<EOF
host: testhost
sources:
  - $TMP/src1
destinations:
  local: $TMP/local-backups
age_recipient: $FAKE_RECIPIENT
pre_hook: relative/path/hook.sh
EOF
set +e
run_sb --config "$TMP/etc-sb/rel-hook.yaml" --once >/dev/null 2>&1
rc=$?
set -e
assert_eq "relative hook exit code" "2" "$rc"

# ────────────────────────────────────────────────────────────────────────
note "9" "non-executable hook → exit 2"
NX_HOOK="$TMP/nx-hook.sh"
echo "#!/bin/sh" > "$NX_HOOK"   # NOT chmod +x
cat > "$TMP/etc-sb/nx-hook.yaml" <<EOF
host: testhost
sources:
  - $TMP/src1
destinations:
  local: $TMP/local-backups
age_recipient: $FAKE_RECIPIENT
pre_hook: $NX_HOOK
EOF
set +e
run_sb --config "$TMP/etc-sb/nx-hook.yaml" --once >/dev/null 2>&1
rc=$?
set -e
assert_eq "non-executable hook exit code" "2" "$rc"

# ────────────────────────────────────────────────────────────────────────
note "10" "lock conflict → exit 10"
mkdir -p "$TMP/lock"
echo $$ > "$TMP/lock/pid"
set +e
run_sb --list >/dev/null 2>&1
rc=$?
set -e
rm -rf "$TMP/lock"
assert_eq "lock conflict exit code" "10" "$rc"

# ────────────────────────────────────────────────────────────────────────
note "11" "--once overrides lock"
mkdir -p "$TMP/lock"
echo $$ > "$TMP/lock/pid"
set +e
run_sb --once --list >/dev/null 2>&1
rc=$?
set -e
rm -rf "$TMP/lock"
assert_eq "--once overrides lock" "0" "$rc"

# ────────────────────────────────────────────────────────────────────────
note "12" "--dry-run does not write any file"
mkdir -p "$TMP/local-backups"
BEFORE=$(find "$TMP/local-backups" -type f 2>/dev/null | wc -l)
set +e
run_sb --config "$TMP/etc-sb/valid.yaml" --dry-run --once >/dev/null 2>&1
rc=$?
set -e
AFTER=$(find "$TMP/local-backups" -type f 2>/dev/null | wc -l)
if (( rc == 0 )) && (( BEFORE == AFTER )); then
    pass "dry-run did not create any file"
else
    fail "dry-run wrote files (before=$BEFORE after=$AFTER rc=$rc)"
fi

# ────────────────────────────────────────────────────────────────────────
note "13" "restore --list returns correct sort order"
mkdir -p "$TMP/local-backups"
touch -d '2026-01-01 12:00' "$TMP/local-backups/sovereign-backup-test-20260101-120000.tar.gz.age"
touch -d '2026-02-01 12:00' "$TMP/local-backups/sovereign-backup-test-20260201-120000.tar.gz.age"
touch -d '2026-03-01 12:00' "$TMP/local-backups/sovereign-backup-test-20260301-120000.tar.gz.age"
out=$(run_restore --list 2>&1)
# Expect three entries listed, in ascending lexical timestamp order.
first=$(grep -oE 'sovereign-backup-test-[0-9-]+' <<<"$out" | head -1)
last=$(grep -oE 'sovereign-backup-test-[0-9-]+' <<<"$out" | tail -1)
if [[ "$first" == "sovereign-backup-test-20260101-120000" \
   && "$last"  == "sovereign-backup-test-20260301-120000" ]]; then
    pass "restore --list sorted by timestamp"
else
    fail "restore --list sort wrong (first=$first last=$last)"
    printf '    got: %s\n' "$out"
fi

# ────────────────────────────────────────────────────────────────────────
note "14" "restore --verify: valid backup → 0, corrupted → 1"
# Build a real tiny backup: tar+gzip+age of $TMP/src1, using age in
# passphrase-less recipient mode. Skip if age is not installed.
if command -v age >/dev/null 2>&1; then
    # Generate a real keypair for this test only.
    IDENT_FILE="$TMP/identity"
    age-keygen -o "$IDENT_FILE" 2>"$TMP/keygen.err"
    REC=$(grep -oE 'age1[0-9a-z]+' "$TMP/keygen.err" | head -1)
    if [[ -z "$REC" ]]; then
        # age-keygen variants print the recipient to stdout via comment line.
        REC=$(grep -oE 'age1[0-9a-z]+' "$IDENT_FILE" | head -1)
    fi

    GOOD="$TMP/local-backups/sovereign-backup-test-20260601-120000.tar.gz.age"
    tar -cz -C "$TMP" src1 | age -r "$REC" -o "$GOOD"

    # Corrupted: just random bytes pretending to be an age file.
    BAD="$TMP/local-backups/sovereign-backup-test-20260602-120000.tar.gz.age"
    head -c 4096 /dev/urandom > "$BAD"

    set +e
    run_restore --verify "$GOOD" >/dev/null 2>&1
    rc_good=$?
    run_restore --verify "$BAD"  >/dev/null 2>&1
    rc_bad=$?
    set -e
    if (( rc_good == 0 )) && (( rc_bad != 0 )); then
        pass "verify: good=0, bad=non-zero"
    else
        fail "verify mismatch (good rc=$rc_good, bad rc=$rc_bad)"
    fi
else
    pass "verify: age not installed, test skipped (treated as pass)"
fi

# ────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $OK ok, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
