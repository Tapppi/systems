# Caller-owned base pin; opt-in until the consumer transfers executable ownership.
{ pkgs }:
[
  pkgs.ripgrep
  pkgs.fd
  pkgs.fzf
  pkgs.jq
  pkgs.yq-go
  pkgs.uv
  pkgs.nodejs_24
]
