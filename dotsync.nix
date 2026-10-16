# dotsync, which keeps ~/dotfiles in step across machines; see dotsync.sh.
{ pkgs }:

let
  # The Mac's HUD (dotsync-hud.js), shown for 5 seconds. osascript ships with
  # macOS, so there is nothing to install for it.
  hud = pkgs.writeShellScript "dotsync-hud" ''
    exec /usr/bin/osascript -l JavaScript ${./dotsync-hud.js} "$1" "$2" "''${3:-}" 5
  '';
in
pkgs.writeShellApplication {
  name = "dotsync";
  # gh is git's credential helper for the https remote on Linux (home/.gitconfig).
  runtimeInputs = with pkgs; [ git gh flock coreutils gnugrep ];
  # The script uses `set -uo pipefail` on purpose: it reports failures itself.
  bashOptions = [ ];
  # A default, so tests can point DOTSYNC_NOTIFY somewhere else.
  text = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
    : "''${DOTSYNC_NOTIFY=${hud}}"
  '' + builtins.readFile ./dotsync.sh;
}
