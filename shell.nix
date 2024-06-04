{ packages, pkgs, stdenv, lib, mkShell }:

let
  httpun-wsDrvs = lib.filterAttrs (_: value: lib.isDerivation value) packages;

in
(mkShell {
  inputsFrom = lib.attrValues httpun-wsDrvs;
  buildInputs = with pkgs.ocamlPackages; [
    merlin
    pkgs.ocamlformat
  ];
}).overrideAttrs (o: {
  propagatedBuildInputs = lib.filter
    (drv:
      # we wanna filter our own packages so we don't build them when entering
      # the shell. They always have `pname`
      !(lib.hasAttr "pname" drv) ||
      drv.pname == null ||
      !(lib.any (name: name == drv.pname) (lib.attrNames httpun-wsDrvs)))
    o.propagatedBuildInputs;
})
