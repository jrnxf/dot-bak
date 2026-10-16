# Standalone Home Manager installs into the per-user Nix profile. On Linux,
# Nix's installer only hooks interactive shells, so load Nix here too or
# commands run over ssh and by agents miss everything Nix installed.
if [[ $OSTYPE == linux* ]]; then
  # The Linux machine has no en_US.UTF-8 locale; C.UTF-8 is built into glibc.
  export LC_ALL=C.UTF-8
  if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
fi
if [[ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]]; then
  source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
