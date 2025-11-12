# flake.nix
{

  inputs = {
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    systems.url = "github:nix-systems/default";
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      pre-commit-hooks,
      systems,
      treefmt-nix,
    }:
    let

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Small tool to iterate over each systems
      eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});

      treefmtModule = {
        programs.nixfmt.enable = true;
        programs.mdformat.enable = true;
      };

      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs treefmtModule);

      preCommitOutputs = eachSystem (
        pkgs:
        let
          preCommitCheck = pre-commit-hooks.lib.${pkgs.system}.run {
            src = ./.;
            hooks = {
              nixfmt.enable = true;
              mdformat.enable = true;
            };
          };
        in
        {
          pre-commit-check = preCommitCheck;
          shellHook = preCommitCheck.shellHook;
          # Safely filter for critical packages for the dev shell
          enabledPackages = builtins.filter (
            pkg: (pkg ? isCritical) && pkg.isCritical
          ) preCommitCheck.enabledPackages;
        }
      );

    in
    {
      # for `nix fmt`
      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
      # for `nix flake check`
      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.system}.config.build.check self;
        # Include pre-commit check in flake check
        pre-commit-check = preCommitOutputs.${pkgs.system}.pre-commit-check;
      });

      devShells = eachSystem (pkgs: {
        default = nixpkgs.legacyPackages.${pkgs.system}.mkShell {
          # Inherit the shell hook and dependencies from the common 'let' block
          inherit (preCommitOutputs.${pkgs.system}) shellHook;
          buildInputs = preCommitOutputs.${pkgs.system}.enabledPackages;
        };
      });

    };
}
