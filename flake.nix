{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Only for the few fast-moving agent CLIs home-linux.nix takes from it.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Third-party agent skill repos, pinned by flake.lock. agent-skills.nix
    # links every directory under each one's skills/. Add a new one to
    # skillInputs below too. Update with `nix flake update <name>`.
    emil-skills.url = "github:emilkowalski/skills";
    emil-skills.flake = false;
    i-have-adhd.url = "github:ayghri/i-have-adhd";
    i-have-adhd.flake = false;
    # Nests one level deeper (skills/<category>/<skill>), so unlike the
    # inputs above it is not added to skillInputs below - agent-skills.nix
    # links only its one skill we want, not every category folder.
    matt-skills.url = "github:mattpocock/skills";
    matt-skills.flake = false;
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, nixpkgs-unstable, ... }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your macOS username differs.
      user = "jrnxf";
      # Per-machine overrides (e.g. excluding an MDM-managed app on a work Mac) live in
      # local.nix. It's tracked with a neutral default - see the comment in that file for
      # how to set a real override without it leaking into the shared repo.
      localOverrides =
        if builtins.pathExists ./local.nix then import ./local.nix else { };
      skillInputs = { inherit (inputs) emil-skills i-have-adhd; };
      mattSkills = inputs.matt-skills;
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit user localOverrides; };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
        ];
      };

      # Home Manager runs standalone on both OSes, not inside nix-darwin, so
      # applying user-level changes needs no sudo and dotsync can do it on its
      # own. Only darwinConfigurations above needs `sudo darwin-rebuild`.
      # Applied by rebuild.sh.
      homeConfigurations."mac" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          config.allowUnfree = true;
        };
        extraSpecialArgs = { inherit user skillInputs mattSkills; };
        modules = [ ./home-darwin.nix ];
      };

      homeConfigurations."linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {
          inherit user skillInputs mattSkills;
          pkgsUnstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "claude-code";
          };
        };
        modules = [ ./home-linux.nix ];
      };
    };
}
