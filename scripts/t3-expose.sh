#!/usr/bin/env bash
# =============================================================================
# t3-expose.sh — make a workspace VM's T3 Code server reachable from the T3
# apps (iPhone, iPad, Mac) over the host's tailnet address.
#
# Usage:
#   sudo ./t3-expose.sh <vm-name> [--port <port>]   install and start the forward
#   sudo ./t3-expose.sh <vm-name> --remove          stop and remove the forward
#   ./t3-expose.sh <vm-name> --print [--port <port>] [--vm-ip <ip>] [--tailnet-ip <ip>]
#                                                   print the units, change nothing
#
# The VM sits on the host-private Incus bridge and has no Tailscale. This script
# instead runs a TCP forwarder on the host: a systemd socket bound to the host's
# tailnet IPv4 address only, which hands connections to systemd-socket-proxyd,
# which relays them to the T3 Code server on port 3773 in the VM. Nothing listens
# on the LAN or on a public address; access is the tailnet plus T3's pairing code.
#
# --port is the tailnet-side port (default 3773); give each VM its own. The VM's
# address is written into the unit as a literal, so rerun this script after
# recreating the VM or whenever its address changes. --vm-ip and --tailnet-ip
# replace address discovery. The tailnet address must be in 100.64.0.0/10, the
# range Tailscale assigns IPv4 addresses from; anything else is refused.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

die()   { echo "ERROR: $*" >&2; exit 1; }
usage() { awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; }

PROXYD=/usr/lib/systemd/systemd-socket-proxyd
T3_PORT=3773                       # where the server listens inside the VM
IPV4_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
TAILNET_REGEX='^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}$'

NAME=""
PORT=3773
ACTION=install
VM_IP=""
TAILNET_IP=""

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) require_value --port "${2:-}" || exit 2
            PORT="$2"; shift 2 ;;
    --vm-ip) require_value --vm-ip "${2:-}" || exit 2
             VM_IP="$2"; shift 2 ;;
    --tailnet-ip) require_value --tailnet-ip "${2:-}" || exit 2
                  TAILNET_IP="$2"; shift 2 ;;
    --remove) ACTION=remove; shift ;;
    --print) ACTION=print; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *)  [[ -z "$NAME" ]] \
          || { echo "ERROR: unexpected extra argument '$1' (VM is '$NAME')." >&2; exit 2; }
        NAME="$1"; shift ;;
  esac
done

[[ -n "$NAME" ]] || { usage >&2; exit 2; }
validate_name "$NAME" "vm-name"
if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65535 )); then
  echo "ERROR: --port must be a number from 1024 to 65535." >&2
  exit 2
fi
UNIT_BASE="t3-forward-${NAME}"
UNIT_DIR=/etc/systemd/system

# ── Helpers ───────────────────────────────────────────────────────────────────
valid_ipv4() {
  local a b c d
  [[ "$1" =~ $IPV4_REGEX ]] || return 1
  IFS=. read -r a b c d <<< "$1"
  (( 10#$a <= 255 && 10#$b <= 255 && 10#$c <= 255 && 10#$d <= 255 ))
}

# First IPv4 address of exactly this instance. `incus list` column 4 holds only
# IPv4 addresses; a record starts at a line beginning "<name>," and an instance
# with several addresses continues on following lines.
discover_vm_ip() {
  command -v incus >/dev/null 2>&1 || die "incus CLI not found."
  # awk reads all of its input and prints at the end: closing the pipe early
  # (as `head -n 1` does) would kill the producer with SIGPIPE, and pipefail
  # would then turn a found address into a silent failure.
  incus list -c n4 -f csv | awk -F, -v name="$NAME" '
    $0 ~ /^[^,]+,/ { current = ($1 == name) }
    current && first == "" && match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
      first = substr($0, RSTART, RLENGTH)
    }
    END { if (first != "") print first }'
}

discover_tailnet_ip() {
  command -v tailscale >/dev/null 2>&1 \
    || die "tailscale CLI not found; this host must be on the tailnet."
  tailscale ip -4 | sed -n '1p'
}

render_socket() {
  cat <<EOF
[Unit]
Description=T3 Code tailnet port ${PORT} for VM ${NAME}
After=tailscaled.service

[Socket]
ListenStream=${TAILNET_IP}:${PORT}
FreeBind=yes

[Install]
WantedBy=sockets.target
EOF
}

render_service() {
  cat <<EOF
[Unit]
Description=T3 Code forward to VM ${NAME}
Requires=${UNIT_BASE}.socket
After=${UNIT_BASE}.socket

[Service]
Type=notify
ExecStart=${PROXYD} ${VM_IP}:${T3_PORT}
PrivateTmp=yes
EOF
}

# ── Remove ────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == remove ]]; then
  (( EUID == 0 )) || die "run as root: sudo $0 $NAME --remove"
  systemctl disable --now "${UNIT_BASE}.socket" 2>/dev/null || true
  systemctl stop "${UNIT_BASE}.service" 2>/dev/null || true
  rm -f "${UNIT_DIR}/${UNIT_BASE}.socket" "${UNIT_DIR}/${UNIT_BASE}.service"
  systemctl daemon-reload
  echo "==> Removed the T3 Code forward for '$NAME'."
  exit 0
fi

# ── Resolve and validate addresses ────────────────────────────────────────────
[[ -n "$VM_IP" ]] || VM_IP=$(discover_vm_ip)
[[ -n "$VM_IP" ]] || die "Instance '$NAME' is missing, stopped, or has no IPv4 address."
valid_ipv4 "$VM_IP" || die "VM address '$VM_IP' is not an IPv4 address."

[[ -n "$TAILNET_IP" ]] || TAILNET_IP=$(discover_tailnet_ip)
if [[ ! "$TAILNET_IP" =~ $TAILNET_REGEX ]] || ! valid_ipv4 "$TAILNET_IP"; then
  echo "ERROR: refusing to bind '${TAILNET_IP:-}': only a tailnet address" >&2
  echo "       (100.64.0.0/10) may be used, never a LAN or public one." >&2
  exit 1
fi

# ── Print ─────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == print ]]; then
  echo "# ${UNIT_DIR}/${UNIT_BASE}.socket"
  render_socket
  echo ""
  echo "# ${UNIT_DIR}/${UNIT_BASE}.service"
  render_service
  exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────
(( EUID == 0 )) || die "run as root: sudo $0 $NAME"
[[ -x "$PROXYD" ]] || die "$PROXYD not found (it ships in the systemd package)."

render_socket  >| "${UNIT_DIR}/${UNIT_BASE}.socket"
render_service >| "${UNIT_DIR}/${UNIT_BASE}.service"
chmod 0644 "${UNIT_DIR}/${UNIT_BASE}.socket" "${UNIT_DIR}/${UNIT_BASE}.service"

systemctl daemon-reload
systemctl enable "${UNIT_BASE}.socket"
# Stop the relay so a changed VM address takes effect; the socket starts it again
# on the next connection.
systemctl stop "${UNIT_BASE}.service" 2>/dev/null || true
systemctl restart "${UNIT_BASE}.socket"

echo "==> T3 Code in '$NAME' is forwarded on the tailnet."
echo "    App address:  http://${TAILNET_IP}:${PORT}"
echo "    Pairing link: incus exec $NAME -- sudo -u admin -H /home/admin/.local/bin/t3 pair"
echo "                  then replace the host and port in the printed URL with ${TAILNET_IP}:${PORT}"
echo "    Remove:       sudo $0 $NAME --remove"
