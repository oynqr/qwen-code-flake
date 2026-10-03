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

    sshAuthorizedKeys = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.singleLineStr;
      description = "SSH public keys authorized to log in as the dev user.";
    };
  };
}
