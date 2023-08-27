{
  description = "A Haskell kernel for IPython.";

  inputs = {

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    hls.url = "github:haskell/haskell-language-server";

    hlint = { url = "github:ndmitchell/hlint/v3.6.1"; flake = false; };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    ghc-syntax-highlighter = {
      url = "github:mrkkrp/ghc-syntax-highlighter?rev=71ff751eaa6034d4aef254d6bc5a8be4f6595344";
      flake = false;
    };

  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem ["x86_64-linux" "x86_64-darwin"] (system: let
      # TODO list packages by iterating over folder
      ihaskellPackageNames = [
        "aeson" "blaze" "charts" "diagrams" "gnuplot" "graphviz" "hatex" 
        "juicypixels" "magic" "plot" "rlangqq" "static-canvas" "widgets" ];
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ 
          self.overlays.default
        ];
      };

      # reintroduce "ghc" later
      ghcMajorVersion = hsPkgs: 
        (builtins.concatStringsSep "" (pkgs.lib.lists.init (builtins.splitVersion hsPkgs.ghc.version)));

      # defers to release.nix
      mkEnv = hsPkgs: displayPkgs: let 
        majorVersion = ghcMajorVersion hsPkgs;
      in
        # returns a buildEnv
        import ./release.nix {
          compiler = "ghc${majorVersion}";
          # TODO use
          pkgs = pkgs;
          packages = displayPkgs;
          systemPackages = p: with p; [
            gnuplot # for the ihaskell-gnuplot runtime
          ];
          ihaskellOverlay = pkgs."ihaskellOverlayGhc${majorVersion}";
        };

      # executable is either static or shared
      mkExe = hsPkgs: 
        let 
          exe = (mkEnv hsPkgs (_:[])).ihaskellExe;
        in 
        pkgs.runCommand "ihaskell-wrapper" 
          { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p $out/bin
          makeWrapper ${exe}/bin/ihaskell $out/bin/ihaskell --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.which ]}
          '';


      ghcDefault = ghc96;
      # ghc92 = pkgs.ihaskellPackagesGhc92;
      # ghc94 = pkgs.ihaskellPackagesGhc94;
      ghc96 = pkgs.ihaskellPackagesGhc96;

      supportedGhcs = [
        # TODO restore, removed for now to ease development
        # ghc92 ghc94
        ghc96
      ];

      pythonDevEnv = pkgs.python3.withPackages (p: [
        p.jupyter-core p.jupyter-client
      ]);

      mkDevShell = hsPkgs:
        let
          mkPackage = hsPkgs:
            hsPkgs.developPackage {
              root = pkgs.lib.cleanSource ./.;
              name = "ihaskell";
              returnShellEnv = false;
              modifier = pkgs.haskell.lib.dontCheck;
              overrides = pkgs.ihaskellOverlayGhc96; 
              # (mkEnv hsPkgs (_:[])).ihaskellOverlay;
              withHoogle = false;
            };

          myIHaskell = mkPackage hsPkgs;

          myModifier = drv:
            pkgs.haskell.lib.addBuildTools drv (with hsPkgs; [
              cabal-install
              pythonDevEnv
              # self.inputs.hls.packages.${system}."haskell-language-server-${compilerVersion}"
              pkgs.cairo # for the ihaskell-charts HLS dev environment
              pkgs.pango # for the ihaskell-diagrams HLS dev environment
              pkgs.lapack # for the ihaskell-plot HLS dev environment
              pkgs.blas # for the ihaskell-plot HLS dev environment
            ]);
        # TODO restore withHoogle
        in (myModifier myIHaskell).envFunc {withHoogle=false;};


      # accumPackages = collec: pkgs.lib.genAttrs collec 

    in {

      # just so that we can debug the package set via repl
      legacyPackages = {

        inherit (pkgs) ihaskellPackagesGhc96;
      };

      # TODO expose all the other packages
      packages = let 
          genPackagesForGhc = hsPkgs: let 
            majorVersion = ghcMajorVersion hsPkgs; in [
              # TODO move to devShell ?
            (pkgs.lib.nameValuePair "ihaskell-${majorVersion}-dev" (mkDevShell hsPkgs))
            (pkgs.lib.nameValuePair "ihaskell-${majorVersion}" ( mkExe hsPkgs))
            (pkgs.lib.nameValuePair "ihaskell-${majorVersion}-env" (mkEnv hsPkgs (_:[])))

          ] ++ (map (name: pkgs.lib.nameValuePair (name) hsPkgs."ihaskell-${name}") ihaskellPackageNames)
          ;
        in {

        # TODO revert to 94 before merging ?
        default = self.packages.${system}.ihaskell-96;

        # Development environment
        # ihaskell-dev    = mkDevShell ghcDefault;

        # IHaskell kernel
        ihaskell    = mkExe ghcDefault;
      } 
      // (pkgs.lib.listToAttrs (pkgs.lib.concatMap genPackagesForGhc supportedGhcs))
      ;

          # pkgs.lib.foldAttrs supportedGhcs genPackagesForGhc);

      devShells = let 
        mkDevShellEntries = hsPkgs:  let
          majorVersion = ghcMajorVersion hsPkgs;
        in [
          # TODO provide devShell w/o nix libraries
            (pkgs.lib.nameValuePair "ihaskell-${majorVersion}" (mkDevShell hsPkgs))
            # (pkgs.lib.nameValuePair "ihaskell-${majorVersion}-env" (mkEnv hsPkgs))
        ];

      in rec {
        default = ihaskell-dev;

        ihaskell-dev = mkDevShell ghcDefault;

        # Full Jupyter environment
        # ihaskell-env    = mkEnv ghcDefault;
      } 
      // (pkgs.lib.listToAttrs (pkgs.lib.concatMap mkDevShellEntries supportedGhcs))
      ;
    }) // {

      overlays = { 
        default = final: prev: let 
            ihaskell-src = final.nix-gitignore.gitignoreSource
              [ "**/*.ipynb" "**/*.nix" "**/*.yaml" "**/*.yml" "**/\.*" "/Dockerfile" "/README.md" "/cabal.project" "/images" "/notebooks" "/requirements.txt" ]
              ./.;
          in 
          {

          python3 = prev.python3.override {
            packageOverrides = pfinal: pprev: {
              openapi-core = pprev.openapi-core.overridePythonAttrs(oa: {

                doCheck = false;
                doInstallCheck = false;
              });
            };
          };


          zeromq4 = prev.zeromq4.overrideAttrs(oa: {
            propagatedBuildInputs = oa.buildInputs;
          });

          ihaskellKernelSpecFunc = ihaskellKernelFile: final.runCommand "ihaskell-kernel" {} ''
            export kerneldir=$out/kernels/haskell
            mkdir -p $kerneldir
            cp ${./html}/* $kerneldir
            echo '${builtins.toJSON ihaskellKernelFile}' > $kerneldir/kernel.json
          '';

          ihaskellGhcLibFunc = exe: env: final.writeShellScriptBin "ihaskell" ''
            ${exe}/bin/ihaskell -l $(${env}/bin/ghc --print-libdir) "$@"
          '';

          ihaskellDataDirFunc = ihaskellEnv: let
            rtsopts =  "-M3g -N2";
            ihaskellGhcLib = final.ihaskellGhcLibFunc ihaskellEnv ihaskellEnv;
            ihaskellKernelFile = final.ihaskellKernelFileFunc ihaskellGhcLib rtsopts;
            ihaskellKernelSpec = final.ihaskellKernelSpecFunc ihaskellKernelFile;
            ihaskellLabextension = final.runCommand "ihaskell-labextension" {} ''
              mkdir -p $out/labextensions/
              ln -s ${./jupyterlab-ihaskell/labextension} $out/labextensions/jupyterlab-ihaskell
            '';

            ihaskellDataDirFunc' = ihaskellKernelSpec: ihaskellLabextension: final.buildEnv {
              name = "ihaskell-data-dir";
              paths = [ ihaskellKernelSpec ihaskellLabextension ];
            };

          in ihaskellDataDirFunc' ihaskellKernelSpec ihaskellLabextension;

          ihaskellKernelFileFunc = ihaskellGhcLib: rtsopts: {
            display_name = "Haskell";
            argv = [
              "${ihaskellGhcLib}/bin/ihaskell"
              "kernel"
              "{connection_file}"
              "+RTS"
            ] ++ (final.lib.splitString " " rtsopts) ++ [
              "-RTS"
            ];
            language = "haskell";
          };

          ihaskellBuildEnvFunc = {
            ihaskellEnv, 
            jupyterlab,
            # systemPackages,
            ihaskellDataDir
            }: final.pkgs.buildEnv {
            name = "ihaskell-with-packages";
            nativeBuildInputs = [ final.pkgs.makeWrapper ];
            paths = [ ihaskellEnv jupyterlab ];
            # --prefix PATH : "${nixpkgs.lib.makeBinPath ([ihaskellEnv] ++ (systemPackages nixpkgs))}" \
            postBuild = ''
              for prg in $out/bin"/"*;do
                if [[ -f $prg && -x $prg ]]; then
                  wrapProgram $prg \
                    --prefix JUPYTER_PATH : "${ihaskellDataDir}"
                fi
              done
            '';
            passthru = {
              # inherit haskellPackages;
              # inherit ihaskellExe;
              inherit ihaskellEnv;
              # inherit ihaskellOverlay;
              # inherit ihaskellLabextension;
              # inherit jupyterlab;
              # inherit ihaskellGhcLibFunc;
              # inherit ihaskellKernelFileFunc;
              # inherit ihaskellKernelSpecFunc;
              # inherit ihaskellDataDirFunc;
              # inherit ihaskellBuildEnvFunc;
            };

            meta.mainProgram = "jupyter-lab";
          };

          # prev.haskell.packages.ghc924.extend (
          ihaskellOverlayGhc92 = final.callPackage ./overlay-92.nix { 
            inherit (self) inputs; inherit ihaskell-src;
          };
          ihaskellPackagesGhc92 = prev.haskell.packages.ghc92.extend(final.ihaskellOverlayGhc92);

          ihaskellOverlayGhc94 = final.callPackage ./overlay-94.nix {
            inherit (self) inputs; inherit ihaskell-src;
          };
          ihaskellPackagesGhc94 = prev.haskell.packages.ghc94.extend(final.ihaskellOverlayGhc94);

          ihaskellOverlayGhc96 = final.callPackage ./overlay-96.nix {
            inherit (self) inputs; inherit ihaskell-src;
          };
          ihaskellPackagesGhc96 = prev.haskell.packages.ghc96.extend(final.ihaskellOverlayGhc96);
        };
      };
    };
}
