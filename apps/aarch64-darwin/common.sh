# shellcheck shell=sh
#
# Shared helpers for the darwin apps. Sourced, never executed.
#
# mkApp in flake.nix execs ${self}/apps/<system>/<script>, so $0 is the store
# path of the calling script and `dirname "$0"` resolves this file beside it.
# The same works when a script is run straight out of a checkout.

# Consumed by the sourcing scripts, so shellcheck cannot see the uses here.
# shellcheck disable=SC2034
GREEN='\033[1;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
RED='\033[1;31m'
# shellcheck disable=SC2034
NC='\033[0m'

nix_flake() {
  nix --extra-experimental-features 'nix-command flakes' "$@"
}

# Echo the darwinConfigurations attribute name for this machine.
#
# Reads HostName — what `networking.hostName` pins via `scutil --set HostName`
# — deliberately in preference to the alternatives:
#   * LocalHostName is the Bonjour name. mDNSResponder renames it (asterix ->
#     asterix-2) when another device on the LAN claims the same name, which
#     would silently break every app here.
#   * ComputerName is a display name that may contain spaces and Unicode, so
#     it makes a poor flake attribute key.
# LocalHostName is still the fallback, for the pre-first-switch state on a
# fresh machine where HostName has never been set.
darwin_host() {
  if [ -n "${DARWIN_HOST:-}" ]; then
    printf '%s\n' "${DARWIN_HOST}"
    return 0
  fi

  _host=$(scutil --get HostName 2>/dev/null) || _host=""
  [ -n "$_host" ] || _host=$(scutil --get LocalHostName 2>/dev/null) || _host=""

  if [ -z "$_host" ]; then
    echo "${RED}Could not determine this machine's hostname.${NC}" >&2
    echo "${YELLOW}Set one with 'scutil --set HostName <name>', or pass DARWIN_HOST=<name>.${NC}" >&2
    return 1
  fi

  printf '%s\n' "$_host"
}

# Fail early, and accurately, when the host has no entry in this flake.
#
# `nix eval --apply builtins.hasAttr` distinguishes the two cases cleanly, and
# the distinction is the whole point of this function:
#   * flake evaluates -> exit 0, prints "true" or "false" on stdout
#   * evaluation fails -> non-zero exit, real diagnostic on stderr
# Discarding that stderr and treating any failure as "no such host" is what
# sends the user chasing a missing host entry when the actual problem is an
# unfetchable input or a broken flake.nix.
require_darwin_host() {
  _h="$1"
  _err=$(mktemp)

  if ! _found=$(nix_flake eval .#darwinConfigurations \
      --apply "cfgs: builtins.hasAttr \"${_h}\" cfgs" 2>"$_err"); then
    echo "${RED}Could not evaluate this flake's darwinConfigurations:${NC}" >&2
    cat "$_err" >&2
    rm -f "$_err"
    return 1
  fi
  rm -f "$_err"

  if [ "$_found" = "true" ]; then
    return 0
  fi

  echo "${RED}No darwinConfigurations.${_h} in this flake.${NC}" >&2
  _avail=$(nix_flake eval --raw .#darwinConfigurations \
    --apply 'cfgs: builtins.concatStringsSep ", " (builtins.attrNames cfgs)' 2>/dev/null)
  [ -n "$_avail" ] && echo "${YELLOW}Available hosts: ${_avail}${NC}" >&2
  echo "${YELLOW}Add a host entry to flake.nix, or set DARWIN_HOST to an existing one.${NC}" >&2
  return 1
}
