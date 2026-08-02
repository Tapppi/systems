# bench-obs: bench observability guest — Prometheus, Grafana,
# postgres_exporter, and the Incus metrics scrape live here (tieto
# goldmill/wiki/reviews/bench/phase0-summary.md, phase 1 step 3). Scaffold
# only so far; the observability stack lands with that step.
{ ... }:

{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-obs";
}
