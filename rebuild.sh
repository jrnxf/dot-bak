#!/usr/bin/env bash
# Applies this repo to the machine.
#
#   rebuild.sh         apply the home config from the working tree; on a Mac,
#                      also `sudo darwin-rebuild switch` when the system config
#                      changed. `reload` runs this.
#   rebuild.sh --auto  apply the home config as committed, never sudo. dotsync
#                      runs this after a pull or commit; it prints "system"
#                      when a system change still waits for a `reload`.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# launchd and systemd start dotsync without the login shell's PATH.
export PATH="$PATH:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
export USER="${USER:-$(id -un)}"
nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }

auto=false
[ "${1:-}" = --auto ] && auto=true
if [ "$(uname -s)" = Linux ]; then host=linux; else host=mac; fi

# One apply at a time: a `reload` can overlap dotsync's. flock comes from
# home.nix, so a machine's very first run goes without it.
state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
mkdir -p "$state"
exec 9>"$state/apply.lock"
if command -v flock >/dev/null; then flock 9; fi

flake=$DIR
if $auto; then
  # Only what is committed, so a half-done edit never applies itself.
  flake="git+file://$DIR?rev=$(git -C "$DIR" rev-parse HEAD)"
fi

home=$(nix build --no-link --print-out-paths "$flake#homeConfigurations.$host.activationPackage")
# Rename a pre-existing file at a managed path instead of failing on it.
# Its output goes to stderr: --auto's stdout is only the "system" line.
HOME_MANAGER_BACKUP_EXT=hm-backup "$home/activate" >&2

if [ "$host" = mac ]; then
  # From the working tree, as darwin-rebuild sees it, so a local.nix override
  # counts.
  system=$(nix eval --raw "$DIR#darwinConfigurations.mac.system.outPath")
  if [ "$system" != "$(readlink /run/current-system)" ]; then
    if $auto; then
      echo system
    else
      sudo darwin-rebuild switch --flake "$DIR#mac"
    fi
  fi
fi

# Clears the "reload" marker (dotsync.sh). dotsync records its own applies.
if ! $auto && command -v dotsync >/dev/null; then
  dotsync built
fi
