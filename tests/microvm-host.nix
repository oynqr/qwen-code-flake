{ self, pkgs }:
let
  sshKeys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  fakeLlm = ./no-internet/fake_openai.py;
  storeTest = pkgs.writeText "store-test.nix" ''
    derivation {
      name = "qwen-code-dev-store-test";
      system = builtins.currentSystem;
      builder = "/bin/sh";
      args = [ "-c" "echo persisted > $out" ];
    }
  '';
  microvmHost = llm: {
    imports = [ self.nixosModules.default ];

    virtualisation = {
      memorySize = 4096;
      cores = 2;
    };

    environment.systemPackages = [ pkgs.python3 ];

    qwen-code-dev = {
      sshAuthorizedKeys = [ sshKeys.snakeOilEd25519PublicKey ];
      llmPort = 18080;
      llmModel = "qwen-local";
      vcpu = 1;
      memory = 1536;
      diskSize = 512;
    }
    // llm;
  };
in
pkgs.testers.runNixOSTest {
  name = "qwen-code-dev-microvm-host";

  nodes = {
    host = microvmHost { };

    lan = { nodes, ... }: microvmHost { llmHost = nodes.remote.networking.primaryIPAddress; };

    vpn = microvmHost { llmHost = "10.99.0.1"; };

    remote = {
      networking.firewall.allowedTCPPorts = [
        8000
        18080
      ];
      systemd.services = {
        web = {
          wantedBy = [ "multi-user.target" ];
          script = "${pkgs.python3}/bin/python3 -m http.server 8000";
        };
        llm = {
          wantedBy = [ "multi-user.target" ];
          script = "${pkgs.python3}/bin/python3 ${fakeLlm} 18080 /tmp/llm.log 0.0.0.0";
        };
      };
    };
  };

  testScript = ''
    ssh = (
        "timeout 120 ssh -i /root/key -p 2222 -o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 dev@127.0.0.1"
    )
    qwen = f"{ssh} 'qwen -p hello'"

    def guest_connects(address, port):
        return f"{ssh} 'timeout 10 bash -c \"exec 3<>/dev/tcp/{address}/{port}\"'"

    def address(machine):
        return machine.succeed("ip -4 -o address show eth1 | awk '{ sub(/\\/.*/, \"\", $4); print $4 }'").strip()

    start_all()
    remote.wait_for_open_port(8000)
    remote.wait_for_open_port(18080)
    remote_address = address(remote)

    for machine in [host, lan, vpn]:
        machine.wait_for_unit("microvm@qwen-code-dev.service")
        machine.succeed("install -m 600 ${sshKeys.snakeOilEd25519PrivateKey} /root/key")
        machine.succeed("systemd-run --unit=decoy-any python3 -m http.server --bind 0.0.0.0 18082")
        machine.wait_for_open_port(18082)

    host.succeed("systemd-run --unit=fake-llm python3 ${fakeLlm} 18080 /tmp/llm.log")
    host.succeed("systemd-run --unit=decoy-lo python3 -m http.server --bind 127.0.0.1 18081")
    host.wait_for_open_port(18080)
    host.wait_for_open_port(18081)
    lan.succeed("systemd-run --unit=decoy-lo python3 -m http.server --bind 127.0.0.1 18080")
    lan.wait_for_open_port(18080)
    vpn.succeed("ip link add vpn0 type dummy && ip address add 10.99.0.1/32 dev vpn0 && ip link set vpn0 up")
    vpn.succeed("systemd-run --unit=fake-llm python3 ${fakeLlm} 18080 /tmp/llm.log 10.99.0.1")
    vpn.succeed("systemd-run --unit=decoy-lo python3 -m http.server --bind 127.0.0.1 18081")
    vpn.wait_for_open_port(18080, "10.99.0.1")
    vpn.wait_for_open_port(18081)

    with subtest("LLM on the NixOS host"):
        host.wait_until_succeeds(f"{ssh} true", timeout=1200)
        host.succeed(guest_connects("10.0.2.2", 18080))
        host.fail(guest_connects("10.0.2.2", 18081))
        host.fail(guest_connects("10.0.2.2", 18082))
        host.fail(guest_connects("10.0.2.2", 22))
        host.fail(guest_connects(address(host), 18082))
        host.succeed(guest_connects(remote_address, 8000))
        assert "Hello from the local LLM." in host.succeed(qwen)
        host.succeed("grep -q 'chat/completions.*model=qwen-local' /tmp/llm.log")
        assert '"contextWindowSize":262144' in host.succeed(
            f"{ssh} 'cat /etc/qwen-code/settings.json'"
        )

    with subtest("LLM on another machine in the local network"):
        lan.wait_until_succeeds(f"{ssh} true", timeout=1200)
        base_url = lan.succeed(f"{ssh} 'echo $OPENAI_BASE_URL'").strip()
        assert base_url == f"http://{remote_address}:18080/v1", base_url
        lan.fail(guest_connects("10.0.2.2", 18080))
        lan.fail(guest_connects("10.0.2.2", 18082))
        lan.fail(guest_connects(address(lan), 18082))
        assert "Hello from the local LLM." in lan.succeed(qwen)
        remote.succeed("grep -q 'chat/completions.*model=qwen-local' /tmp/llm.log")

    with subtest("LLM on a VPN address of the NixOS host"):
        vpn.wait_until_succeeds(f"{ssh} true", timeout=1200)
        base_url = vpn.succeed(f"{ssh} 'echo $OPENAI_BASE_URL'").strip()
        assert base_url == "http://10.99.0.1:18080/v1", base_url
        vpn.succeed(guest_connects("10.99.0.1", 18080))
        vpn.fail(guest_connects("10.99.0.1", 18082))
        vpn.fail(guest_connects("10.0.2.2", 18081))
        vpn.fail(guest_connects("10.0.2.2", 18082))
        vpn.fail(guest_connects(address(vpn), 18082))
        assert "Hello from the local LLM." in vpn.succeed(qwen)
        vpn.succeed("grep -q 'chat/completions.*model=qwen-local' /tmp/llm.log")

    with subtest("Writable nix store persists across restarts"):
        built = host.succeed(f"{ssh} 'nix-build --no-out-link ${storeTest}'").strip().splitlines()[-1]
        assert built.startswith("/nix/store/"), built
        host.succeed("timeout 300 systemctl restart microvm@qwen-code-dev.service")
        host.wait_until_succeeds(f"{ssh} true", timeout=1200)
        host.succeed(f"{ssh} 'nix-store --check-validity {built}'")
        assert host.succeed(f"{ssh} 'cat {built}'").strip() == "persisted"

    with subtest("Graceful shutdown keeps the volumes"):
        host.succeed("timeout 300 systemctl stop microvm@qwen-code-dev.service")
        for image in ["home", "nix-store", "nix-var"]:
            host.succeed(f"test -e /var/lib/microvms/qwen-code-dev/qwen-code-dev-{image}.img")
  '';
}
