# Standalone public composition; all network identities are synthetic.
{
  networking.hostName = "metrics-example";
  services.systems-bench-obs = {
    nodeTargets = {
      host = [ "host.example:9100" ];
      guest = [ "guest.example:9100" ];
    };
    temporalTargets = [ "temporal.example:9091" ];
    hatchetTargets = [ "hatchet.example:9090" ];
    incusTargets = [ "incus.example:8444" ];
    hatchetApiUrl = "http://hatchet.example:8888";
    hatchetQueues = "sample-work";
    postgresDatabases = "sample_database";
    soakEngines = [ "sample-engine" ];
  };
}
