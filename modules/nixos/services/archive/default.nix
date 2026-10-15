# Write-only rsync archive. Attach persistent storage at /data before use.
# The stable uid/gid preserve ownership across rebuilds; /var/empty prevents
# the sync account from replacing its forced-command authorized keys.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.systems-archive;
  syncKeys = cfg.syncKeys;

  syncCommand = key: ''command="${pkgs.rrsync}/bin/rrsync -wo /data",restrict ${key}'';
in
{
  imports = [ ../../lxc-guest.nix ];

  options.services.systems-archive = {
    syncKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Keys granted write-only rsync access.";
    };
  };

  config = {

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [ ];
      trustedInterfaces = lib.mkForce [ ];
      interfaces."tailscale0".allowedTCPPorts = [ 22 ];
    };

    networking.nftables.tables.archive-egress = {
      family = "inet";
      content = ''
        chain output {
          type filter hook output priority filter; policy drop;

          oif "lo" accept

          # Replies to inbound SSH, and the return path of anything accepted
          # below. Without this the guest could receive but never answer.
          ct state established,related accept

          # Path MTU discovery and neighbour discovery. Dropping these does not
          # fail loudly, it strands large packets and reads as a stalled
          # transfer.
          meta l4proto { icmp, ipv6-icmp } accept

          # Peers on the overlay are already authenticated by Tailscale, and the
          # inbound rules decide what they may reach.
          oifname "tailscale0" accept

          # DHCP keeps eth0 addressed, and losing the lease loses the tailnet
          # with it.
          udp dport { 67, 68 } accept

          # The underlay is allowed only what keeps the node reachable at all:
          # the control plane and DERP over 443, NAT traversal and direct peer
          # sessions over UDP, and DNS to resolve them.
          #
          # 443 is open to any destination, which is the one hole this policy
          # does not close — it is required for DERP and is also the shape an
          # exfiltration attempt would take. Scoping it to tailscaled's cgroup
          # does work (`socket cgroupv2 level 2 "system.slice/tailscaled.service"`)
          # but is rejected here as too fragile to run unattended: nftables
          # resolves a cgroup path to an inode at load time, so the rule fails
          # to load if it is evaluated before tailscaled has started, and
          # silently stops matching whenever tailscaled restarts under a new
          # cgroup id. Losing egress that way is indistinguishable from a
          # network fault. What the rest of the policy buys is that nothing
          # else gets out: no arbitrary port, no plain HTTP, no substituter
          # fetch.
          udp dport { 53, 3478, 41641 } accept
          tcp dport { 53, 443 } accept
        }
      '';
    };

    users.groups.sync.gid = 900;
    users.users.sync = {
      isSystemUser = true;
      group = "sync";
      uid = 900;
      home = "/var/empty";
      shell = pkgs.bashInteractive;
      openssh.authorizedKeys.keys = map syncCommand syncKeys;
    };

    systemd.tmpfiles.rules = [
      "d /data 0750 sync sync -"
    ];
  };
}
