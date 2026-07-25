#!/usr/bin/env bash
# Bootstrap nix-rosetta-builder's VM image using nixpkgs' prebuilt
# darwin.linux-builder as a one-time aarch64-linux builder.
#
# Why this is needed: nix-rosetta-builder builds a custom NixOS image, and
# building an aarch64-linux image requires an aarch64-linux builder. nixpkgs'
# darwin.linux-builder is prebuilt and substitutable, so it has no such
# problem and can break the cycle. It is used once here and then discarded;
# rosetta-builder takes over permanently afterwards.
#
# Ports: bootstrap builder 31022, rosetta-builder 31122 — no clash.
# Run as your normal user. It will prompt for sudo.

set -euo pipefail

. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true

WORKDIR="$HOME/.local/share/linux-builder"
FLAKE="/Users/tapani/project/github/tapppi/systems"
KEYS="$WORKDIR/keys"
export KEYS

# The image the whole exercise exists to produce.
TARGET='.#darwinConfigurations.aarch64-darwin.config.system.build.toplevel'

cleanup() {
  if [[ -n "${VM_PID:-}" ]] && kill -0 "$VM_PID" 2>/dev/null; then
    echo "==> stopping bootstrap VM (pid $VM_PID)"
    kill "$VM_PID" 2>/dev/null || true
    wait "$VM_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$WORKDIR" "$KEYS"
cd "$WORKDIR"

echo "==> 1/5 generating builder keypair (if absent)"
if [[ ! -e "$KEYS/builder_ed25519" ]]; then
  ssh-keygen -q -f "$KEYS/builder_ed25519" -t ed25519 -N "" -C 'builder@localhost'
fi

echo "==> 2/5 installing keys to /etc/nix (sudo) and writing ssh config"
# The nix daemon runs as root and ssh's to the VM itself, so the key and the
# ssh Host block must be readable by root, not by us.
sudo install -g nixbld -m 600 "$KEYS/builder_ed25519" /etc/nix/builder_ed25519
sudo install -g nixbld -m 644 "$KEYS/builder_ed25519.pub" /etc/nix/builder_ed25519.pub
# Written to root's own ~/.ssh/config, not /etc/ssh/ssh_config.d/, because
# Homebrew's OpenSSH is ahead of macOS's in PATH and reads
# /opt/homebrew/etc/ssh/ssh_config — it never sees the system drop-in dir.
# Every ssh binary reads ~/.ssh/config, and the daemon's HOME is /var/root.
sudo mkdir -p /var/root/.ssh
sudo tee /var/root/.ssh/config >/dev/null <<'EOF'
Host linux-builder
  Hostname localhost
  HostKeyAlias linux-builder
  Port 31022
  User builder
  IdentityFile /etc/nix/builder_ed25519
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
sudo chmod 600 /var/root/.ssh/config

echo "==> 3/5 starting bootstrap VM in background"
nix run nixpkgs#darwin.linux-builder >"$WORKDIR/vm.log" 2>&1 &
VM_PID=$!

echo "    waiting for sshd on localhost:31022 (up to 180s)"
for i in $(seq 1 90); do
  if nc -z localhost 31022 2>/dev/null; then
    echo "    up after ~$((i * 2))s"
    break
  fi
  if ! kill -0 "$VM_PID" 2>/dev/null; then
    echo "!! VM exited early. Log:" >&2
    tail -30 "$WORKDIR/vm.log" >&2
    exit 1
  fi
  sleep 2
done
nc -z localhost 31022 2>/dev/null || {
  echo "!! VM never opened port 31022. Log:" >&2
  tail -30 "$WORKDIR/vm.log" >&2
  exit 1
}

echo "==> 4/5 building via the bootstrap builder (as root — only root is a trusted-user)"
# Run as root so the --builders setting is honoured; an untrusted user's
# --builders is silently ignored, which would look like the builder is unused.
cd "$FLAKE"
# Builder spec fields, in order:
#   uri  systems  sshKey  maxJobs  speedFactor  supportedFeatures  mandatoryFeatures
# supportedFeatures must include kvm: the disk-image build runs a VM, and Nix
# refuses to schedule a derivation on a builder that does not advertise the
# features it requires — which surfaces confusingly as "platform mismatch".
sudo --preserve-env=KEYS /nix/var/nix/profiles/default/bin/nix build \
  --no-link --print-out-paths --no-warn-dirty \
  --builders 'ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 4 1 kvm,benchmark,big-parallel,nixos-test -' \
  --builders-use-substitutes \
  "$TARGET"

echo "==> 5/5 done — image built, bootstrap VM will now be stopped"
echo "    rosetta-builder can take over from here; this VM is not needed again."
