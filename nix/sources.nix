{ ocamlVersion ? "4_12" }:

let
  overlays =
    builtins.fetchTarball
      https://github.com/anmonteiro/nix-overlays/archive/37f6a73908.tar.gz;
in
import "${overlays}/boot.nix" {
  extraOverlays = [
    (self: super: {
      ocamlPackages = super.ocaml-ng."ocamlPackages_${ocamlVersion}";
    })
  ];
}
