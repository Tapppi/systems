# arkisto: the archive guest. A NixOS LXC system container under Incus on
# dogmatix whose only job is to hold data that must outlive the machines that
# produced it — agent session transcripts mirrored off the Macs on a timer,
# and host data evacuated from tmopro18. It is a storage endpoint, not an
# application host: the only listeners are sshd and the node exporter the
# shared base brings.
#
# The archive lives on an Incus custom storage volume attached at /data, not
# on the guest rootfs, so the guest can be rebuilt or replaced without
# touching the data. Attaching that volume is part of creating the guest: with
# no volume attached the tmpfiles rules below create /data on the rootfs
# instead and the archive accumulates somewhere that a guest replacement
# destroys, with nothing to distinguish the two states from inside.
#
#   /data/agent-sessions/<hostname>/claude/   per-Mac session mirrors
#   /data/host-data/<hostname>/               data evacuated from a machine
#   /data/sources/<service>/                  non-host origins (Dropbox, …)
#   /data/inventories/<date>/                 inventory reports themselves
#
# The namespace records where data was *obtained*, not who nominally owns it:
# a stale Dropbox folder found on a Mac's disk belongs under that host, not
# under sources/dropbox, which is reserved for an export pulled from the
# account itself.
#
# Join to the tailnet once by hand, as a tagged resource:
#   incus exec arkisto -- tailscale up --authkey <key> --advertise-tags=tag:backup
# tag:backup must already exist in the tailnet ACL policy with a tagOwner, or
# the join is rejected. A tagged node is owned by the tag rather than by a
# user, so its node key does not expire the way a user device's does — which
# is what an always-on backup target needs.
#
# No --ssh, unlike the bench guests: Tailscale SSH terminates the session
# inside tailscaled and never reaches sshd, so it would hand any ACL-permitted
# peer a shell straight past the forced command that is the entire restriction
# on the sync user below.
{ pkgs, ... }:

let
  # Public keys of the per-Mac `sync` identities, added as each Mac is
  # enrolled — one bare `ssh-ed25519 AAAA... sync@<host>` string per Mac
  # (asterix, tmopro18). Empty means no Mac can write to the archive yet.
  # A key listed here is never a login: the forced command below replaces
  # whatever the client asked to run.
  syncKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIfM1dNWxJMQsnNncq3BFdlFw8jUYT6kIiTHhmLZ8aqu sync@asterix"
  ];

  # rrsync is its own top-level package in nixpkgs — pkgs.rsync ships rsync
  # and rsync-ssl only.
  #
  # -wo makes the server refuse to send, so a key that leaks can add to the
  # archive but not read it back out. `restrict` denies pty allocation,
  # agent/port/X11 forwarding and ~-escapes.
  #
  # rrsync holds an exclusive flock on /data for the duration of a write and
  # dies rather than waits if it cannot take it, so concurrent syncs are one
  # success and one failure — the per-Mac timers have to be staggered.
  syncCommand = key: ''command="${pkgs.rrsync}/bin/rrsync -wo /data",restrict ${key}'';
in
{
  imports = [ ../../../modules/nixos/lxc-guest.nix ];

  networking.hostName = "arkisto";

  users.groups.sync.gid = 900;
  users.users.sync = {
    isSystemUser = true;
    group = "sync";
    # Pinned rather than auto-allocated: /data outlives the guest, and a
    # replacement guest that allocated a different id would find the whole
    # archive owned by a number it knows nothing about.
    uid = 900;
    # NOT /data, tempting as that is: sshd reads %h/.ssh/authorized_keys, and
    # sync can write anywhere under /data, so a home there would let a leaked
    # key install an unrestricted key for itself and escape the forced
    # command. rrsync chdirs to its restricted dir and never consults $HOME.
    home = "/var/empty";
    # sshd runs a forced command through the account's login shell, so
    # nologin would reject the connection before rrsync ever ran.
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = map syncCommand syncKeys;
  };

  # The volume is created empty and root-owned; rsync runs as `sync` and
  # cannot mkdir under a root-owned mount point.
  systemd.tmpfiles.rules = [
    "d /data 0750 sync sync -"
    "d /data/agent-sessions 0750 sync sync -"
    "d /data/host-data 0750 sync sync -"
    "d /data/sources 0750 sync sync -"
    "d /data/inventories 0750 sync sync -"
  ];
}
