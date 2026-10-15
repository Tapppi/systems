# Benchmark runtime and service generator. Supply workload units privately.
# Payload and requirements are deployed to /var/lib/bench-soak/code at runtime;
# Python 3.13 and the shared library path match the supplied binary wheels.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.systems-bench-load;
  code = "/var/lib/bench-soak/code";
  venv = "/var/lib/bench-soak/venv";
  py = "${venv}/bin/python";

  python = pkgs.python313;

  wheelLibs = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
    pkgs.openssl
  ];

  soakUnit =
    {
      description,
      exec,
      extraEnv ? { },
      after ? [ ],
      autostart ? true,
      restart ? "always",
    }:
    {
      inherit description;
      wantedBy = lib.optional autostart "multi-user.target";
      after = [
        "network-online.target"
        "soak-venv.service"
      ]
      ++ after;
      wants = [ "network-online.target" ];
      requires = [ "soak-venv.service" ];
      environment = {
        PYTHONPATH = code;
        PYTHONUNBUFFERED = "1";
        HOME = "/var/lib/bench-soak";
        LD_LIBRARY_PATH = wheelLibs;
        OTEL_TRACES_EXPORTER = "none";
      }
      // extraEnv;
      serviceConfig = {
        User = "soak";
        Group = "soak";
        WorkingDirectory = code;
        ExecStart = exec;
        Restart = restart;
        RestartSec = 15;
      };
      unitConfig.StartLimitIntervalSec = 0;
    };
in
{
  imports = [
    ../../lxc-guest.nix
    { systemd.services = lib.mapAttrs (_: soakUnit) cfg.units; }
  ];

  options.services.systems-bench-load = {
    units = lib.mkOption {
      description = "Benchmark workers and drivers generated with the shared runtime and restart contract.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              description = "Unit description.";
            };
            exec = lib.mkOption {
              type = lib.types.str;
              description = "Command including the runtime interpreter.";
            };
            extraEnv = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Additional environment variables.";
            };
            after = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional ordering dependencies.";
            };
            autostart = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Start with the guest.";
            };
            restart = lib.mkOption {
              type = lib.types.str;
              default = "always";
              description = "Systemd restart policy.";
            };
          };
        }
      );
    };
  };

  config = {

    users.groups.soak = { };
    users.users.soak = {
      isSystemUser = true;
      group = "soak";
      home = "/var/lib/bench-soak";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/bench-soak 0750 soak soak -"
      "d ${code} 0750 soak soak -"
      "z /var/lib/node-exporter-textfile 0775 root soak -"
    ];

    environment.systemPackages = [
      pkgs.postgresql
      pkgs.jq
    ]; # psql for debug

    systemd.services.soak-venv = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        python
        pkgs.gcc
        pkgs.coreutils
      ];
      environment.LD_LIBRARY_PATH = wheelLibs;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "soak";
        Group = "soak";
        TimeoutStartSec = "30min"; # first build pulls ~400 MB of wheels
      };
      script = ''
        req=${code}/soak-requirements.txt
        if [ ! -f "$req" ]; then
          echo "no payload at ${code}: push benchlib/agentlib/compose first" >&2
          exit 1
        fi
        want=$(sha256sum "$req" | cut -d' ' -f1)
        have=$(cat ${venv}/.requirements-sha 2>/dev/null || true)
        if [ "$want" != "$have" ] || [ ! -x ${py} ]; then
          rm -rf ${venv}
          ${python}/bin/python3 -m venv ${venv}
          ${venv}/bin/pip install --quiet --upgrade pip
          ${venv}/bin/pip install --quiet -r "$req"
          echo "$want" > ${venv}/.requirements-sha
        fi
        ${py} -c 'import temporalio, hatchet_sdk, absurd_sdk, langgraph'
      '';
    };

  };
}
