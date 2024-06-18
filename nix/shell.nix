{ packages
, pkgs
, stdenv
, lib
, mkShell
, release-mode ? false
}:

let
  httpun-wsDrvs = lib.filterAttrs (_: value: lib.isDerivation value) packages;

in
(mkShell {
  inputsFrom = lib.attrValues httpun-wsDrvs;
  buildInputs = with pkgs.ocamlPackages; (if release-mode then
    (with pkgs; [
      cacert
      curl
      dune-release
      git
    ]) else [ ]) ++ [
    merlin
    ocamlformat
    httpun-lwt-unix
    httpun-async
    httpun-eio
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
