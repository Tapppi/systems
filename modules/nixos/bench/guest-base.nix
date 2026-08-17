# Bench-specific base for the bench-* NixOS LXC guests under Incus on
# dogmatix (workflow-engine bench; see tieto goldmill/wiki/reviews/bench/).
# Everything these guests share with every other LXC guest lives in
# ../lxc-guest.nix.
#
# The bench-guest Incus profile adds security.nesting=true to the shared
# device set — without nesting, nix builds inside the unprivileged guest fail
# on sandbox namespace setup:
#   incus launch images:nixos/unstable <name> -p default -p bench-guest
#
# Join each guest to the tailnet once by hand:
#   incus exec <name> -- tailscale up --ssh
{ ... }:

{
  imports = [ ../lxc-guest.nix ];
}
