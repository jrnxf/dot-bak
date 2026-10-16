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

  # Pull, push and apply ~/dotfiles every minute (dotsync.sh). Lingering is on
  # for this user, so the timer runs without a login. The profile path keeps
  # the unit unchanged when dotsync changes, as on the Mac.
  systemd.user.services.dotsync = {
    Unit.Description = "Sync ~/dotfiles with GitHub";
    Service = {
      Type = "oneshot";
      ExecStart = "${config.home.profileDirectory}/bin/dotsync sync";
    };
  };
  systemd.user.timers.dotsync = {
    Unit.Description = "Sync ~/dotfiles with GitHub every minute";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
