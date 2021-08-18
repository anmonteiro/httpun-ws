{ pkgs ? import ./sources.nix { inherit ocamlVersion; }
, ocamlVersion ? "4_12"
, doCheck ? true
}:

let
  inherit (pkgs) lib stdenv ocamlPackages;
in

with ocamlPackages;

let
  genSrc = { dirs, files }: lib.filterGitSource {
    src = ./..;
    inherit dirs;
    files = files ++ [ "dune-project" ];
  };
  buildWebsocketaf = args: buildDunePackage ({
    version = "0.0.1-dev";
    useDune2 = true;
  } // args);
  websocketafPackages = rec {
    websocketaf = buildWebsocketaf {
      pname = "websocketaf";
      src = genSrc {
        dirs = [ "lib" "lib_test" ];
        files = [ "websocketaf.opam" ];
      };
      buildInputs = [ alcotest ];
      propagatedBuildInputs = [
        angstrom
        faraday
        gluten
        httpaf
        base64
      ];
    };

    # These two don't have tests
    websocketaf-lwt = buildWebsocketaf {
      pname = "websocketaf-lwt";
      src = genSrc {
        dirs = [ "lwt" ];
        files = [ "websocketaf-lwt.opam" ];
      };
      doCheck = false;
      propagatedBuildInputs = [ gluten-lwt websocketaf lwt digestif ];
    };

    websocketaf-lwt-unix = buildWebsocketaf {
      pname = "websocketaf-lwt-unix";
      src = genSrc {
        dirs = [ "lwt-unix" ];
        files = [ "websocketaf-lwt-unix.opam" ];
      };
      doCheck = false;
      propagatedBuildInputs = [
        websocketaf
        websocketaf-lwt
        faraday-lwt-unix
        gluten-lwt-unix
      ];
    };
  };

in
websocketafPackages // (if (lib.versionOlder "4.08" ocaml.version) then {
  websocketaf-async = buildWebsocketaf {
    pname = "websocketaf-async";
    src = genSrc {
      dirs = [ "async" ];
      files = [ "websocketaf-async.opam" ];
    };
    doCheck = false;
    propagatedBuildInputs = with websocketafPackages; [
      websocketaf
      async
      digestif
      faraday-async
      gluten-async
    ];
  };

  websocketaf-mirage = buildWebsocketaf {
    pname = "websocketaf-mirage";
    src = genSrc {
      dirs = [ "mirage" ];
      files = [ "websocketaf-mirage.opam" ];
    };
    doCheck = false;
    propagatedBuildInputs = with websocketafPackages; [
      conduit-mirage
      websocketaf-lwt
      gluten-mirage
    ];
  };
} else { })
