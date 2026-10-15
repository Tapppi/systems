{ pkgs, config, ... }:

{
  # Initializes Emacs with org-mode so we can tangle the main config
  #".emacs.d/init.el" = {
  #  text = builtins.readFile ./config/emacs/init.el;
  #};
}
