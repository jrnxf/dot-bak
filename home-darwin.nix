# The Mac's home configuration: everything shared, plus what only makes sense
# with a display attached.
{ config, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  # MarkText ships unsigned, so the Homebrew cask was disabled (Gatekeeper) and
  # nixpkgs marks it bad on darwin. Package the upstream arm64 zip directly;
  # home-manager links the .app into ~/Applications/Home Manager Apps.
  marktext = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "marktext";
    version = "0.19.1";
    src = pkgs.fetchurl {
      url = "https://github.com/marktext/marktext/releases/download/v${finalAttrs.version}/marktext-mac-arm64-${finalAttrs.version}.zip";
      hash = "sha256-9UAuT6nUK/+JIky55V4LonVaGfm78ZMqFefH/PyLp3w=";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    sourceRoot = ".";
    dontFixup = true; # never touch a prebuilt app bundle
    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications
      cp -R marktext.app "$out/Applications/MarkText.app"
      runHook postInstall
    '';
    meta = {
      description = "Simple and elegant markdown editor";
      homepage = "https://github.com/marktext/marktext";
      license = pkgs.lib.licenses.mit;
      platforms = [ "aarch64-darwin" ];
    };
  });
in

{
  imports = [ ./home.nix ];

  home.packages = with pkgs; [
    # the font everything renders in
    nerd-fonts.hack
    # gui apps not installable via homebrew casks
    marktext  # markdown editor
  ];
  fonts.fontconfig.enable = true;
  # Copy .app bundles into ~/Applications/Home Manager Apps instead of
  # symlinking them into the store; Spotlight and Raycast skip symlinked apps.
  targets.darwin.copyApps.enable = true;
  targets.darwin.linkApps.enable = false;

  # Ghostty keeps runtime state (auto/) next to its config, so link just the file.
  home.file.".config/ghostty/config".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/ghostty/config";
  home.file.".config/ghostty/shaders/cursor-glide.glsl".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/ghostty/shaders/cursor-glide.glsl";

  # Karabiner saves via write-temp-then-rename, which clobbers a file symlink
  # on every GUI edit. Linking the whole directory instead makes those renames
  # land inside the repo, so GUI edits show up as a git diff rather than a
  # broken link. Runtime state written next to the config (assets/,
  # automatic_backups/) ends up in the repo dir too and is gitignored.
  home.file.".config/karabiner".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/karabiner";
}
