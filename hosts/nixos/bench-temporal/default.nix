# bench-temporal: Temporal bench guest — services.temporal (single-process,
# numHistoryShards=64 permanent from first boot), UI unit, and the schema
# oneshot live here (tieto goldmill/wiki/reviews/bench/
# phase0-hosting-temporal.md, phase 1 step 6). Scaffold only so far; the
# Temporal services land with that step.
{ ... }:

{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-temporal";
}
