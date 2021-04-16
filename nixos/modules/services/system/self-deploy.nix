{ config, lib, pkgs, ... }:

let
  cfg = config.services.self-deploy;

  workingDirectory = "/var/lib/self-deploy";
  repositoryDirectory = "${workingDirectory}/repo";
  outPath = "${workingDirectory}/system";

  gitWithRepo = "${pkgs.git}/bin/git -C ${repositoryDirectory}";

  renderNixArgs = args:
    let
      toArg = key: value:
        if builtins.isString value
        then " --argstr ${lib.escapeShellArg key} ${lib.escapeShellArg value}"
        else " --arg ${lib.escapeShellArg key} ${lib.escapeShellArg (toString value)}";
    in
      lib.concatStrings (lib.mapAttrsToList toArg args);

in {
  options.services.self-deploy = {
    enable = lib.mkEnableOption "self-deploy";

    nixFile = lib.mkOption {
      type = lib.types.path;

      default = "/default.nix"

      description = ''
      Path to nix file in repository. Leading '/' refers to root of
      git repository.
      '';
    };

    attribute = lib.mkOption {
      type = lib.types.str;

      description = ''
      Attribute of `nixFile` that builds the current system.
      '';
    };

    args = lib.mkOption {
      type = lib.types.attrs;

      default = {};

      description = ''
      Arguments to `nix-build` passed as `--argstr` or `--arg` depending on
      the type.
      '';
    };

    command = lib.mkOption {
      type = lib.types.enum [ "boot" "switch" "dry-activate" "test" ];

      default = "switch";

      description = ''
      The `switch-to-configuration` command used.
      '';
    };

    repository = lib.mkOption {
      type = let
        makeOptionsModule = protocol: options: lib.types.submodule (
          { config, ... }:
          {
            options = options // {
              protocol = lib.mkOption {
                type = lib.types.enum [ protocol ];

                description = ''
                Protocol to be used to clone the git repository.
                '';
              };
            };
          }                                                           
        );

        localOptions = {
          path = lib.mkOption {
            type = lib.types.path;

            description = ''
            Path to local git repository.
            '';
          };
        };
        
        sshOptions = {
          user = lib.mkOption {
            type = lib.types.str;

            example = "git";

            description = ''
            SSH user used when connecting to git host.
            '';
          };
          host = lib.mkOption {
            type = lib.types.str;

            example = "github.com";
            
            description = ''
            SSH host.
            '';
          };
          port = lib.mkOption {
            type = with lib.types; nullOr port;

            default = null;

            description = ''
            SSH port.
            '';
          };
          path = lib.mkOption {
            type = lib.types.path;

            example = "/NixOS/nixpkgs.git";

            description = ''
            Path to git repository on SSH host.
            '';
          };

          sshKeyFile = lib.mkOption {
            type = with lib.types; nullOr path;

            default = null;

            description = ''
            If necessary, the path to the SSH private key used to
            fetch the git repository.
            '';
          };
        };
        
        httpOptions = {
          secure = lib.mkOption {
            type = lib.types.bool;

            default = true;

            description = ''
            Whether to fetch over the HTTPS (HTTP Secure) protocol
            or unsecured HTTP.
            '';
          };
          host = lib.mkOption {
            type = lib.types.str;

            example = "github.com";
            
            description = ''
            HTTP(S) host.
            '';
          };
          port = lib.mkOption {
            type = with lib.types; nullOr port;

            description = ''
            HTTP(S) port.
            '';
          };
          path = lib.mkOption {
            type = lib.types.path;

            example = "/NixOS/nixpkgs.git";

            description = ''
            Path to git repository on HTTP(S) host.
            '';
          };
        };
        
        ftpOptions = {
          secure = lib.mkOption {
            type = lib.types.bool;

            default = false;

            description = ''
            Whether to fetch over the FTPS (FTP Secure) protocol
            or unsecured FTP.
            '';
          };
          host = lib.mkOption {
            type = lib.types.str;
            
            description = ''
            FTP(S) host.
            '';
          };
          port = lib.mkOption {
            type = lib.types.port;

            description = ''
            FTP(S) port.
            '';
          };
          path = lib.mkOption {
            type = lib.types.path;

            description = ''
            Path to git repository on FTP(S) host.
            '';
          };
        };
        
        gitOptions = {
          host = lib.mkOption {
            type = lib.types.str;
            
            description = ''
            Git protocol host.
            '';
          };
          port = lib.mkOption {
            type = lib.types.port;

            description = ''
            Git protocol port.
            '';
          };
          path = lib.mkOption {
            type = lib.types.path;

            description = ''
            Path to git repository on git host.
            '';
          };
        };
      in lib.types.oneOf [
        (makeOptionsModule "local" localOptions)
        (makeOptionsModule "ssh"     sshOptions)
        (makeOptionsModule "http"   httpOptions)
        (makeOPtionsModule "ftp"     ftpOptions)
        (makeOptionsModule "git"     gitOptions)
      ];
    };

    branch = lib.mkOption {
      type = lib.types.str;

      default = "origin/master";

      description = ''
      Branch to track
      
      Carefully note that this service does not push or pull branches, so
      if you want to track a remote branch you want to prefix your branch 
      with `origin/` (e.g. `origin/master`).
      
      You can also specify a revision or tag, too, if you want to pin this
      machine to a specific commit.
      '';
    };

    startAt = lib.mkOption {
      type = with lib.types; either str (listOf str);

      default = "hourly";

      description = ''
      The schedule on which to run the `self-deploy` service. Format
      specified by `systemd.time 7`.

      This value can also be a list of `systemd.time 7` formatted
      strings, in which case the service will be started on multiple
      schedules.
      '';
    };
  };

  config = config.mkIf cfg.enable {
    systemd.services.self-deploy = {
      wantedBy = [ "multi-user.target" ];

      requires = config.mkIf (cfg.repository.protocol != "local") [ "network-online.target" ];

      environment.GIT_SSH_COMMAND =
        config.mkIf (cfg.repository.protocol == "ssh" && !(isNull cfg.repository.sshKeyFile)
          "${pkgs.openssh}/bin/ssh -i ${lib.escapeShellArg cfg.repository.sshKeyFile}";

      serviceConfig.X-RestartIfChanged = false;

      script = let
        buildGitSuffix = repository: with repository;
          "${host}${lib.optionalString (!(isNull port)) ":${toString port}"}${path}";

        buildGitUrl = repository: with repository; {
          "local" = "file://${path}";
          "ssh" = "ssh://${user}@${buildGitSuffix repository}";
          "http" = "http${lib.optionalString secure "s"}://${buildGitSuffix repository}";
          "ftp" = "ftp${lib.optionalString secure "s"}://${buildGitSuffix repository}";
          "git" = "git://${buildGitSuffix repository}";
        }."${protocol}";
      in ''
      if [ ! -e ${workingDirectory} ]; then
        ${pkgs.coreutils}/bin/mkdir --parents ${workingDirectory}
      fi

      if [ ! -e ${repositoryDirectory} ]; then
        ${pkgs.git}/bin/git clone ${lib.cli.toGNUCommandLineShell {} {
          local = (cfg.repository.protocol == "local");
        }} ${lib.escapeShellArg (buildGitUrl cfg.repository)} ${repositoryDirectory}
      fi

      ${gitWithRepo} fetch ${lib.escapeShellArg cfg.branch}

      ${gitWithRepo} checkout FETCH_HEAD

      ${pkgs.nix}/bin/nix-build${renderNixArgs cfg.args} ${lib.cli.toGNUCommandLineShell {} {
        attr = cfg.attribute;
        out-link = outPath;                       
      }} ${lib.escapeShellArg "${repositoryDirectory}${nixFile}"}

      ${lib.optionalString (cfg.command != "test")
        "${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --set ${outPath}"}

      ${pkgs.coreutils}/bin/rm ${outPath}

      ${gitWithRepo} gc --prune=all

      ${outPath}/bin/switch-to-configuration switch

      ${lib.optionalString (cfg.command == "boot") "${pkgs.systemd}/bin/systemctl reboot"}
      '';
    };
  };
}
