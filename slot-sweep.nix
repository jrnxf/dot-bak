# slot-sweep, which clears idle treehouse slots' build output; see slot-sweep.sh.
{ pkgs }:

pkgs.writeShellApplication {
  name = "slot-sweep";
  runtimeInputs = with pkgs; [ git coreutils findutils gnugrep gnused ];
  # The script uses `set -uo pipefail` on purpose: one failed removal must not
  # stop the rest.
  bashOptions = [ ];
  text = builtins.readFile ./slot-sweep.sh;
}
