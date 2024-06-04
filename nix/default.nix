{ nix-filter, lib, stdenv, ocamlPackages, doCheck ? true }:

with ocamlPackages;

let
  genSrc = { dirs, files }:
    with nix-filter; filter {
      root = ./..;
      include = [ "dune-project" ] ++ files ++ (builtins.map inDirectory dirs);
    };
  buildHttpun-ws = args: buildDunePackage ({
    version = "0.0.1-dev";
    useDune2 = true;
  } // args);

  httpun-wsPackages = rec {
    httpun-ws = buildHttpun-ws {
      pname = "httpun-ws";
      src = genSrc {
        dirs = [ "lib" "lib_test" ];
        files = [ "httpun-ws.opam" ];
      };
      buildInputs = [ alcotest ];
      doCheck = true;
      propagatedBuildInputs = [
        angstrom
        faraday
        gluten
        httpun
        base64
      ];
    };

    # These two don't have tests
    httpun-ws-lwt = buildHttpun-ws {
      pname = "httpun-ws-lwt";
      src = genSrc {
        dirs = [ "lwt" ];
        files = [ "httpun-ws-lwt.opam" ];
      };
      doCheck = false;
      propagatedBuildInputs = [ gluten-lwt httpun-ws lwt digestif ];
    };

    httpun-ws-lwt-unix = buildHttpun-ws {
      pname = "httpun-ws-lwt-unix";
      src = genSrc {
        dirs = [ "lwt-unix" ];
        files = [ "httpun-ws-lwt-unix.opam" ];
      };
      doCheck = false;
      propagatedBuildInputs = [
        httpun-ws
        httpun-ws-lwt
        faraday-lwt-unix
        gluten-lwt-unix
      ];
    };

    httpun-ws-async = buildHttpun-ws {
      pname = "httpun-ws-async";
      src = genSrc {
        dirs = [ "async" ];
        files = [ "httpun-ws-async.opam" ];
      };
      doCheck = false;
      propagatedBuildInputs = [
        httpun-ws
        async
        digestif
        faraday-async
        gluten-async
      ];
    };

    httpun-ws-mirage = buildHttpun-ws {
      pname = "httpun-ws-mirage";
      src = genSrc {
        dirs = [ "mirage" ];
        files = [ "httpun-ws-mirage.opam" ];
      };
      doCheck = false;
      propagatedBuildInputs = [
        conduit-mirage
        httpun-ws-lwt
        gluten-mirage
      ];
    };
  };
in
httpun-wsPackages // (if lib.versionOlder "5.0" ocaml.version then {
  httpun-ws-eio = buildHttpun-ws {
    pname = "httpun-ws-eio";
    src = genSrc {
      dirs = [ "eio" ];
      files = [ "httpun-ws-eio.opam" ];
    };

    propagatedBuildInputs = [
      gluten-eio
      httpun-wsPackages.httpun-ws
      digestif
    ];
  };

} else { })
