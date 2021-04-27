{ config, lib, pkgs, ... }:

let
  cfg = config.services.self-deploy;

  workingDirectory = "/var/lib/self-deploy";
  repositoryDirectory = "${workingDirectory}/repo";
  outPath = "${workingDirectory}/system";

  gitWithRepo = "git -C ${repositoryDirectory}";

  renderNixArgs = args:
    let
      toArg = key: value:
        if builtins.isString value
        then " --argstr ${lib.escapeShellArg key} ${lib.escapeShellArg value}"
        else " --arg ${lib.escapeShellArg key} ${lib.escapeShellArg (toString value)}";
    in
      lib.concatStrings (lib.mapAttrsToList toArg args);

  isPathType = x: lib.strings.isCoercibleToString x && builtins.substring 0 1 (toString x) == "/";

in {
  options.services.self-deploy = {
    enable = lib.mkEnableOption "self-deploy";

    nixFile = lib.mkOption {
      type = lib.types.path;

      default = "/default.nix";

      description = ''
      Path to nix file in repository. Leading '/' refers to root of
      git repository.
      '';
    };

    nixAttribute = lib.mkOption {
      type = lib.types.str;

      description = ''
      Attribute of `nixFile` that builds the current system.
      '';
    };

    nixArgs = lib.mkOption {
      type = lib.types.attrs;

      default = {};

      description = ''
      Arguments to `nix-build` passed as `--argstr` or `--arg` depending on
      the type.
      '';
    };

    switchCommand = lib.mkOption {
      type = lib.types.enum [ "boot" "switch" "dry-activate" "test" ];

      default = "switch";

      description = ''
      The `switch-to-configuration` subcommand used.
      '';
    };

    repository = lib.mkOption {
      type = with lib.types; oneOf [ path str ];

      description = ''
      The repository to fetch from. Must be properly formatted for git.

      If this value is set to a path (must begin with `/`) then the
      resulting service won't require the network to be up to run.

      If the repository will be fetched over SSH, you should add an
      entry to `programs.ssh.knownHosts` for it.
      '';
    };

    sshKeyFile = lib.mkOption {
      type = with lib.types; nullOr path;

      default = null;

      description = ''
      Path to SSH private key used to fetch private repositories over
      SSH.
      '';
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

  config = lib.mkIf cfg.enable {
    systemd.services.self-deploy = {
      wantedBy = [ "multi-user.target" ];

      requires = lib.mkIf (!(isPathType cfg.repository)) [ "network-online.target" ];
      
      environment.GIT_SSH_COMMAND = lib.mkIf (!(isNull cfg.sshKeyFile))
        "${pkgs.openssh}/bin/ssh -i ${lib.escapeShellArg cfg.sshKeyFile}";
                     
      serviceConfig.X-RestartIfChanged = false;

      path = with pkgs; [
        git nix systemd
      ];

      script = ''
      if [ ! -e ${workingDirectory} ]; then
        mkdir --parents ${workingDirectory}
      fi

      if [ ! -e ${repositoryDirectory} ]; then
        git clone ${lib.cli.toGNUCommandLineShell {} {
          inherit (cfg) local;
        }} ${lib.escapeShellArg cfg.repository} ${repositoryDirectory}
      fi

      ${gitWithRepo} fetch ${lib.escapeShellArg cfg.branch}

      ${gitWithRepo} checkout FETCH_HEAD

      nix-build${renderNixArgs cfg.nixArgs} ${lib.cli.toGNUCommandLineShell {} {
        attr = cfg.nixAttribute;
        out-link = outPath;                       
      }} ${lib.escapeShellArg "${repositoryDirectory}${cfg.nixFile}"}

      ${lib.optionalString (cfg.nixCommand != "test")
        "nix-env --profile /nix/var/nix/profiles/system --set ${outPath}"}

      rm ${outPath}

      ${gitWithRepo} gc --prune=all

      ${outPath}/bin/switch-to-configuration ${cfg.nixCommand}

      ${lib.optionalString (cfg.nixCommand == "boot") "systemctl reboot"}
      '';
    };
  };
}
