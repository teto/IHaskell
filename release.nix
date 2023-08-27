{ compiler
# , pkgs ? import <pkgs> {}
, pkgs

# haskell packages to add to environment
, packages ? (_: [])
, pythonPackages ? (_: [])
, rtsopts ? "-M3g -N2"
, staticExecutable ? false
, systemPackages ? (_: [])
, ihaskellOverlay ? (final: prev: {})
}:

let
  # ihaskell-src = pkgs.nix-gitignore.gitignoreSource
  #   [ "**/*.ipynb" "**/*.nix" "**/*.yaml" "**/*.yml" "**/\.*" "/Dockerfile" "/README.md" "/cabal.project" "/images" "/notebooks" "/requirements.txt" ]
  #   ./.;
  # displays = self: builtins.listToAttrs (
  #   map
  #     (display: { name = "ihaskell-${display}"; value = self.callCabal2nix display "${ihaskell-src}/ihaskell-display/ihaskell-${display}" {}; })
  #     [ "aeson" "blaze" "charts" "diagrams" "gnuplot" "graphviz" "hatex" "juicypixels" "magic" "plot" "rlangqq" "static-canvas" "widgets" ]);
  haskellPackages = pkgs.haskell.packages."${compiler}".override (old: {
    overrides = pkgs.lib.composeExtensions (old.overrides or (_: _: {})) ihaskellOverlay;
  });

  # ihaskellOverlay = (self: super: {
  #   ihaskell = pkgs.haskell.lib.overrideCabal (
  #                    self.callCabal2nix "ihaskell" ihaskell-src {}) (_drv: {
  #     preCheck = ''
  #       export HOME=$TMPDIR/home
  #       export PATH=$PWD/dist/build/ihaskell:$PATH
  #       export GHC_PACKAGE_PATH=$PWD/dist/package.conf.inplace/:$GHC_PACKAGE_PATH
  #     '';
  #   });
  #   ghc-parser     = self.callCabal2nix "ghc-parser" (builtins.path { path = ./ghc-parser; name = "ghc-parser-src"; }) {};
  #   ipython-kernel = self.callCabal2nix "ipython-kernel" (builtins.path { path = ./ipython-kernel; name = "ipython-kernel-src"; }) {};
  # } // displays self);

  # statically linking against haskell libs reduces closure size at the expense
  # of startup/reload time, so we make it configurable
  ihaskellExe = if staticExecutable
    then pkgs.haskell.lib.justStaticExecutables haskellPackages.ihaskell
    else pkgs.haskell.lib.enableSharedExecutables haskellPackages.ihaskell;
  ihaskellEnv = haskellPackages.ghcWithPackages packages;
  jupyterlab = pkgs.python3.withPackages (ps: [ ps.jupyterlab ] ++ pythonPackages ps);
  ihaskellGhcLibFunc = exe: env: pkgs.writeShellScriptBin "ihaskell" ''
    ${exe}/bin/ihaskell -l $(${env}/bin/ghc --print-libdir) "$@"
  '';
  ihaskellKernelFileFunc = ihaskellGhcLib: rtsopts: {
    display_name = "Haskell";
    argv = [
      "${ihaskellGhcLib}/bin/ihaskell"
      "kernel"
      "{connection_file}"
      "+RTS"
    ] ++ (pkgs.lib.splitString " " rtsopts) ++ [
      "-RTS"
    ];
    language = "haskell";
  };
  ihaskellKernelSpecFunc = ihaskellKernelFile: pkgs.runCommand "ihaskell-kernel" {} ''
    export kerneldir=$out/kernels/haskell
    mkdir -p $kerneldir
    cp ${./html}/* $kerneldir
    echo '${builtins.toJSON ihaskellKernelFile}' > $kerneldir/kernel.json
  '';
  ihaskellLabextension = pkgs.runCommand "ihaskell-labextension" {} ''
    mkdir -p $out/labextensions/
    ln -s ${./jupyterlab-ihaskell/labextension} $out/labextensions/jupyterlab-ihaskell
  '';
  ihaskellDataDirFunc = ihaskellKernelSpec: ihaskellLabextension: pkgs.buildEnv {
    name = "ihaskell-data-dir";
    paths = [ ihaskellKernelSpec ihaskellLabextension ];
  };
  ihaskellBuildEnvFunc = { ihaskellEnv, jupyterlab, systemPackages, ihaskellDataDir }: pkgs.buildEnv {
    name = "ihaskell-with-packages";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    paths = [ ihaskellEnv jupyterlab ];
    postBuild = ''
      for prg in $out/bin"/"*;do
        if [[ -f $prg && -x $prg ]]; then
          wrapProgram $prg \
            --prefix PATH : "${pkgs.lib.makeBinPath ([ihaskellEnv] ++ (systemPackages pkgs))}" \
            --prefix JUPYTER_PATH : "${ihaskellDataDir}"
        fi
      done
    '';
    passthru = {
      inherit haskellPackages;
      inherit ihaskellExe;
      inherit ihaskellEnv;
      inherit ihaskellOverlay;
      inherit ihaskellLabextension;
      inherit jupyterlab;
      inherit ihaskellGhcLibFunc;
      inherit ihaskellKernelFileFunc;
      inherit ihaskellKernelSpecFunc;
      inherit ihaskellDataDirFunc;
      inherit ihaskellBuildEnvFunc;
    };

    meta.mainProgram = "jupyter-lab";
  };
in ihaskellBuildEnvFunc {
  inherit ihaskellEnv jupyterlab systemPackages;
  ihaskellDataDir = let
    ihaskellGhcLib = ihaskellGhcLibFunc ihaskellExe ihaskellEnv;
    ihaskellKernelFile = ihaskellKernelFileFunc ihaskellGhcLib rtsopts;
    ihaskellKernelSpec = ihaskellKernelSpecFunc ihaskellKernelFile;
  in ihaskellDataDirFunc ihaskellKernelSpec ihaskellLabextension;
}
