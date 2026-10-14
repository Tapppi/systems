# The pinned kernel already has USB reset-resume and nested-report guards.
# These T2 input-driver adaptations preserve both while adding SPI support.
# https://github.com/t2linux/linux-t2-patches/commit/bd611d0d819cb811eace54b16cb79af1f674dca6
{ ... }:
{
  nixpkgs.overlays = [
    (_final: previous: {
      linuxPackagesFor = kernel:
        previous.linuxPackagesFor (
          if (kernel.pname or "") == "linux-t2" then
            (kernel.override {
              fetchurl = args: previous.fetchurl (
                if (args.name or "") == "4001-asahi-trackpad.patch" then
                  args // {
                    url = "https://raw.githubusercontent.com/t2linux/linux-t2-patches/bd611d0d819cb811eace54b16cb79af1f674dca6/4001-asahi-trackpad.patch";
                    hash = "sha256-O4VroQXfCX+iE2IYI6sM2mdtyfRdQpRoj1aur3Qxglc=";
                  }
                else args
              );
            }).overrideAttrs (attrs: {
              patches = attrs.patches ++ [ ./hid-magicmouse-nested-guard.patch ];
            })
          else kernel
        );
    })
  ];
}
