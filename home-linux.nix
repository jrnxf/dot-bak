# The Linux home configuration, for a headless machine that runs agents:
# everything shared, plus what Homebrew provides on the Mac.
{ config, pkgs, pkgsUnstable, ... }:

{
  imports = [ ./home.nix ];

  home.packages = (with pkgs; [
    git
    gh
    nodejs
    bun
    tmux
    # uvx launches the Semble MCP server
    uv
    # the shared .zshrc aliases cat and ls to these
    bat
    lsd
    # the browser chrome-devtools-axi drives headless, and a font for it to
    # render text with
    chromium
    dejavu_fonts
  ]) ++ (with pkgsUnstable; [
    # Homebrew follows the latest release of these on the Mac; the release
    # branch the rest of this config is pinned to lags too far behind for them.
    claude-code
    herdr
  ]);
  fonts.fontconfig.enable = true;

  # This machine hosts Firstmate, so every herdr started here uses the config
  # home.nix generates for it (Firstmate's working directory). herdr's
  # sockets, logs and session state stay in ~/.config/herdr; only the config
  # file moves.
  home.sessionVariables.HERDR_CONFIG_PATH =
    "${config.home.homeDirectory}/.config/herdr-firstmate/config.toml";
}
