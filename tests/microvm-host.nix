{ self, pkgs }:
let
  sshKeys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
  fakeLlm = ./no-internet/fake_openai.py;
in
pkgs.testers.runNixOSTest {
  name = "qwen-code-dev-microvm-host";

  nodes.host = {
    imports = [ self.nixosModules.default ];

    virtualisation = {
      memorySize = 4096;
      cores = 2;
    };

    environment.systemPackages = [ pkgs.python3 ];

    qwen-code-dev = {
      sshAuthorizedKeys = [ sshKeys.snakeOilEd25519PublicKey ];
      vcpu = 1;
      memory = 1536;
      diskSize = 512;
    };
  };

  testScript = ''
    ssh = (
        "timeout 120 ssh -i /root/key -p 2222 -o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 dev@127.0.0.1"
    )
    qwen = (
        f"{ssh} 'OPENAI_BASE_URL=http://10.0.2.2:18080/v1 OPENAI_API_KEY=dummy "
        "OPENAI_MODEL=local-model qwen -p hello'"
    )

    start_all()
    host.wait_for_unit("microvm@qwen-code-dev.service")
    host.succeed("install -m 600 ${sshKeys.snakeOilEd25519PrivateKey} /root/key")
    host.succeed("systemd-run --unit=fake-llm python3 ${fakeLlm} 18080 /tmp/llm.log")
    host.wait_for_open_port(18080)

    with subtest("qwen-code in the microvm uses the LLM on the host"):
        host.wait_until_succeeds(f"{ssh} true", timeout=1200)
        assert "Hello from the local LLM." in host.succeed(qwen)
        host.succeed("grep -q chat/completions /tmp/llm.log")

    with subtest("Graceful shutdown keeps the home volume"):
        host.succeed("timeout 300 systemctl stop microvm@qwen-code-dev.service")
        host.succeed("test -e /var/lib/microvms/qwen-code-dev/qwen-code-dev-home.img")
  '';
}
