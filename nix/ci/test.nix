{ ocamlVersion }:

let
  pkgs = import ../sources.nix { inherit ocamlVersion; };
  inherit (pkgs) lib stdenv fetchTarball ocamlPackages;

  websocketafPkgs = import ./.. { inherit ocamlVersion; };
in
  pkgs.recurseIntoAttrs websocketafPkgs
