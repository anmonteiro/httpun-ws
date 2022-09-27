{ ocamlVersion }:

let
  lock = builtins.fromJSON (builtins.readFile ./../../flake.lock);
  src = fetchGit {
    url = with lock.nodes.nixpkgs.locked;"https://github.com/${owner}/${repo}";
    inherit (lock.nodes.nixpkgs.locked) rev;
    allRefs = true;
  };
  nix-filter-src = fetchGit {
    url = with lock.nodes.nix-filter.locked; "https://github.com/${owner}/${repo}";
    inherit (lock.nodes.nix-filter.locked) rev;
    # inherit (lock.nodes.nixpkgs.original) ref;
    allRefs = true;
  };

  nix-filter = import "${nix-filter-src}";

  pkgs = import "${src}" {
    extraOverlays = [
      (self: super: {
        ocamlPackages = super.ocaml-ng."ocamlPackages_${ocamlVersion}";
      })
    ];
  };

  inherit (pkgs) lib stdenv fetchTarball ocamlPackages;

  websocketafPkgs = pkgs.callPackage ./.. {
    inherit nix-filter;
    doCheck = true;
  };
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
    ${ if !(lib.hasPrefix "5_" ocamlVersion) then "rm -rf ./examples/eio" else "" }
    dune build @examples/all --display=progress
  '';
}
