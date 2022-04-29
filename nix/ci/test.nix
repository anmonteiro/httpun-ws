{ ocamlVersion }:

let
  pkgs = import ../sources.nix { inherit ocamlVersion; };
  inherit (pkgs) lib stdenv fetchTarball ocamlPackages;

  websocketafPkgs = pkgs.recurseIntoAttrs (import ./.. { inherit ocamlVersion; doCheck = true; });
  websocketafDrvs = lib.filterAttrs (_: value: lib.isDerivation value) websocketafPkgs;

in

stdenv.mkDerivation {
  name = "websocketaf-examples";
  src = ./../..;
  dontBuild = true;
  installPhase = ''
    touch $out
  '';
  buildInputs = (lib.attrValues websocketafDrvs) ++
    (with ocamlPackages; [
      ocaml
      dune
      findlib
      alcotest
      httpaf-lwt-unix
      httpaf-async
    ]);
  doCheck = true;
  checkPhase = ''
    dune runtest
    dune build @examples/all --display=progress
  '';
}
