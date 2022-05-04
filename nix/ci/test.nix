{ ocamlVersion }:

let
  lock = builtins.fromJSON (builtins.readFile ./../../flake.lock);
  src = fetchGit {
    url = with lock.nodes.nixpkgs.locked;"https://github.com/${owner}/${repo}";
    inherit (lock.nodes.nixpkgs.locked) rev;
  };
  pkgs = import "${src}/boot.nix" {
    extraOverlays = [
      (self: super: {
        ocamlPackages = super.ocaml-ng."ocamlPackages_${ocamlVersion}";
      })
    ];
  };

  inherit (pkgs) lib stdenv fetchTarball ocamlPackages;

  websocketafPkgs = pkgs.recurseIntoAttrs (pkgs.callPackage ./.. {
    doCheck = true;
  });
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
      httpaf-lwt-unix
      httpaf-async
    ]);
  doCheck = true;
  checkPhase = ''
    dune build @examples/all --display=progress
  '';
}
