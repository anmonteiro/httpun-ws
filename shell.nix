let
  pkgs = import ./nix/sources.nix { };
  inherit (pkgs) stdenv lib;
  websocketafPkgs = pkgs.recurseIntoAttrs (import ./nix { inherit pkgs; });
  websocketafDrvs = lib.filterAttrs (_: value: lib.isDerivation value) websocketafPkgs;

in
(pkgs.mkShell {
  inputsFrom = lib.attrValues websocketafDrvs;
  buildInputs = with pkgs.ocamlPackages; [ merlin pkgs.ocamlformat ];
}).overrideAttrs (o: {
  propagatedBuildInputs = lib.filter
    (drv:
      # we wanna filter our own packages so we don't build them when entering
      # the shell. They always have `pname`
      !(lib.hasAttr "pname" drv) ||
      drv.pname == null ||
      !(lib.any (name: name == drv.pname) (lib.attrNames websocketafDrvs)))
    o.propagatedBuildInputs;
})

