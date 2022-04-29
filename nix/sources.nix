{ ocamlVersion ? "4_12" }:

let
  overlays =
    builtins.fetchTarball
      https://github.com/anmonteiro/nix-overlays/archive/af932978.tar.gz;
  nixpkgs = import "${overlays}/sources.nix";
in
import nixpkgs {
  overlays = [
    (import overlays)
    (self: super: {
      ocamlPackages = super.ocaml-ng."ocamlPackages_${ocamlVersion}";
    })
  ];
}
