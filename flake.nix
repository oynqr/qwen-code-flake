{
  description = "qwen-code overridden to the latest upstream release";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          qwen-code = pkgs.qwen-code.overrideAttrs (
            finalAttrs: prevAttrs: {
              version = "0.24.7";

              src = pkgs.fetchFromGitHub {
                owner = "QwenLM";
                repo = "qwen-code";
                tag = "v${finalAttrs.version}";
                hash = "sha256-vFRBbW7sLXvVzmBrN47Q7jMdLY/2ebhguMW5TXeiX/Y=";
              };

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
            }
          );
        in
        {
          inherit qwen-code;
          default = qwen-code;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
