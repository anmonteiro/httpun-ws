{ pkgs ? import ./sources.nix { inherit ocamlVersion; }
, ocamlVersion ? "4_10"
, doCheck ? true }:

let
  inherit (pkgs) lib stdenv ocamlPackages;
in

  with ocamlPackages;

  let
    buildWebsocketaf = args: buildDunePackage ({
      version = "0.0.1-dev";
      useDune2 = true;
      src = lib.gitignoreSource ./..;
      doCheck = doCheck;
    } // args);
    websocketafPackages = rec {
      websocketaf = buildWebsocketaf {
        pname = "websocketaf";
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
        doCheck = false;
        propagatedBuildInputs = [ gluten-lwt websocketaf lwt4 digestif ];
      };

      websocketaf-lwt-unix = buildWebsocketaf {
        pname = "websocketaf-lwt-unix";
        doCheck = false;
        propagatedBuildInputs = [
          websocketaf
          websocketaf-lwt
          faraday-lwt-unix
          gluten-lwt-unix
        ];
      };
    };

  in websocketafPackages // (if (lib.versionOlder "4.08" ocaml.version) then {
    websocketaf-mirage = buildWebsocketaf {
      pname = "websocketaf-mirage";
      doCheck = false;
      propagatedBuildInputs = with websocketafPackages; [
        conduit-mirage
        websocketaf-lwt
        gluten-mirage
      ];
    };
  } else {})
