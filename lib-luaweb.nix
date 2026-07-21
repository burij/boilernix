{ pkgs ? import (fetchTarball
    "https://github.com/NixOS/nixpkgs/tarball/nixos-26.05")
  {} }:

let
  lib = pkgs.lib;
  appName = "lahna";
  appVersion = lib.strings.fileContents ./VERSION;
  appPort = 8152;

  runtimeDeps = with pkgs; [
    pandoc
    wget
  ];

  devDeps = with pkgs; [
    nixpkgs-fmt
    pkgs.luajitPackages.luarocks
  ];

  luaEnv = pkgs.luajit.withPackages (ps: with ps; [ http ]);

  luaLightWings = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/burij/"
      + "lahna/lua-light-wings/refs/tags/"
      + "v.0.4/modules/lua-light-wings.lua";
    sha256 =
      "sha256-Tczj+XNIobX64Cncm0/rbDwMizUDhRmeyjFwrJrDCco=";
  };

  luaCpath =
    "${luaEnv}/lib/lua/${luaEnv.lua.luaversion}/?.so";
  runtimePath = lib.makeSearchPath "bin" runtimeDeps;

  wrapperArgs = [
    "--add-flags"
    "\"$out/lib/$pname/main.lua\""
    "--set" "LUA_PATH"
    "\"$out/lib/$pname/?.lua;$out/lib/$pname/?/init.lua\""
    "--set" "LUA_CPATH" "\"${luaCpath}\""
    "--prefix" "PATH" ":" "\"${runtimePath}\""
  ];

  luajitWrapper = "makeWrapper"
    + " ${luaEnv}/bin/luajit"
    + " $out/bin/$pname"
    + " ${lib.concatStringsSep " " wrapperArgs}";

  package = pkgs.stdenv.mkDerivation {
    pname = appName;
    version = appVersion;
    src = ./.;
    dontCmake = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    buildInputs = [ luaEnv ] ++ runtimeDeps;

    installPhase = ''
      mkdir -p $out/lib/$pname
      find . -mindepth 1 -maxdepth 1 ! -path "./.*" |
        xargs -r -I {} mv {} $out/lib/$pname/

      ${luajitWrapper}
    '';
  };

  shell = pkgs.mkShell {
    buildInputs = runtimeDeps ++ devDeps ++ [ luaEnv ];
    shellHook = ''
      alias run='lua main.lua'
      alias lahna='./result/bin/lahna'
      alias form='nixpkgs-fmt lib.nix'
      mkdir -p modules
      cp ${luaLightWings} ./modules/lua-light-wings.lua
    '';
  };

  container = { config, lib, pkgs, ... }: {
    containers.${appName} = {
      autoStart = true;
      privateNetwork = false;
      privateUsers = "pick";
      hostAddress = "10.0.0.1";
      localAddress = "10.0.0.2";

      bindMounts = {
        "${appName}-public" = {
          hostPath = "/srv/config/${appName}/public";
          mountPoint = "/var/lib/${appName}/public";
          isReadOnly = false;
        };
        "${appName}-conf" = {
          hostPath = "/srv/config/${appName}/conf.lua";
          mountPoint = "/var/lib/${appName}/conf.lua";
          isReadOnly = false;
        };
      };

      config = { config, pkgs, ... }:
        { system.stateVersion = "25.11";
          environment.systemPackages =
            [ package ] ++ runtimeDeps;

          systemd.services."${appName}" = {
            description = "${appName}-daemon";
            after = [ "network.target" ];
            environment = {
              LAHNA_HOST = "0.0.0.0";
              LAHNA_PORT = "${toString appPort}";
          };
          serviceConfig = {
            Type = "simple";
            ExecStart =
              "${package}/bin/${appName}"
              + " /var/lib/${appName}/conf.lua";
            Restart = "always";
            RestartSec = 10;
            StandardOutput = "journal";
            StandardError = "journal";
            WorkingDirectory =
              "${package}/lib/${appName}";
          };
          wantedBy = [ "multi-user.target" ];
        };

        users.users.${appName} = {
          isSystemUser = true;
          group = appName;
        };
        users.groups.${appName} = { };

        networking.firewall.allowedTCPPorts =
          [ appPort ];
      };
    };
  };

in
{ shell = shell; package = package; container = container; }
