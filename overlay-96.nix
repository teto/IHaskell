{ ihaskell-src, inputs, libsodium, fetchpatch, haskell }:
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

    # overrideSrc
    # hlint = doJailbreak hprev.hlint;
    hlint = hfinal.callCabal2nix "hlint" "${inputs.hlint}" { };

    foundation = hprev.foundation.overrideAttrs(oa: {
      patches = [];
    });

    ghc-parser        = hfinal.callCabal2nix "ghc-parser" ./ghc-parser {};
    # requires zeromq4-haskell !
    ipython-kernel    = hfinal.callCabal2nix "ipython-kernel" ./ipython-kernel {};

    # libsodium = overrideCabal (drv: {
    #   libraryToolDepends = (drv.libraryToolDepends or []) ++ [self.buildHaskellPackages.c2hs];
    # }) super.libsodium;
    ghc-syntax-highlighter = 
      # let
      # src = nixpkgs.fetchFromGitHub {
      #   owner = "mrkkrp";
      #   repo = "ghc-syntax-highlighter";
      #   rev = "71ff751eaa6034d4aef254d6bc5a8be4f6595344";
      #   sha256 = "14yahxi4pnjbvcd9r843kn7b36jsjaixd99jswsrh9n8xd59c2f1";
      # };
      # in
        hfinal.callCabal2nix "ghc-syntax-highlighter" inputs.ghc-syntax-highlighter {};

    zeromq4-haskell = addPkgconfigDepend hprev.zeromq4-haskell libsodium;
    here = appendPatch (doJailbreak hprev.here) (fetchpatch {
      url = "https://github.com/tmhedberg/here/commit/3c648cdef8998383d9b63af4984ccb12c7729644.patch";
      sha256 = "sha256-Cvedt/UpH0tWrXVHCNFZlt0dr443IAkCOJdSjuPLIf8=";
    });
    shelly = doJailbreak hprev.shelly;
    hourglass = dontCheck hprev.hourglass;

    # libraryPkgconfigDepends = [ zeromq ];
    # aeson = hprev.aeson_2_0_3_0;
  } // displays hfinal


