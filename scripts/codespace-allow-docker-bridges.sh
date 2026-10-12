#!/usr/bin/env bash
# Codespaces only: let user-defined Docker networks (such as kind's) reach the
# internet.
#
# The default Codespaces image loads Docker's rules into nftables, but a stale
# iptables-legacy FORWARD chain with policy DROP is also active and only allows
# docker0. Packets have to pass both, so traffic from any br-* bridge is
# dropped: kind nodes can't resolve DNS or pull images. This adds an ACCEPT for
# br-* bridges to the legacy DOCKER-USER chain. Firewall rules don't survive a
# Codespace restart, so .devcontainer/devcontainer.json runs this on every start.
# Safe to re-run; does nothing where iptables-legacy isn't present.
set -euo pipefail

if ! command -v iptables-legacy >/dev/null 2>&1 \
  || ! sudo iptables-legacy -L DOCKER-USER -n >/dev/null 2>&1; then
  echo "iptables-legacy DOCKER-USER chain not found; nothing to do"
  exit 0
fi

allow() {
  sudo iptables-legacy -C DOCKER-USER "$@" 2>/dev/null \
    || sudo iptables-legacy -I DOCKER-USER "$@"
}
allow -i br-+ -j ACCEPT
allow -o br-+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
echo "Allowed Docker bridge networks through iptables-legacy FORWARD"
