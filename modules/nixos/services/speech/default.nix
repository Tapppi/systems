# Kokoro CPU service in an unprivileged container. The outer container needs
# mknod/setxattr interception; native overlay also needs userxattr. Health
# notification makes systemd readiness wait for the loaded model.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.systems-speech;
  image = cfg.image;

  threads = cfg.threads;
in
{
  imports = [ ../../lxc-guest.nix ];

  options.services.systems-speech = {
    image = lib.mkOption {
      type = lib.types.str;
      description = "Kokoro CPU image, pinned by digest.";
    };
    threads = lib.mkOption {
      type = lib.types.str;
      description = "Inference thread count.";
    };
  };

  config = {

    networking.firewall = {
      allowedTCPPorts = lib.mkForce [ ];
      trustedInterfaces = lib.mkForce [ ];
      interfaces."tailscale0".allowedTCPPorts = [
        22
        8880
        9100
      ];
    };

    virtualisation.containers.storage.settings.storage.options.overlay.mountopt = "nodev,userxattr";

    virtualisation.oci-containers = {
      backend = "podman";
      containers.kokoro = {
        inherit image;
        networks = [ "host" ];
        environment = {
          OMP_NUM_THREADS = threads;
          MKL_NUM_THREADS = threads;
          OPENBLAS_NUM_THREADS = threads;
          TORCH_NUM_THREADS = threads;
          MALLOC_ARENA_MAX = "2";
          API_LOG_LEVEL = "WARNING";
        };
        podman.sdnotify = "healthy";
        extraOptions = [
          "--health-cmd=curl -fsS http://127.0.0.1:8880/v1/models || exit 1"
          "--health-interval=60s"
          "--health-timeout=20s"
          "--health-retries=5"
          "--health-start-period=300s"
          "--health-on-failure=kill"
        ];
      };
    };

    systemd.services.podman-kokoro.serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 20;
    };

    systemd.timers.kokoro-recycle = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        Persistent = true;
      };
    };
    systemd.services.kokoro-recycle = {
      path = [ pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
      };
      script = "systemctl restart podman-kokoro.service";
    };

    environment.systemPackages = [ pkgs.curl ]; # endpoint checks from the guest
  };
}
