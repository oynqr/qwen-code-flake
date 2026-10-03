{ self }:
{
  config,
  pkgs,
  ...
}:
let
  cfg = config.qwen-code-dev;
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
      volumes = [
        {
          image = "qwen-code-dev-home.img";
          mountPoint = "/home";
          size = cfg.diskSize;
        }
      ];
    };

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

    environment.variables.OPENAI_BASE_URL = "http://10.0.2.2:${toString cfg.llmPort}/v1";

    environment.systemPackages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.qwen-code
      pkgs.git
    ]
    ++ cfg.packages;

    system.stateVersion = "26.11";
  };
}
