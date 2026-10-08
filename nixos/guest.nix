{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.qwen-code-dev;
  llm = import ./llm.nix { inherit lib cfg; };
in
{
  imports = [ ./options.nix ];

  config = {
    networking.hostName = "qwen-code-dev";

    microvm = {
      hypervisor = "qemu";
      socket = "qwen-code-dev.socket";
      inherit (cfg) vcpu;
      mem = cfg.memory;
      interfaces = [
        {
          type = "user";
          id = "qemu";
          mac = "02:00:00:00:00:01";
        }
      ];
      forwardPorts = [
        {
          from = "host";
          host.address = "127.0.0.1";
          host.port = 2222;
          guest.port = 22;
        }
      ];
      shares = [
        {
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          readOnly = true;
        }
      ];
      writableStoreOverlay = "/nix/.rw-store";
      volumes = [
        {
          image = "qwen-code-dev-home.img";
          mountPoint = "/home";
          size = cfg.diskSize;
        }
        {
          image = "qwen-code-dev-nix-store.img";
          mountPoint = config.microvm.writableStoreOverlay;
          size = cfg.storeSize;
        }
        {
          image = "qwen-code-dev-nix-var.img";
          mountPoint = "/nix/var";
          size = 1024;
        }
      ];
    };

    fileSystems."/nix/var".neededForBoot = true;

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    users.users.dev = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.sshAuthorizedKeys;
    };

    systemd.tmpfiles.settings.qwen-code-dev.${config.users.users.dev.home}.d = {
      user = "dev";
      inherit (config.users.users.dev) group;
      mode = "0700";
    };

    security.sudo.wheelNeedsPassword = false;

    warnings = lib.optionals (!lib.hasPrefix "qwen" (lib.toLower cfg.llmModel)) [
      ''
        qwen-code-dev.llmModel = "${cfg.llmModel}" does not start with "qwen".
        Auto mode might not work correctly on models that do not start with "qwen".
      ''
    ];

    environment.variables = {
      OPENAI_BASE_URL = llm.baseUrl;
      OPENAI_MODEL = cfg.llmModel;
      OPENAI_API_KEY = "none";
    };

    environment.etc."qwen-code/settings.json".text = builtins.toJSON {
      model.generationConfig.contextWindowSize = cfg.llmContextWindow;
    };

    environment.systemPackages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.qwen-code
      pkgs.git
    ]
    ++ cfg.packages;

    system.stateVersion = "26.11";
  };
}
