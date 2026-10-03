#################
 qwen-code-flake
#################

A NixOS module that runs a development virtual machine (VM) with `qwen-code
<https://github.com/QwenLM/qwen-code>`_. This build of qwen-code sends no requests to
Internet servers when it starts with a local large language model (LLM) server. The VM
uses `microvm.nix <https://github.com/microvm-nix/microvm.nix>`_ and starts with the
host. It can reach the Internet, but on the host only the LLM server.

*******
 Usage
*******

1. Add the module to the ``flake.nix`` file of your NixOS configuration:

   .. code-block:: nix

       {
         inputs = {
           nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
           qwen-code-flake.url = "github:oynqr/qwen-code-flake";
         };

         outputs =
           { nixpkgs, qwen-code-flake, ... }:
           {
             nixosConfigurations.HOSTNAME = nixpkgs.lib.nixosSystem {
               modules = [
                 ./configuration.nix
                 qwen-code-flake.nixosModules.default
                 {
                   qwen-code-dev = {
                     sshAuthorizedKeys = [ "SSH_PUBLIC_KEY" ];
                     llmModel = "MODEL_NAME";
                   };
                 }
               ];
             };
           };
       }

   Replace the following:

   - ``HOSTNAME``: the name of your NixOS configuration.
   - ``SSH_PUBLIC_KEY``: your SSH public key.
   - ``MODEL_NAME``: the name of the model on your LLM server.

2. Apply the configuration:

   .. code-block:: shell

       sudo nixos-rebuild switch --flake .#HOSTNAME

3. Connect to the VM from the host:

   .. code-block:: shell

       ssh -p 2222 dev@127.0.0.1

4. In the VM, start qwen-code:

   .. code-block:: shell

       qwen

*********
 Options
*********

.. list-table::
    :header-rows: 1
    :widths: 30 15 55

    - - Option
      - Default
      - Description
    - - ``qwen-code-dev.sshAuthorizedKeys``
      - Required
      - SSH public keys that can log in as ``dev``.
    - - ``qwen-code-dev.llmModel``
      - Required
      - Name of the model on the LLM server.
    - - ``qwen-code-dev.llmHost``
      - ``"127.0.0.1"``
      - Host of the LLM server. ``"127.0.0.1"`` is the NixOS host. For other addresses
        of the NixOS host, use an IP address.
    - - ``qwen-code-dev.llmPort``
      - ``11434``
      - Port of the LLM server.
    - - ``qwen-code-dev.packages``
      - ``[ ]``
      - Additional packages in the VM.
    - - ``qwen-code-dev.vcpu``
      - ``2``
      - Number of virtual CPUs.
    - - ``qwen-code-dev.memory``
      - ``4096``
      - Memory in MiB.
    - - ``qwen-code-dev.diskSize``
      - ``16384``
      - Size of ``/home`` in MiB.
    - - ``qwen-code-dev.storeSize``
      - ``16384``
      - Size of the writable Nix store in MiB.
