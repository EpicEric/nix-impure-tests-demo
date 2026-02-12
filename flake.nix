{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      rust-overlay,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      eachSystem =
        f:
        (builtins.foldl' (
          acc: system:
          let
            fSystem = f system;
          in
          builtins.foldl' (
            acc': attr:
            acc'
            // {
              ${attr} = (acc'.${attr} or { }) // fSystem.${attr};
            }
          ) acc (builtins.attrNames fSystem)
        ) { } systems);
    in
    eachSystem (
      system:
      let
        rustChannel = "stable";
        rustVersion = "latest";

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        inherit (pkgs) lib;

        craneLib = (crane.mkLib pkgs).overrideToolchain (
          p: p.rust-bin.${rustChannel}.${rustVersion}.default
        );

        src = craneLib.cleanCargoSource ./.;

        commonArgs = {
          inherit src;
          strictDeps = true;
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        mydns = craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;
            doCheck = false;
            meta.mainProgram = "mydns";
          }
        );
      in
      {
        packages.${system} = {
          inherit mydns;
          default = self.packages.${system}.mydns;
        };

        apps.${system}.default = {
          type = "app";
          program = lib.getExe mydns;
          meta = {
            mainProgram = "mydns";
            description = "My simple DNS CLI";
          };
        };

        checks.${system} = {
          # naive-tests = craneLib.cargoNextest (
          #   commonArgs
          #   // {
          #     inherit cargoArtifacts;
          #   }
          # );

          mydns-tests =
            let
              nextest-archive = craneLib.mkCargoDerivation (
                commonArgs
                // {
                  inherit cargoArtifacts;
                  doCheck = false;
                  pname = "mydns-nextest-archive";
                  nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [ pkgs.cargo-nextest ];
                  buildPhaseCargoCommand = ''
                    cargo nextest archive --archive-format tar-zst --archive-file archive.tar.zst
                  '';
                  installPhaseCommand = ''
                    mkdir -p $out
                    cp archive.tar.zst $out
                  '';
                }
              );
            in
            pkgs.testers.runNixOSTest {
              name = "mydns-nextest";
              nodes = {
                machine =
                  { ... }:
                  {
                    virtualisation.diskSize = 4096;
                    networking.hosts = {
                      "52.0.56.137" = [ "52-0-56-137.nip.io" ];
                    };
                    systemd.services.cargo-nextest = {
                      description = "Integration Tests for mydns";
                      wantedBy = [ "multi-user.target" ];
                      after = [ "network-online.target" ];
                      wants = [ "network-online.target" ];
                      path = [
                        pkgs.cargo
                        pkgs.cargo-nextest
                      ];
                      script = ''
                        cp -r ${src}/* .
                        cargo nextest run \
                          --archive-file ${nextest-archive}/archive.tar.zst \
                          --workspace-remap .
                      '';
                      serviceConfig = {
                        StateDirectory = "cargo-nextest";
                        StateDirectoryMode = "0750";
                        WorkingDirectory = "/var/lib/cargo-nextest";
                        Type = "oneshot";
                        RemainAfterExit = "yes";
                        Restart = "no";
                      };
                    };
                  };
              };
              testScript = ''
                machine.start()
                machine.wait_for_unit("cargo-nextest.service")
              '';
            };
        };

        devShells.${system}.default = craneLib.devShell {
          checks = self.checks.${system};
          packages = [ pkgs.cargo-nextest ];
        };
      }
    );
}
