{
  description = "A template for machine learning with flax";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    let out = system:
      let
        useCuda = system == "x86_64-linux";
        pkgs = import nixpkgs {
          inherit system;
          config.cudaSupport = useCuda;
          config.allowUnfree = true;
        };
        inherit (pkgs) poetry2nix lib stdenv fetchurl;
        inherit (pkgs.cudaPackages) cudatoolkit;
        inherit (pkgs.linuxPackages) nvidia_x11;
        python = pkgs.python39;
        pythonEnv = poetry2nix.mkPoetryEnv {
          inherit python;
          projectDir = ./.;
          preferWheels = true;
          overrides = poetry2nix.overrides.withDefaults (pyfinal: pyprev: rec {
            # Use tensorflow-gpu on linux
            tensorflow-gpu =
              if stdenv.isLinux then
              # Override the nixpkgs bin version instead of
              # poetry2nix version so that rpath is set correctly.
                pyprev.tensorflow-bin.overridePythonAttrs
                  (old: {
                    inherit (pyprev.tensorflow-gpu) src version;
                  }) else null;
            # Use tensorflow-macos on macOS
            tensorflow-macos =
              if stdenv.isDarwin then
                pyprev.tensorflow-macos.overridePythonAttrs
                  (old: {
                    buildInputs = (old.buildInputs or [ ]) ++ [ pyfinal.wheel ];
                    postInstall = ''
                      rm $out/bin/tensorboard
                    '';
                  }) else null;
            astunparse = pyprev.astunparse.overridePythonAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ pyfinal.wheel ];
            });
            # Use cuda-enabled jaxlib as required
            jaxlib =
              if useCuda then
              # Override the nixpkgs bin version instead of
              # poetry2nix version so that rpath is set correctly.
                pyprev.jaxlib-bin.overridePythonAttrs
                  (old: {
                    inherit (old) pname version;
                    src = fetchurl {
                      url = "https://storage.googleapis.com/jax-releases/cuda11/jaxlib-0.3.10+cuda11.cudnn82-cp39-none-manylinux2014_x86_64.whl";
                      sha256 = "sha256-ccmqJ++93I8eKCm3/GUhvJC9NTpBKb7HBp/TGoqdWT4=";
                    };
                  }) else pyprev.jaxlib;
          });
        };
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = [
            pythonEnv
          ] ++ lib.optionals useCuda [
            nvidia_x11
            cudatoolkit
          ];
          shellHook = ''
            export pythonfaulthandler=1
            export pythonbreakpoint=ipdb.set_trace
            set -o allexport
            source .env
            set +o allexport
          '' + pkgs.lib.optionalString useCuda ''
            export CUDA_PATH=${cudatoolkit.lib}
            export LD_LIBRARY_PATH=${cudatoolkit.lib}/lib:${nvidia_x11}/lib
            export EXTRA_LDFLAGS="-l/lib -l${nvidia_x11}/lib"
            export EXTRA_CCFLAGS="-i/usr/include"
          '';
        };
      }; in with utils.lib; eachSystem defaultSystems out;

}
