# bench-absurd: Absurd bench guest — schema glue, workers, Habitat, and the
# scheduler timer live here (tieto goldmill/wiki/reviews/bench/
# phase0-hosting-absurd.md). Scaffold only so far; the Absurd services land
# with bench phase 1 step 4.
{ ... }:

{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-absurd";
}
