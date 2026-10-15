# Run from the public flake as documented in ../README.md.
{ nixpkgs, pkgs }:
let
  lib = nixpkgs.lib;
  mk =
    extra:
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../default.nix
        ./synthetic.nix
        extra
      ];
    }).config;
  base = mk { };
  extended = mk {
    services.systems-bench-obs = {
      dashboardFiles."sample.json" = ./fixtures/dashboards/sample.json;
      extraAlertRules.fleet = [
        {
          alert = "SyntheticTargetMissing";
          expr = ''absent(up{instance="additional.example:9100"})'';
        }
      ];
    };
  };
  legacy = mk {
    services.systems-bench-obs = {
      dashboards = ./fixtures/dashboards;
      alertRules = ./fixtures/alerts.nix;
      extraAlertRules.custom = [
        {
          alert = "SyntheticExtra";
          expr = "vector(0) == 1";
        }
      ];
    };
  };
  unknown = mk { services.systems-bench-obs.extraAlertRules.typo = [ ]; };
  badFilename = mk {
    services.systems-bench-obs.dashboardFiles."nested/file.json" = ./fixtures/dashboards/sample.json;
  };
  failures = c: lib.filter (a: !a.assertion) c.assertions;
  rules = c: (builtins.fromJSON (builtins.head c.services.prometheus.rules)).groups;
  findRule = c: name: lib.findFirst (r: r.alert == name) null (lib.concatMap (g: g.rules) (rules c));
  directory =
    c: (builtins.head c.services.grafana.provision.dashboards.settings.providers).options.path;
  ruleFile =
    c: pkgs.writeText "synthetic-bench-rules.json" (builtins.head c.services.prometheus.rules);
in
assert failures base == [ ];
assert failures extended == [ ];
assert failures legacy == [ ];
assert lib.any (a: lib.hasInfix "unknown groups: typo" a.message) (failures unknown);
assert lib.any (a: lib.hasInfix "JSON filenames" a.message) (failures badFilename);
assert (findRule base "GrafanaDashboardsMissing").expr == "grafana_stat_totals_dashboard < 2";
assert (findRule extended "GrafanaDashboardsMissing").expr == "grafana_stat_totals_dashboard < 3";
assert lib.hasInfix ''count(up{job="node"}) < 2'' (findRule base "BenchTargetMissing").expr;
assert (findRule base "SyntheticTargetMissing") == null;
assert
  (findRule extended "SyntheticTargetMissing").expr
  == ''absent(up{instance="additional.example:9100"})'';
assert (findRule legacy "SyntheticInventory").expr == "vector(1) == 0";
assert (findRule legacy "SyntheticExtra") != null;
assert (findRule legacy "GrafanaDashboardsMissing") == null;
assert toString (directory legacy) == toString ./fixtures/dashboards;
pkgs.runCommand "bench-observability-check"
  {
    nativeBuildInputs = [
      pkgs.prometheus.cli
      pkgs.python3
    ];
  }
  ''
    promtool check rules ${ruleFile base}
    promtool check rules ${ruleFile extended}
    promtool check rules ${ruleFile legacy}
    python3 ${./check-dashboards.py} ${directory base} ${directory extended}
    touch "$out"
  ''
