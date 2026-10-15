# Small server administration toolset.
{ pkgs }:

with pkgs; [
  bashInteractive
  bash-completion
  zsh-syntax-highlighting
  zsh-history-substring-search

  neovim
  micro

  ripgrep
  fd
  fzf
  bat
  eza
  zoxide
  tree
  nnn

  jq
  yq-go # mikefarah's Go yq, which is what the Brewfile's `yq` is
  sqlite

  htop
  btop
  ncdu
  lm_sensors
  pv

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

  git
  git-lfs
  lazygit
  gh
  diff-so-fancy

  tmux
  tmuxinator

  p7zip
  pigz
  zip
  unzip
  zstd
  e2fsprogs

  gawk
  gnumake
  parallel
  shellcheck
  cloc
  rename
  fdupes
  tlrc # tldr client

  sops
  age
]
