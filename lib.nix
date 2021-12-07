{
  nixpkgs,
  staticExecutable ? false
}:
{
  ihaskell-src = nixpkgs.nix-gitignore.gitignoreSource
    [ "**/*.ipynb" "**/*.nix" "**/*.yaml" "**/*.yml" "**/\.*" "/Dockerfile" "/README.md" "/cabal.project" "/images" "/notebooks" "/requirements.txt" ]
    ./.;
  displays = self: builtins.listToAttrs (
    map
      (display: { name = "ihaskell-${display}"; value = self.callCabal2nix display "${ihaskell-src}/ihaskell-display/ihaskell-${display}" {}; })
      [ "aeson" "blaze" "charts" "diagrams" "gnuplot" "graphviz" "hatex" "juicypixels" "magic" "plot" "rlangqq" "static-canvas" "widgets" ]);

  ihaskellExe = if staticExecutable
    then nixpkgs.haskell.lib.justStaticExecutables haskellPackages.ihaskell
    else nixpkgs.haskell.lib.enableSharedExecutables haskellPackages.ihaskell;
  ihaskellEnv = haskellPackages.ghcWithPackages packages;

}
