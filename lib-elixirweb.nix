{ pkgs ? import
    (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.11")
    { config = { }; overlays = [ ]; }
}:

let

  appName = "ifc_editor";
  appVersion = "0.2.8";

  elixirEnv = with pkgs; [
    elixir
    erlang
  ];

  beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang;

  dependencies = with pkgs; [
    wget
    git
    opencode
    nixpkgs-fmt
    jujutsu
    python3
    python3Packages.ifcopenshell
    python3Packages.pandas
    python3Packages.openpyxl
  ];

  shell = pkgs.mkShell {
    buildInputs = elixirEnv ++ dependencies;
    shellHook = ''
      alias run='mix run --no-halt'
      alias repl='iex -S mix'
      alias make='nix-build -A package'
      alias form='nixpkgs-fmt default.nix; mix format'
      alias test='IFC_DATA_PATH=/home/burij/Temp ./result/bin/ifc_editor start'
    '';
  };

  package = beamPackages.mixRelease {
    pname = appName;
    version = appVersion;
    src = ./.;
    removeCookie = false;
    env = {
      HOME = "/tmp";
    };
  };


in
{ shell = shell; package = package; }
