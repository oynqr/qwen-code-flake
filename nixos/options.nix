{ lib, ... }:
{
  options.qwen-code-dev = {
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages installed in the microvm.";
    };

    vcpu = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Number of virtual CPUs of the microvm.";
    };

    memory = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = "Memory of the microvm in MiB.";
    };

    diskSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16384;
      description = "Size of the persistent /home volume in MiB.";
    };

    storeSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16384;
      description = "Size of the persistent writable /nix/store overlay volume in MiB.";
    };

    llmHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Host of the OpenAI-compatible LLM server. "127.0.0.1" or "localhost" means the NixOS host's
        loopback interface, which the microvm reaches as 10.0.2.2 on llmPort only. Any other host
        is reached directly, including machines on the host's local network or VPN. If it is an IP
        address of the NixOS host itself, such as its LAN or VPN address, llmPort on that address
        is the only host port the microvm can reach; use an IP address rather than a hostname for
        that case.
      '';
    };

    llmPort = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "TCP port of the LLM server. For an LLM on the NixOS host, this is the only host port the microvm can reach.";
    };

    llmModel = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = ''
        Name of the model on the LLM server. Auto mode might not work correctly on models
        that do not start with "qwen".
      '';
    };

    sshAuthorizedKeys = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.singleLineStr;
      description = "SSH public keys authorized to log in as the dev user.";
    };
  };
}
