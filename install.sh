#!/usr/bin/env bash
# sovereign-backup install script, idempotent.
#
# Run as root or with sudo. Detects hostname and picks the matching config
# (sparki / legi / floki) from config/. Falls back to the annotated example
# if no host match is found.
#
# Installs:
#   /usr/local/bin/sovereign-backup
#   /usr/local/bin/sovereign-restore
#   /etc/systemd/system/sovereign-backup.service
#   /etc/systemd/system/sovereign-backup.timer
#   /etc/sovereign-backup/<hostname>.yaml  (only if missing)
#   /etc/sovereign-backup/sovereign-backup.yaml.example  (always refreshed)

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "✗ run as root (or with sudo)" >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="$(hostname -s 2>/dev/null || hostname)"

echo "▸ installing sovereign-backup binaries"
install -m 0755 "$REPO_DIR/bin/sovereign-backup"  /usr/local/bin/sovereign-backup
install -m 0755 "$REPO_DIR/bin/sovereign-restore" /usr/local/bin/sovereign-restore

echo "▸ installing systemd units"
install -m 0644 "$REPO_DIR/systemd/sovereign-backup.service" /etc/systemd/system/
install -m 0644 "$REPO_DIR/systemd/sovereign-backup.timer"   /etc/systemd/system/

echo "▸ installing config directory"
mkdir -p /etc/sovereign-backup
chmod 0750 /etc/sovereign-backup

# Always refresh the annotated example for reference
install -m 0644 "$REPO_DIR/config/sovereign-backup.yaml.example" \
    /etc/sovereign-backup/sovereign-backup.yaml.example

CFG_TARGET="/etc/sovereign-backup/${HOST}.yaml"
CFG_SOURCE="$REPO_DIR/config/${HOST}.yaml"

if [ -f "$CFG_TARGET" ]; then
    echo "  ! $CFG_TARGET exists, NOT overwritten"
    if [ -f "$CFG_SOURCE" ]; then
        install -m 0640 "$CFG_SOURCE" "${CFG_TARGET}.new"
        echo "  → new shipped config saved as ${CFG_TARGET}.new"
    fi
elif [ -f "$CFG_SOURCE" ]; then
    install -m 0640 "$CFG_SOURCE" "$CFG_TARGET"
    echo "  ✓ $CFG_TARGET created from shipped config/${HOST}.yaml"
else
    install -m 0640 "$REPO_DIR/config/sovereign-backup.yaml.example" "$CFG_TARGET"
    echo "  ✓ $CFG_TARGET created from example (hostname '$HOST' has no shipped config)"
    echo "  ! review and edit before enabling the timer"
fi

echo "▸ creating runtime dir"
mkdir -p /run/sovereign-backup
chmod 0750 /run/sovereign-backup

echo "▸ ensuring USB mountpoint exists"
mkdir -p /mnt/sov-backup
chmod 0755 /mnt/sov-backup

echo "▸ ensuring log file"
install -m 0644 /dev/null /var/log/sovereign-backup.log 2>/dev/null || true

systemctl daemon-reload

echo ""
echo "✓ sovereign-backup installed for host '$HOST'."
echo ""
echo "Next steps:"
echo "  1. Place the age recipient (public key) at the path in"
echo "     $CFG_TARGET (default /etc/sovereign-backup/age-recipient)"
echo "  2. Review the config:        sudo nano $CFG_TARGET"
echo "  3. List sources:             sudo sovereign-backup --list"
echo "  4. Dry-run:                  sudo sovereign-backup --dry-run --verbose"
echo "  5. Enable daily timer:       sudo systemctl enable --now sovereign-backup.timer"
echo "  6. Manual USB backup:        sudo sovereign-backup --target usb"
echo "  7. List existing backups:    sudo sovereign-restore --list"
echo "  8. Logs:                     journalctl -u sovereign-backup.service -e"
