{ pkgs ? import
    (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.11")
    { config = { }; overlays = [ ]; }
}:

let
  lib = pkgs.lib;

  appName = "elahna";
  appVersion = lib.strings.fileContents ./VERSION;
  appPort = 8151;

  elixirEnv = with pkgs; [
    elixir
    erlang
  ];

  beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang;

  dependencies = with pkgs; [
    wget
    nixpkgs-fmt
    pandoc
    openssl
  ];

  shell = pkgs.mkShell {
    buildInputs = elixirEnv ++ dependencies;
    shellHook = ''
      cp ./README.md ./priv/content/readme.md
      alias run='mix phx.server'
      alias form='nixpkgs-fmt lib.nix; mix format'
      alias test='PHX_SERVER=true SECRET_KEY_BASE=$(mix phx.gen.secret) \
        CONTENT_PATH=./priv/content ./result/bin/elahna start'
      alias newkey='sudo mkdir -p /var/lib/${appName}/; \
        openssl rand -base64 64 | \
        sudo tee /var/lib/${appName}/phoenix_secret > /dev/null &&
        sudo chmod 600 /var/lib/${appName}/phoenix_secret'
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

  container = { config, lib, pkgs, ... }: {
    containers.${appName} = {
      autoStart = true;
      privateNetwork = false;
      privateUsers = "no";
      hostAddress = "10.0.0.1";
      localAddress = "10.0.0.2";

      bindMounts = {
        "${appName}-content" = {
          hostPath = "/srv/config/${appName}/${appVersion}/priv/content";
          mountPoint = "/var/www/content";
          isReadOnly = false;
        };
        "${appName}-secret" = {
          hostPath = "/var/lib/${appName}/phoenix_secret";
          mountPoint = "/etc/${appName}/secret_key";
          isReadOnly = true;
        };
      };

      config = { config, pkgs, ... }: {
        system.stateVersion = "25.11";

        environment.systemPackages = with pkgs; [
          package
        ];

        systemd.services."${appName}" = {
          description = "${appName} - Phoenix HTMX Server";

          script = ''
            export SECRET_KEY_BASE=$(cat /etc/${appName}/secret_key)
            exec ${package}/bin/${appName} start
          '';

          environment = {
            PHX_SERVER = "true";
            CONTENT_PATH = "/var/www/content";
            PORT = toString appPort;
            PHX_URL_PORT = toString appPort;
            PHX_URL_SCHEME = "http";
            PHX_HOST = "localhost";
          };
          serviceConfig = {
            Restart = "always";
            RestartSec = 10;
            WorkingDirectory = "/var/www";
            User = appName;
            Group = appName;
          };
          wantedBy = [ "multi-user.target" ];
        };

        systemd.tmpfiles.rules = [
          "d /var/www 0755 ${appName} ${appName}"
          "d /var/www/content 0755 ${appName} ${appName}"
        ];

        users.users.${appName} = {
          isSystemUser = true;
          group = appName;
        };
        users.groups.${appName} = { };

        networking.firewall.allowedTCPPorts = [ appPort ];
      };
    };
  };

in
{ shell = shell; package = package; container = container; }
