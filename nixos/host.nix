{ guest, microvm }:
{ config, ... }:
let
  cfg = config.qwen-code-dev;
in
{
  imports = [
    microvm.nixosModules.host
    ./options.nix
  ];

  microvm.vms.qwen-code-dev.config = {
    imports = [ guest ];
    qwen-code-dev = cfg;
  };

  networking.nftables = {
    enable = true;
    tables.qwen-code-dev = {
      family = "inet";
      content = ''
        chain output {
          type filter hook output priority filter; policy accept;
          meta skuid != "microvm" accept
          ct state established,related accept
          fib daddr type != local accept
          ip daddr 127.0.0.1 tcp dport ${toString cfg.llmPort} accept
          meta l4proto { tcp, udp } th dport 53 accept
          reject
        }
      '';
    };
    preCheckRuleset = ''
      sed -i 's/skuid != "microvm"/skuid != "nobody"/' ruleset.conf
    '';
  };

  systemd.services."microvm@" = {
    requires = [ "nftables.service" ];
    after = [ "nftables.service" ];
  };
}
