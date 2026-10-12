# References, see for docs, licenses etc.:
# * nixCats-example flake: https://github.com/BirdeeHub/nixCats-nvim/tree/main/templates/example
# * nixCats-kickstart-nvim: https://github.com/BirdeeHub/nixCats-nvim/tree/main/templates/kickstart-nvim

{
  description = "Tapppi neovim packages configured with nixCats, plugins installed with nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixCats.url = "github:BirdeeHub/nixCats-nvim";

    # This is how we add overlays for plugins only available on github
    "plugins-wezterm-types" = {
      url = "github:gonstoll/wezterm-types";
      flake = false;
    };
  };

  # see :help nixCats.flake.outputs
  outputs = { self, nixpkgs, ... }@inputs: let
    inherit (inputs.nixCats) utils;
    luaPath = "${./.}";
    # Intel macOS is retired; preserve the remaining standalone build targets.
    forEachSystem = utils.eachSystem
      (builtins.filter (system: system != "x86_64-darwin") nixpkgs.lib.platforms.all);
    # the following extra_pkg_config contains any values
    # which you want to pass to the config set of nixpkgs
    # import nixpkgs { config = extra_pkg_config; inherit system; }
    # will not apply to module imports
    # as that will have your system values
    extra_pkg_config = {
      # allowUnfree = true;
    };
    # ${pkgs.stdenv.hostPlatform.system} is available in categoryDefinitions and packageDefinitions
    # It is resolved in the builder and passed to only those sections

    # :help nixCats.flake.outputs.overlays
    dependencyOverlays = /* (import ./overlays inputs) ++ */ [
      # This overlay grabs all the inputs named in the format
      # `plugins-<pluginName>`
      # Once we add this overlay to our nixpkgs, we are able to
      # use `pkgs.neovimPlugins`, which is a set of our plugins.
      (utils.standardPluginOverlay inputs)
      # add any other flake overlays here.

      # when other people mess up their overlays by wrapping them with system,
      # you may instead call this function on their overlay.
      # it will check if it has the system in the set, and if so return the desired overlay
      # (utils.fixSystemizedOverlay inputs.codeium.overlays
      #   (system: inputs.codeium.overlays.${system}.default)
      # )
    ];

    # :help nixCats.flake.outputs.categories
    # :help nixCats.flake.outputs.categoryDefinitions.scheme
    categoryDefinitions = { pkgs, settings, categories, extra, name, mkPlugin, ... }@packageDef: {
      # Dependencies that should be available at RUN TIME for plugins.
      # Will be available to PATH within neovim terminal
      lspsAndRuntimeDeps = {
        # TODO: web vscode json etc. lang servers, typescript tools, eslint
        general = with pkgs; [
          universal-ctags
          ripgrep
          fd
          lazygit
        ];
        lint = with pkgs; {
          default = [
            gitlint
          ];
          markdown = [
            markdownlint-cli2
          ];
          shell = [
            shellcheck
            zsh
          ];
          go = [
            golangci-lint
          ];
          python = [
            ruff
          ];
        };
        debug = with pkgs; {
          go = [ delve ];
        };
        format = with pkgs; {
          default = [
            fixjson
            yamlfix
            prettierd
          ];
          shell = [
            shfmt
          ];
          go = [
            gotools # includes goimports
            golangci-lint
          ];
          zig = [
            zig
          ];
          python = [
            ruff
          ];
        };
        rust = with pkgs; [
          rust-analyzer
          rustfmt
        ];
        zig = with pkgs; [
          zls
        ];
        typescript = with pkgs; [
          typescript
        ];
        go = with pkgs; [
          gopls
          gotools
          go-tools
          gccgo
        ];
        shell = with pkgs; [
          bash-language-server
        ];
        lua = with pkgs; [
          lua-language-server
          stylua
        ];
        neonixdev = with pkgs; [
          nix-doc
          nixd
          nixfmt
        ];
        gleam = with pkgs; [
          gleam  # Compiler, CLI tools, formatter (gleam format), and LSP (gleam lsp)
        ];
        python = with pkgs; [
          basedpyright  # Python LSP server (fork of pyright with more features)
          ruff  # Fast Python linter and formatter
        ];
        mojo = with pkgs; [
          # Note: Mojo toolchain includes LSP, linter, and formatter
          # If mojo package is not available in nixpkgs, users will need to install manually
          # or use Mason fallback outside of Nix
        ];
        swift = with pkgs; [
          # Sourcekit LSP build caching is broken on nix, it always builds.
          # Happily enough, it's available on macOS systems with xcode or another swift toolchain
          # sourcekit-lsp  # Swift LSP server (includes formatting)
        ];
      };

      # Plugins that will load at startup without using packadd:
      startupPlugins = {
        # TODO snacks and mini
        debug = with pkgs.vimPlugins; [
          nvim-nio
        ];
        snacks = with pkgs.vimPlugins; [
          snacks-nvim
        ];
        nosnacks = with pkgs.vimPlugins; [
        ];
        rust = with pkgs.vimPlugins; [
          rustaceanvim
        ];
        general = with pkgs.vimPlugins; {
          always = [
            lze
            lzextras
            vim-repeat
            vim-sleuth
            plenary-nvim
            nvim-notify # TODO: Replace with snacks notify
            nvim-spider
          ];
          extra = [
            oil-nvim
            nvim-web-devicons
            helpview-nvim
            rainbow-delimiters-nvim
          ];
        };
        # Retrieve category used as a setting from current packageDefinitions
        # :help nixCats.flake.outputs.categoryDefinitions.scheme
        themer = with pkgs.vimPlugins;
          (builtins.getAttr (categories.colorscheme or "onedark") {
              # Theme switcher without creating a new category
              "onedark" = onedark-nvim;
              "catppuccin" = catppuccin-nvim;
              "catppuccin-mocha" = catppuccin-nvim;
              "tokyonight" = tokyonight-nvim;
              "tokyonight-day" = tokyonight-nvim;
            }
          );
          # This is obviously a fairly basic usecase for this, but still nice.
      };

      # Plugins that are not loaded automatically at startup.
      # Use lze in configs to load them
      # `:NixCats pawsible` command to see the name expected by packadd
      optionalPlugins = {
        debug = with pkgs.vimPlugins; {
          # it is possible to add default values.
          # there is nothing special about the word "default"
          # but we have turned this subcategory into a default value
          # via the extraCats section at the bottom of categoryDefinitions.
          default = [
            nvim-dap
            nvim-dap-ui
            nvim-dap-virtual-text
          ];
          go = [ nvim-dap-go ];
        };
        format = with pkgs.vimPlugins; [
          conform-nvim
        ];
        lint = with pkgs.vimPlugins; [
          nvim-lint
        ];
        markdown = with pkgs.vimPlugins; [
          markdown-preview-nvim
        ];
        neonixdev = with pkgs.vimPlugins; [
          lazydev-nvim
          # This is how you enable plugins added as flake inputs
          pkgs.neovimPlugins.wezterm-types
        ];
        typescript = with pkgs.vimPlugins; [
          typescript-tools-nvim
        ];
        mini = with pkgs.vimPlugins; [
          mini-nvim
        ];
        nomini = with pkgs.vimPlugins; [
          nvim-surround
        ];
        nosnacks = with pkgs.vimPlugins; [
          telescope-fzf-native-nvim
          telescope-ui-select-nvim
          telescope-nvim
          indent-blankline-nvim
        ];
        general = {
          blink = with pkgs.vimPlugins; [
            ## TODO: snippets setup, blink, keybinds etc.
            ## TODO: snippet fix: https://github.com/BirdeeHub/nixCats-nvim/commit/c6000fb730d4067e3e1d65e9d5a2cbcd1ceaef83
            luasnip
            cmp-cmdline
            blink-cmp
            blink-compat
            colorful-menu-nvim
          ];
          treesitter = with pkgs.vimPlugins; [
            nvim-treesitter-textobjects
            nvim-treesitter.withAllGrammars
            # If only want some of the grammars
            # (nvim-treesitter.withPlugins (
            #   plugins: with plugins; [
            #     nix
            #     lua
            #   ]
            # ))
          ];

          always = with pkgs.vimPlugins; [
            nvim-lspconfig
            lualine-nvim
            gitsigns-nvim
            vim-fugitive
            vim-rhubarb
            which-key-nvim
            undotree
            lazygit-nvim
            nvim-ufo
            promise-async
          ];
          extra = with pkgs.vimPlugins; [
            fidget-nvim
            comment-nvim
            nvim-ts-context-commentstring
            vim-startuptime
          ];
        };
      };

      # shared libraries to be added to LD_LIBRARY_PATH
      # variable available to nvim runtime
      # sharedLibraries = {
      #   general = with pkgs; [ # <- this would be included if any of the subcategories of general are
      #     # libgit2
      #   ];
      # };

      # environmentVariables: Allows setting env vars for terminal and plugins at run time

      # extraWrapperArgs: Allows setting extra args for the wrapper
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/setup-hooks/make-wrapper.sh

      # lists of the functions you would have passed to
      # python.withPackages or lua.withPackages
      # do not forget to set `hosts.python3.enable` in package settings

      # get the path to this python environment
      # in your lua config via
      # vim.g.python3_host_prog
      # or run from nvim terminal via :!<packagename>-python3
      python3.libraries = {
        test = (_:[]);
      };
      # populates $LUA_PATH and $LUA_CPATH
      extraLuaPackages = {
        general = [ (_:[]) ];
      };

      # see :help nixCats.flake.outputs.categoryDefinitions.default_values
      # WARNING: use of categories argument in this set will cause infinite recursion
      # The categories argument of this function is the FINAL value.
      # You may use it in any of the other sets.
      extraCats = {
        debug = [
          [ "debug" "default" ]
        ];
        lint = [
          [ "lint" "default" ]
        ];
        format = [
          [ "format" "default" ]
        ];
        shell = [
          [ "lint" "shell" ]
          [ "format" "shell" ]
        ];
        markdown = [
          [ "lint" "markdown" ]
        ];
        neonixdev = [
          [ "lua" ]
        ];
        go = [
          [ "lint" "go" ]
          [ "debug" "go" ]
          [ "format" "go" ]
        ];
        zig = [
          [ "format" "zig" ]
        ];
        python = [
          [ "lint" "python" ]
          [ "format" "python" ]
        ];
        mojo = [
          [ "lint" "mojo" ]
          [ "format" "mojo" ]
        ];
      };
    };

    # We define default categories here, so we can use them for both default and test packages
    defaultCategories = {
      general = true;
      # debug = { default = true; };
      lint = { default = true; };
      format = { default = true; };

      snacks = false;
      nosnacks = true;
      mini = true;
      nomini = false;

      shell = true;
      markdown = true;
      lua = true;
      neonixdev = true;
      gleam = true;
      python = true;
      zig = false;
      swift = true;

      # NOTE: ALSO enables debug.go and debug.default due to our extraCats in categoryDefinitions
      # go = true;
      # rust = true;
      typescript = true;
      # mojo = true;

      # Categories don't *have* to have plugins to be used:
      lspDebugMode = false;
      themer = true;
      colorscheme = "catppuccin-mocha";
    };

    # see :help nixCats.flake.outputs.packageDefinitions
    # The entire set is directly translated to a Lua table for querying, and a get function is defined.
    packageDefinitions = {
      # The name here is the name of the package and the default command name for it.
      nvim = { ... }: {
      # nvim = { pkgs, name, ... }@misc: {
        settings = {
          # :help nixCats.flake.outputs.settings for all of the settings available
          suffix-path = true;
          suffix-LD = true;
          # WARNING: Make sure these dont conflict with other installed packages on your path, or the build will fail
          aliases = [ "vim" "vi" ];

          wrapRc = true;
          # Name for searching .config and .local and so on, i.e. controls sharing between packages for auth etc.
          # :h $NVIM_APPNAME
          configDirName = "nvim";
          # neovim-unwrapped = inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.neovim;
          # hosts.python3.enable = true;
          # hosts.node.enable = true;
        };
        # enable the categories you want from categoryDefinitions
        categories = defaultCategories // {};
        extra = {
          # Add extra configuration here to not bloat categories, available to lua the exact same way
          # nixCats.extra("path.to.val") will perform vim.tbl_get(nixCats.extra, "path" "to" "val")
          # The main nixCats("path.to.cat") will report true if `path.to = true` even though path.to.cat would be
          # an indexing error in that case. This is useful for subcategories, but bad for fetching values.
          nixdExtras = {
            inherit nixpkgs;
            # or nixpkgs = ''import ${pkgs.path} {}'';
          };
        };
      };
      testNvim = { ... }: {
        settings = {
          suffix-path = true;
          suffix-LD = true;
          # IMPURE PACKAGE: normal config reload from unwrappedCfgPath
          wrapRc = false;
          # Or unset unwrappedCfgPath to use `stdpath('config') := ~/.config/testNvim` and symlink there
          unwrappedCfgPath = "/Users/tapani/project/github/tapppi/nix-config/flakes/nvim";

          # Alias to tvim for ease of use
          aliases = [ "tvi" ];

          configDirName = "testNvim";
        };
        # Includes same categories as default package in order to test configs for the main package
        categories = defaultCategories // {};
        extra = {
          nixdExtras = {
            inherit nixpkgs;
          };
        };
      };
    };

    # defaultPackageName controls the the top level option passed to utils.mkNixosModules and utils.mkHomeModules
    # In addition, every package exports its own module via overrideable passhtru so you can yourpackage.homeModule
    # If you made a package named `nixCats` your default package, you could configure the modules like:
    # config.nixCats = {
    #   enable = true;
    #   packageNames = [ "nixCats" ]; # <- the packages you want installed
    #   <see :h nixCats.module for options>
    # }
    defaultPackageName = "nvim";
    testPackageName = "testNvim";
  in
  # you shouldnt need to change much past here, but you can if you wish.
  # but you should at least eventually try to figure out whats going on here!
  # see :help nixCats.flake.outputs.exports
  forEachSystem (system: let
    # and this will be our builder! it takes a name from our packageDefinitions as an argument, and builds an nvim.
    nixCatsBuilder = utils.baseBuilder luaPath {
      # we pass in the things to make a pkgs variable to build nvim with later
      inherit nixpkgs system dependencyOverlays extra_pkg_config;
      # and also our categoryDefinitions and packageDefinitions
    } categoryDefinitions packageDefinitions;
    # call it with our defaultPackageName
    defaultPackage = nixCatsBuilder defaultPackageName;
    testPackage = nixCatsBuilder testPackageName;

    # this pkgs variable is just for using utils such as pkgs.mkShell
    # within this outputs set.
    pkgs = import nixpkgs {
      inherit system;
      config = extra_pkg_config;
    };
    # The one used to build neovim is resolved inside the builder
    # and is passed to our categoryDefinitions and packageDefinitions
  in {
    # these outputs will be wrapped with ${system} by utils.eachSystem

    # this will generate a set of all the packages
    # in the packageDefinitions defined above
    # from the package we give it.
    # and additionally output the original as default.
    packages = utils.mkAllWithDefault defaultPackage;

    # choose your package for devShell
    # and add whatever else you want in it.
    devShells = {
      default = pkgs.mkShell {
        name = defaultPackageName;
        packages = [ defaultPackage ];
        inputsFrom = [ ];
        shellHook = ''
        '';
      };
      test = pkgs.mkShell {
        name = testPackageName;
        packages = [ defaultPackage testPackage ];
        inputsFrom = [ ];
        shellHook = ''
            export EDITOR=tvi
        '';
      };
    };

  }) // (let
    # we also export a nixos module to allow reconfiguration from configuration.nix
    nixosModule = utils.mkNixosModules {
      moduleNamespace = [ defaultPackageName ];
      inherit defaultPackageName dependencyOverlays luaPath
        categoryDefinitions packageDefinitions extra_pkg_config nixpkgs;
    };
    # and the same for home manager
    homeModule = utils.mkHomeModules {
      moduleNamespace = [ defaultPackageName ];
      inherit defaultPackageName dependencyOverlays luaPath
        categoryDefinitions packageDefinitions extra_pkg_config nixpkgs;
    };
  in {

    # these outputs will be NOT wrapped with ${system}

    # this will make an overlay out of each of the packageDefinitions defined above
    # and set the default overlay to the one named here.
    overlays = utils.makeOverlays luaPath {
      inherit nixpkgs dependencyOverlays extra_pkg_config;
    } categoryDefinitions packageDefinitions defaultPackageName;

    nixosModules.default = nixosModule;
    homeModules.default = homeModule;

    inherit utils nixosModule homeModule;
    inherit (utils) templates;
  });

}
