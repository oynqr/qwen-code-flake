{ self, pkgs }:
let
  sshKeys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  fakeLlm = ./no-internet/fake_openai.py;
in
pkgs.testers.runNixOSTest {
  name = "qwen-code-dev-microvm-host";

  nodes = {
    host = {
      imports = [ self.nixosModules.default ];

      virtualisation = {
        memorySize = 4096;
        cores = 2;
      };

      environment.systemPackages = [ pkgs.python3 ];

      qwen-code-dev = {
        sshAuthorizedKeys = [ sshKeys.snakeOilEd25519PublicKey ];
        llmPort = 18080;
        vcpu = 1;
        memory = 1536;
        diskSize = 512;
      };
    };

    remote = {
      networking.firewall.allowedTCPPorts = [ 8000 ];
      systemd.services.web = {
        wantedBy = [ "multi-user.target" ];
        script = "${pkgs.python3}/bin/python3 -m http.server 8000";
      };
    };
  };

  testScript = ''
    ssh = (
        "timeout 120 ssh -i /root/key -p 2222 -o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 dev@127.0.0.1"
    )
    qwen = f"{ssh} 'OPENAI_API_KEY=dummy OPENAI_MODEL=local-model qwen -p hello'"

    def guest_connects(address, port):
        return f"{ssh} 'timeout 10 bash -c \"exec 3<>/dev/tcp/{address}/{port}\"'"

    def address(machine):
        return machine.succeed("ip -4 -o address show eth1 | awk '{ sub(/\\/.*/, \"\", $4); print $4 }'").strip()

    start_all()
    remote.wait_for_open_port(8000)
    host.wait_for_unit("microvm@qwen-code-dev.service")
    host.succeed("install -m 600 ${sshKeys.snakeOilEd25519PrivateKey} /root/key")
    host.succeed("systemd-run --unit=fake-llm python3 ${fakeLlm} 18080 /tmp/llm.log")
    host.succeed("systemd-run --unit=decoy-lo python3 -m http.server --bind 127.0.0.1 18081")
    host.succeed("systemd-run --unit=decoy-any python3 -m http.server --bind 0.0.0.0 18082")
    host.wait_for_open_port(18080)
    host.wait_for_open_port(18081)
    host.wait_for_open_port(18082)

    with subtest("The microvm reaches the LLM port of the host and nothing else on it"):
        host.wait_until_succeeds(f"{ssh} true", timeout=1200)
        host.succeed(guest_connects("10.0.2.2", 18080))
        host.fail(guest_connects("10.0.2.2", 18081))
        host.fail(guest_connects("10.0.2.2", 18082))
        host.fail(guest_connects("10.0.2.2", 22))
        host.fail(guest_connects(address(host), 18082))
        host.succeed(guest_connects(address(remote), 8000))

    with subtest("qwen-code in the microvm uses the LLM on the host"):
        assert "Hello from the local LLM." in host.succeed(qwen)
        host.succeed("grep -q chat/completions /tmp/llm.log")

    with subtest("Graceful shutdown keeps the home volume"):
        host.succeed("timeout 300 systemctl stop microvm@qwen-code-dev.service")
        host.succeed("test -e /var/lib/microvms/qwen-code-dev/qwen-code-dev-home.img")
  '';
}
