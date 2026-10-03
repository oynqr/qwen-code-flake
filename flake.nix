{
  description = "qwen-code overridden to the latest upstream release";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          systemDefaults = pkgs.writeText "qwen-code-system-defaults.json" (
            builtins.toJSON {
              "$version" = 4;
              privacy.usageStatisticsEnabled = false;
              general.enableAutoUpdate = false;
              telemetry.enabled = false;
            }
          );
          qwen-code = pkgs.qwen-code.overrideAttrs (
            finalAttrs: prevAttrs: {
              version = "0.24.7";

              src = pkgs.fetchFromGitHub {
                owner = "QwenLM";
                repo = "qwen-code";
                tag = "v${finalAttrs.version}";
                hash = "sha256-vFRBbW7sLXvVzmBrN47Q7jMdLY/2ebhguMW5TXeiX/Y=";
              };

              patches = (prevAttrs.patches or [ ]) ++ [
                ./patches/usage-statistics-default-off.patch
                ./patches/extension-update-check-setting.patch
              ];

              npmDeps = null;

              pnpmDeps = pkgs.fetchPnpmDeps {
                inherit (finalAttrs) pname version src;
                pnpm = pkgs.pnpm_11;
                fetcherVersion = 4;
                hash = "sha256-gfPJHK9hcd8g+IBSlUbxTteWjuHDastVKeAV9FZik0Q=";
              };

              nativeBuildInputs =
                builtins.filter (p: (p.name or "") != "npm-config-hook") prevAttrs.nativeBuildInputs
                ++ [
                  pkgs.pnpm_11
                  pkgs.pnpmConfigHook
                  pkgs.makeWrapper
                ];

              postPatch = ''
                substituteInPlace scripts/build.js \
                  --replace-fail "corepack pnpm" "pnpm"
              '';

              preBuild = ''
                node_modules/.bin/patch-package
              '';

              installPhase =
                builtins.replaceStrings
                  [ "npm prune --production" ]
                  [
                    "rm -rf node_modules packages/*/node_modules && pnpm install --offline --prod --frozen-lockfile --ignore-scripts"
                  ]
                  prevAttrs.installPhase;

              postInstall = (prevAttrs.postInstall or "") + ''
                wrapProgram $out/bin/qwen \
                  --set-default QWEN_CODE_SYSTEM_DEFAULTS_PATH ${systemDefaults} \
                  --set-default QWEN_CODE_DISABLE_PRECONNECT 1
              '';
            }
          );
        in
        {
          inherit qwen-code;
          default = qwen-code;
        }
      );

      checks =
        nixpkgs.lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
          (
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
              qwen = nixpkgs.lib.getExe self.packages.${system}.qwen-code;
            in
            {
              no-internet =
                pkgs.runCommand "qwen-code-no-internet"
                  {
                    nativeBuildInputs = [
                      pkgs.python3
                      pkgs.strace
                    ];
                  }
                  ''
                    bash ${./tests/no-internet/check.sh} ${qwen} ${./tests/no-internet}
                    touch $out
                  '';
            }
          );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
