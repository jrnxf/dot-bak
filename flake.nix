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
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit user localOverrides; };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit user skillInputs; };
            home-manager.users.${user} = import ./home-darwin.nix;
            # Pre-existing files at a managed path (e.g. from before this repo took over,
            # or a background daemon recreating its config dir) get renamed instead of
            # blocking activation.
            home-manager.backupFileExtension = "hm-backup";
          }
        ];
      };

      # Standalone home-manager for a Linux machine: the user-level half of the
      # setup above, with no system layer. Applied by rebuild.sh.
      homeConfigurations."linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {
          inherit user skillInputs;
          pkgsUnstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "claude-code";
          };
        };
        modules = [ ./home-linux.nix ];
      };
    };
}
