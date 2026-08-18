# tts: the speech guest. A NixOS LXC system container under Incus on dogmatix
# that serves Kokoro-82M behind the OpenAI `/v1/audio/speech` contract, so the
# aloud-tts plugin in the tieto vault can read notes aloud on the desktop and
# on iOS over one tailnet endpoint. Single-workload guest: podman runs one
# upstream image, and everything else here exists to keep that image alive,
# bounded and reachable.
#
# The workload is an OCI image rather than a nix derivation because
# Kokoro-FastAPI is not in nixpkgs — only the `kokoro` library underneath it is
# (`python3Packages.kokoro`, with `misaki` for G2P). Packaging the server
# itself is three small derivations and a dependency relaxation, which is worth
# doing when this endpoint gets a permanent home and is not worth doing to a
# guest whose whole purpose is to hold the service while tmopro18 is rebuilt.
#
# Model weights are baked into the image: `download_model.py` runs at build
# time and lands ~312 MiB of Kokoro-82M under /app/api/src/models/v1_0, and the
# 68 voice packs are in the upstream git tree. Nothing is fetched at first run,
# there is no Hugging Face cache to persist, and no volume is attached — the
# guest is disposable and rebuilding it costs one image pull. The one way to
# break that is the upstream compose file, which bind-mounts the source tree
# over /app/api and shadows the baked model; this runs the image as built.
#
# Egress is left open, unlike arkisto, which drops it. This guest has to reach
# ghcr.io on every version bump for a 1.5 GB pull, and a drop policy would turn
# each of those into an outage whose only symptom is a unit that never becomes
# healthy.
#
# Nesting: podman inside an unprivileged Incus container needs
# `security.nesting=true`, which the shared `lxc-guest` Incus profile already
# carries for in-guest nix builds, plus two syscall interceptions that it does
# not — hence the second profile below. Both exist to let podman's overlay
# storage driver work from inside a user namespace: `mknod` for the character
# device 0:0 that overlayfs uses as a whiteout, and `setxattr` for the
# `trusted.overlay.opaque` marker on a deleted directory, which needs
# CAP_SYS_ADMIN in the *initial* namespace and so cannot be written from here.
# Without the second one, deleting a file works and deleting a directory that
# exists in a lower layer returns EIO. Incus 7.0.0 shipped a broken mknodat
# interception; 7.0.1 is the fix, and is what dogmatix runs.
#
# Create the host-side profile once — its own rather than an addition to
# lxc-guest, because these keys are for guests that nest an OCI runtime and
# every other guest is better off without the seccomp round trip to incusd:
#   incus profile create podman-guest
#   incus profile set podman-guest security.syscalls.intercept.mknod=true
#   incus profile set podman-guest security.syscalls.intercept.setxattr=true
#   incus profile set podman-guest description="Guests that nest an OCI \
#     runtime: overlayfs whiteout (mknod) and opaque-dir (setxattr) \
#     interception. Compose with lxc-guest."
#
# Create the guest on dogmatix:
#   incus launch images:nixos/unstable tts -p default -p lxc-guest -p podman-guest
#   incus config set tts limits.memory=4GiB limits.cpu.allowance=350ms/100ms \
#     boot.autostart=true boot.autostart.priority=20
# Join it to the tailnet once by hand, as a tagged resource:
#   incus exec tts -- tailscale up --authkey <key> --advertise-tags=tag:svc-tts
# tag:svc-tts must already exist in the tailnet ACL policy with a tagOwner, or
# the join is rejected. Tagged rather than user-owned because a user device's
# node key expires and would take the endpoint down with it — silently, and on
# a schedule nobody is watching. A tagged node's key does not expire.
#
# Deploy from asterix once the guest has joined:
#   nix run nixpkgs#nixos-rebuild -- switch --flake .#tts --target-host root@tts
{ pkgs, lib, ... }:

let
  # v0.8.0, pinned by the index digest so the tag cannot move under a redeploy.
  # Upstream publishes `latest` from the `release` branch and it currently
  # resolves to this same digest, but that is a fact about today, not a
  # guarantee.
  #
  # The floor is v0.7.2, not convenience: v0.3.0 fixed a per-request
  # voice-tensor leak that took RSS to 7.6 GB in two and a half days (upstream
  # #453), and v0.7.2 fixed CVE-2025-62727, a quadratic Range parse reachable
  # through the audio download path.
  #
  # Rollback, if v0.8.0 misbehaves — the build that served this endpoint from
  # tmopro18, still in the registry:
  #   sha256:bcf38f9bf7f040b0465dd4352eb0fa0b2db42d4bd91eba16acef0b40e5c57905
  image = "ghcr.io/remsky/kokoro-fastapi-cpu@sha256:d32322c61254a871e0bc9c38d4e60cd18539cf9b1a2fc8f3ae04409061d0793b";

  # Inference is PyTorch on CPU. Pinned rather than reduced: the count matches
  # the cores the guest actually has, and stating it means a change to the
  # Incus CPU limits cannot silently leave PyTorch sizing its pools from
  # something else. The lever that matters for memory is MALLOC_ARENA_MAX
  # below, not this.
  threads = "4";
in
{
  imports = [ ../../../modules/nixos/lxc-guest.nix ];

  networking.hostName = "tts";

  # Reachable on the overlay only. The shared base opens 22 on every interface
  # and trusts the whole of tailscale0; both are dropped, so the LAN — dogmatix
  # included — cannot reach the synthesis endpoint, and so the ports this guest
  # serves are a list rather than a side effect of trusting an interface.
  #
  # Recovery if this locks the guest out of the tailnet: `incus exec tts` from
  # dogmatix enters the namespace directly and does not traverse the firewall.
  networking.firewall = {
    allowedTCPPorts = lib.mkForce [ ];
    trustedInterfaces = lib.mkForce [ ];
    interfaces."tailscale0".allowedTCPPorts = [
      22
      8880 # Kokoro-FastAPI; aloud-tts appends /v1/audio/speech to the base URL
      9100 # node exporter, scraped by bench-obs
    ];
  };

  # The guest-side half of the overlay story, and the half that does not depend
  # on host state being right. `userxattr` puts overlayfs's opaque-directory
  # markers in the `user.*` namespace instead of `trusted.*`, which an
  # unprivileged mount may write without any interception at all — verified
  # against this kernel on a ZFS-backed guest rootfs. containers/storage adds
  # this flag itself only when it believes it is rootless, and rootful podman
  # in a user namespace is exactly the case it gets wrong.
  #
  # Belt and braces with the profile interceptions rather than instead of them:
  # the interceptions make containers/storage's own probe pass, so it commits
  # to native overlay rather than deciding the driver is unsupported, and this
  # makes the mounts correct even if the profile is ever missing. Changing this
  # setting after the store has content strands markers in the other namespace
  # — wipe /var/lib/containers/storage if it ever has to change.
  #
  # Deliberately *not* paired with fuse-overlayfs in the podman path. Its mere
  # presence changes the outcome: when the probe fails, containers/storage
  # silently moves the whole store onto fuse-overlayfs if it can find the
  # binary, which turns a loud misconfiguration into a quiet slow one. If it is
  # ever wanted, ask for it by name via `mount_program`.
  virtualisation.containers.storage.settings.storage.options.overlay.mountopt =
    "nodev,userxattr";

  virtualisation.oci-containers = {
    backend = "podman";
    containers.kokoro = {
      inherit image;
      # Host networking, so the image binds :8880 straight into the guest's
      # network namespace and the firewall above is the only thing deciding who
      # may connect. Published ports would be the conventional choice, but they
      # put netavark and a NAT bridge between the tailnet and the endpoint, and
      # netavark programs its port forwards through iptables while this guest
      # runs an nftables firewall. Whether that composes depends on which
      # iptables backend is on PATH, and the failure mode is a port that
      # answers from inside the guest and times out from the phone. A
      # single-workload guest gains nothing from the bridge.
      networks = [ "host" ];
      environment = {
        OMP_NUM_THREADS = threads;
        MKL_NUM_THREADS = threads;
        OPENBLAS_NUM_THREADS = threads;
        TORCH_NUM_THREADS = threads;
        # glibc will open up to eight malloc arenas per core under a threaded
        # allocator and this process never gives one back. Two is the usual
        # floor that costs no measurable throughput, and it is the cheapest
        # lever on the resident set of a PyTorch server.
        MALLOC_ARENA_MAX = "2";
        # Upstream ships DEBUG. Every request logs several lines, and the
        # journal is on the guest rootfs.
        API_LOG_LEVEL = "WARNING";
      };
      # `active` should mean `answering`, not `started`. Loading the model
      # takes the better part of a minute on this CPU, and without this the
      # unit goes active while every request still fails — which is the state
      # a redeploy would report as success.
      podman.sdnotify = "healthy";
      extraOptions = [
        # curl is in the image at /usr/bin/curl; nothing is installed to make
        # this work.
        "--health-cmd=curl -fsS http://127.0.0.1:8880/v1/models || exit 1"
        # Deliberately slack. /v1/models is a trivial handler, but it shares an
        # event loop with synthesis that is CPU-bound on four slow cores, so a
        # probe can lose to a long paragraph. Five consecutive failures a
        # minute apart is a wedged server; one slow answer is a Sunday
        # afternoon.
        "--health-interval=60s"
        "--health-timeout=20s"
        "--health-retries=5"
        "--health-start-period=300s"
        "--health-on-failure=kill"
      ];
    };
  };

  # The workload is capped below the guest's own Incus limit on purpose. Let it
  # run the guest out of memory instead and the kernel picks the victim, and
  # the plausible victims are tailscaled and sshd — which turns a recoverable
  # synthesis failure into a guest nobody can reach. Capped here, the container
  # is always what dies, and systemd puts it straight back.
  #
  # 3500M is set against measurements, not upstream's advice, and the two
  # disagree: upstream sizes the CPU image at "at least 4gb", while the build
  # this replaces sat at 2.65 GiB anonymous on tmopro18 with a 3.10 GiB peak
  # over twelve days — against 1.71 GiB when it was first measured. v0.8.0
  # dropped ffmpeg and moved to a slimmer base, so it may well need less than
  # any of those. Measure a week in and tighten; this number is a ceiling
  # chosen to avoid a restart loop on day one, not a budget.
  systemd.services.podman-kokoro.serviceConfig = {
    MemoryMax = "3500M";
    Restart = lib.mkForce "always";
    RestartSec = 20;
  };

  # 1.71 GiB to a 3.10 GiB peak over twelve days of light use is an upward
  # trend nobody has explained, on a host with no swap. A weekly restart costs
  # one cold start — the model is in the image, so nothing is downloaded — and
  # closes the failure mode while the cause is unknown. Drop it once a week of
  # the memory series here is flat.
  systemd.timers.kokoro-recycle = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:30";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
  systemd.services.kokoro-recycle = {
    path = [ pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      # `systemctl restart` blocks until the unit is up, and up here means the
      # healthcheck has passed — a cold model load, not a fork. The default
      # 90 s start timeout would mark this unit failed every week while the
      # restart it asked for was still succeeding behind it.
      TimeoutStartSec = "10min";
    };
    script = "systemctl restart podman-kokoro.service";
  };

  environment.systemPackages = [ pkgs.curl ]; # endpoint checks from the guest
}
