{ ihaskell-src, libsodium, haskell }:
hfinal: hprev: let 
  displays = hfinal': builtins.listToAttrs (
    map (display: {
      name = "ihaskell-${display}";
      value = hfinal'.callCabal2nix display "${ihaskell-src}/ihaskell-display/ihaskell-${display}" {}; })
          [ "aeson" "blaze" "charts" "diagrams" "gnuplot" "graphviz" "hatex" "juicypixels" "magic" "plot" "rlangqq" "static-canvas" "widgets" ]);
  in with haskell.lib; {
    ihaskell = (overrideCabal (
                        hfinal.callCabal2nix "ihaskell" ihaskell-src {}) (_drv: {
      preCheck = ''
        export HOME=$TMPDIR/home
        export PATH=$PWD/dist/build/ihaskell:$PATH
        export GHC_PACKAGE_PATH=$PWD/dist/package.conf.inplace/:$GHC_PACKAGE_PATH
      '';
      configureFlags = (_drv.configureFlags or []) ++ [ "-f" "-use-hlint" ];
    })).overrideScope (final': prev': {
      hlint = null;
    });
    ghc-parser        = hfinal.callCabal2nix "ghc-parser" ./ghc-parser {};
    # requires zeromq4-haskell !
    ipython-kernel    = hfinal.callCabal2nix "ipython-kernel" ./ipython-kernel {};

    # libsodium = overrideCabal (drv: {
    #   libraryToolDepends = (drv.libraryToolDepends or []) ++ [self.buildHaskellPackages.c2hs];
    # }) super.libsodium;

    zeromq4-haskell = addPkgconfigDepend libsodium.dev hprev.zeromq4-haskell ;

    # libraryPkgconfigDepends = [ zeromq ];
    # aeson = hprev.aeson_2_0_3_0;
  } // displays hfinal

