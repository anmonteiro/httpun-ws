{ nix-filter, lib, stdenv, ocamlPackages, doCheck ? true }:

with ocamlPackages;

let
  genSrc = { dirs, files }:
    with nix-filter; filter {
      root = ./..;
      include = [ "dune-project" ] ++ files ++ (builtins.map inDirectory dirs);
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
      doCheck = true;
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

    websocketaf-async = buildWebsocketaf {
      pname = "websocketaf-async";
      src = genSrc {
        dirs = [ "async" ];
        files = [ "websocketaf-async.opam" ];
      };
      doCheck = false;
      propagatedBuildInputs = [
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
      propagatedBuildInputs = [
        conduit-mirage
        websocketaf-lwt
        gluten-mirage
      ];
    };
  };
in
websocketafPackages // (if lib.versionOlder "5.0" ocaml.version then {
  websocketaf-eio = buildWebsocketaf {
    pname = "websocketaf-eio";
    src = genSrc {
      dirs = [ "eio" ];
      files = [ "websocketaf-eio.opam" ];
    };

    propagatedBuildInputs = [
      gluten-eio
      websocketaf
      digestif
    ];
  };

} else { })
