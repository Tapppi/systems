# Host-level toolset for dogmatix, derived from the macos-setup Brewfile.
#
# Scope is deliberately thin: this box is an Incus substrate, so language
# runtimes, cloud CLIs, databases and media tooling live in containers, not
# here. Only what is needed to log in, look around, and debug the host.
#
# Not repeated here: coreutils, findutils, diffutils, gnugrep, gnused, gnutar,
# gzip, less, util-linux (getopt), procps (watch, top) and openssh — the NixOS
# base system already provides all of them.
{ pkgs }:

with pkgs; [
  # Shell
  bashInteractive
  bash-completion
  zsh-syntax-highlighting
  zsh-history-substring-search

  # Editors
  neovim
  micro

  # Search and navigation
  ripgrep
  fd
  fzf
  bat
  eza
  zoxide
  tree
  nnn

  # Data mangling
  jq
  yq-go # mikefarah's Go yq, which is what the Brewfile's `yq` is
  sqlite

  # Monitoring
  htop
  btop
  ncdu
  lm_sensors
  pv

  # Networking and hardware inspection
  curl
  wget
  httpie
  rsync
  mtr
  nmap
  ethtool
  iproute2
  pciutils
  usbutils
  smartmontools

  # Git
  git
  git-lfs
  lazygit
  gh
  diff-so-fancy

  # Terminal multiplexing
  tmux
  tmuxinator

  # Archives and filesystems
  p7zip
  pigz
  zip
  unzip
  zstd
  e2fsprogs

  # Scripting and misc
  gawk
  gnumake
  parallel
  shellcheck
  cloc
  rename
  fdupes
  tlrc # tldr client

  # Secrets
  sops
  age
]
