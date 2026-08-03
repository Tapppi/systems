# bench-temporal: Temporal bench guest (tieto goldmill/wiki/reviews/bench/
# phase0-hosting-temporal.md). Single-process server via the nixpkgs
# services.temporal module, UI, schema oneshot, default namespace.
#
# numHistoryShards=64 is PERMANENT from the first boot against a given
# database — never change it; a mismatch refuses to start and there is no
# re-shard.
#
# The DB password never enters the repo or the nix store: the generated
# config carries an @SQL_PASSWORD@ placeholder, and preStart renders the
# real file into the state dir from /root/bench-secrets.env
# (SQL_PASSWORD=...), which also feeds the schema/namespace oneshots.
{ pkgs, lib, ... }:

let
  pg = "10.135.155.1"; # bench-pg via host proxy on the static bridge IP
  # (incusbr0) — engine<->DB must not depend on tailscale being up
  schemaRoot = "${pkgs.temporal}/share/schema/postgresql/v12";
  sqlStore = db: extra: {
    sql = {
      pluginName = "postgres12";
      databaseName = db;
      connectAddr = "${pg}:5432";
      connectProtocol = "tcp";
      user = "temporal";
      password = "@SQL_PASSWORD@";
    } // extra;
  };
  uiRoot = pkgs.writeTextDir "config/production.yaml" ''
    temporalGrpcAddress: 127.0.0.1:7233
    host: 0.0.0.0
    port: 8080
    enableUi: true
  '';
in
{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-temporal";

  services.temporal = {
    enable = true;
    settings = {
      log = { stdout = true; level = "info"; };
      persistence = {
        numHistoryShards = 64;
        defaultStore = "default";
        visibilityStore = "visibility";
        datastores = {
          default = sqlStore "temporal" {
            maxConns = 10; maxIdleConns = 5; maxConnLifetime = "1h";
          };
          visibility = sqlStore "temporal_visibility" {
            maxConns = 5; maxIdleConns = 2; maxConnLifetime = "1h";
          };
        };
      };
      global = {
        membership.broadcastAddress = "100.116.6.114"; # guest tailnet IP
        metrics.prometheus = {
          framework = "prometheus";
          listenAddress = "0.0.0.0:9091";
        };
      };
      services = {
        frontend.rpc = { grpcPort = 7233; membershipPort = 6933; bindOnIP = "0.0.0.0"; httpPort = 7243; };
        history.rpc = { grpcPort = 7234; membershipPort = 6934; bindOnIP = "0.0.0.0"; };
        matching.rpc = { grpcPort = 7235; membershipPort = 6935; bindOnIP = "0.0.0.0"; };
        worker.rpc = { grpcPort = 7239; membershipPort = 6939; bindOnIP = "0.0.0.0"; };
      };
      clusterMetadata = {
        enableGlobalNamespace = false;
        failoverVersionIncrement = 10;
        masterClusterName = "active";
        currentClusterName = "active";
        clusterInformation.active = {
          enabled = true;
          initialFailoverVersion = 1;
          rpcName = "frontend";
          rpcAddress = "127.0.0.1:7233";
        };
      };
      dcRedirectionPolicy.policy = "noop";
      dynamicConfigClient = {
        filepath = "/var/lib/temporal/dynamicconfig.yaml";
        pollInterval = "60s";
      };
      publicClient.hostPort = "127.0.0.1:7233";
    };
  };

  # Render the real config (password substituted) into the state dir and
  # point the server at it. EnvironmentFile is read by the manager as root,
  # so DynamicUser still gets the variables.
  systemd.services.temporal = {
    path = [ pkgs.gnused pkgs.coreutils ];
    serviceConfig = {
      EnvironmentFile = "/root/bench-secrets.env";
      ExecStart = lib.mkForce "${pkgs.temporal}/bin/temporal-server --root / --config /var/lib/temporal/config/ -e temporal-server start";
    };
    preStart = ''
      mkdir -p /var/lib/temporal/config
      [ -f /var/lib/temporal/dynamicconfig.yaml ] || echo '{}' > /var/lib/temporal/dynamicconfig.yaml
      sed "s|@SQL_PASSWORD@|$SQL_PASSWORD|g" \
        /etc/temporal/temporal-server.yaml > /var/lib/temporal/config/temporal-server.yaml
      chmod 600 /var/lib/temporal/config/temporal-server.yaml
    '';
    after = [ "temporal-schema.service" ];
    requires = [ "temporal-schema.service" ];
  };

  # Schema before server, every activation; update-schema is idempotent.
  # setup-schema errors on an initialized DB — tolerated on purpose.
  systemd.services.temporal-schema = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.temporal ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = "/root/bench-secrets.env";
    };
    # network-online.target inside an LXC guest fires before the host bridge
    # can actually carry traffic, so without this wait the unit fails on an
    # unreachable bench-pg after a host reboot and takes temporal.service
    # (which Requires= it) down with it for good. Type=oneshot cannot use
    # Restart=, so the retry has to live in the script.
    script = ''
      export SQL_PLUGIN=postgres12 SQL_HOST=${pg} SQL_PORT=5432 SQL_USER=temporal
      export SQL_PASSWORD="$SQL_PASSWORD"
      for i in $(seq 1 60); do
        if ${pkgs.netcat}/bin/nc -z ${pg} 5432; then break; fi
        echo "waiting for postgres at ${pg}:5432 ($i/60)"
        sleep 2
      done
      temporal-sql-tool --database temporal setup-schema -v 0.0 || true
      temporal-sql-tool --database temporal update-schema \
        -d ${schemaRoot}/temporal/versioned
      temporal-sql-tool --database temporal_visibility setup-schema -v 0.0 || true
      temporal-sql-tool --database temporal_visibility update-schema \
        -d ${schemaRoot}/visibility/versioned
    '';
  };

  # Default namespace with bench retention; waits for the frontend.
  systemd.services.temporal-namespace = {
    wantedBy = [ "multi-user.target" ];
    after = [ "temporal.service" ];
    requires = [ "temporal.service" ];
    path = [ pkgs.temporal-cli ];
    environment.HOME = "/tmp"; # CLI insists on a config dir
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      for i in $(seq 1 30); do
        temporal operator cluster health --address 127.0.0.1:7233 && break
        sleep 2
      done
      temporal operator namespace describe --address 127.0.0.1:7233 -n default \
        || temporal operator namespace create --address 127.0.0.1:7233 \
             --retention 72h -n default
    '';
  };

  systemd.services.temporal-ui = {
    wantedBy = [ "multi-user.target" ];
    after = [ "temporal.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.temporal-ui-server}/bin/temporal-ui-server --root ${uiRoot} --env production start";
      DynamicUser = true;
      Restart = "on-failure";
    };
  };
}
