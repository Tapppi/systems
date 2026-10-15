# Adapt the T2 input patches to the pinned stable kernel's reset-resume and
# nested-report guards. Replace only 4001 in place, then append the USB parser
# repair after the upstream patch list; reordering can undo those protections.
# Both installer and host import this overlay. Keep their patch inputs identical.
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
