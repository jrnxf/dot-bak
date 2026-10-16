# dotsync, which keeps ~/dotfiles in step across machines; see dotsync.sh.
{ pkgs }:

pkgs.writeShellApplication {
  name = "dotsync";
  # gh is git's credential helper for the https remote on Linux (home/.gitconfig).
  runtimeInputs = with pkgs; [ git gh flock coreutils gnugrep ];
  # The script uses `set -uo pipefail` on purpose: it reports failures itself.
  bashOptions = [ ];
  text = builtins.readFile ./dotsync.sh;
}
