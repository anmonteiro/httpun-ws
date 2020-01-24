{ pkgs ? import ./sources.nix { inherit ocamlVersion; }
, ocamlVersion ? "4_09"
, doCheck ? true }:

let
  inherit (pkgs) lib stdenv ocamlPackages;
in

  with ocamlPackages;

  let
    buildWebsocketaf = args: buildDunePackage ({
      version = "0.0.1-dev";
      src = lib.gitignoreSource ./..;
      doCheck = doCheck;
    } // args);

  in rec {
    websocketaf = buildWebsocketaf {
      pname = "websocketaf";
      buildInputs = [ alcotest ];
      propagatedBuildInputs = [ angstrom faraday httpaf base64 ];
    };

  # These two don't have tests
  websocketaf-lwt = buildWebsocketaf {
    pname = "websocketaf-lwt";
    doCheck = false;
    propagatedBuildInputs = [ websocketaf lwt4 digestif ];
  };

  websocketaf-lwt-unix = buildWebsocketaf {
    pname = "websocketaf-lwt-unix";
    doCheck = false;
    propagatedBuildInputs = [
      websocketaf
      websocketaf-lwt
      faraday-lwt-unix
    ];
  };
}
