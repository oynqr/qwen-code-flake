{ guest, microvm }:
{ config, ... }:
{
  imports = [
    microvm.nixosModules.host
    ./options.nix
  ];

  microvm.vms.qwen-code-dev.config = {
    imports = [ guest ];
    inherit (config) qwen-code-dev;
  };
}
