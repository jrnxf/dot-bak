{ user, localOverrides ? { }, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;

  # home/.zshrc runs compinit itself. nix-darwin's /etc/zshrc compinit sees a
  # different fpath, so the two runs invalidate ~/.zcompdump for each other and
  # every shell rebuilds the completion dump twice (~7s startup).
  programs.zsh.enableGlobalCompInit = false;

  # Touch ID for sudo; reattach makes it work inside tmux too.
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      AppleShowAllExtensions = true;
      _HIHideMenuBar = false;
    };
    # No dock.* settings: nix-darwin restarts the Dock on every activation
    # when any are set. autohide = false is the macOS default anyway.
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
    # NOTE: universalaccess.* (e.g. closeViewScrollWheelToggle, to stop Ctrl+scroll
    # zooming the screen during <C-w>/<C-a> chords) is deliberately NOT set here.
    # macOS TCC-protects that domain, so activation dies with
    # "Could not write domain com.apple.universalaccess". Set it by hand in
    # System Settings > Accessibility > Zoom.
  };
  nix-homebrew = {
    enable = true;
    inherit user;
    # This machine had a pre-existing /opt/homebrew install; migrate it
    # into nix-homebrew instead of wiping it (keeps installed packages).
    autoMigrate = true;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" "--quiet" ];
    taps = [
      # Trust flags mirror the pre-migration Brewfile: brew 6 refuses to load
      # formulae from untrusted third-party taps during bundle.
      "anomalyco/tap"
      { name = "aws/tap"; trusted = true; }
      { name = "charmbracelet/tap"; trusted = true; }
      "deskflow/tap"
      { name = "garden-io/garden"; trusted = true; }
      { name = "isacikgoz/taps"; trusted = true; }
      { name = "jason0x43/neovim-nightly"; trusted = true; }
      { name = "jrnxf/tap"; trusted = true; }
      { name = "libsql/sqld"; trusted = true; }
      { name = "oven-sh/bun"; trusted = true; }
      { name = "tilt-dev/tap"; trusted = true; }
      { name = "tursodatabase/tap"; trusted = true; }
      { name = "withgraphite/tap"; trusted = true; }
    ];
    brews = [
      "act"
      "age"
      "agent-browser"
      { name = "anomalyco/tap/opencode"; trusted = true; }
      "awscli"
      "bat"
      "bfg"
      "bitwarden-cli"
      "black"
      "caddy"
      "cmake"
      "colima"
      "coreutils"
      "delve"
      "docker"
      "edencommon"
      "exiftool"
      "fastfetch"
      "fb303"
      "fbthrift"
      "fclones"
      "fd"
      "ffmpeg"
      "figlet"
      "fizz"
      "folly"
      "fzf"
      "gettext"
      "gh"
      "git"
      "git-lfs"
      "gmp"
      "gnu-sed"
      "go"
      "go-task"
      "golang-migrate"
      "gotop"
      "gum"
      "harfbuzz"
      "hasura-cli"
      "helm"
      "herdr"
      "htop"
      "hyperfine"
      "imagemagick"
      "isacikgoz/taps/tldr"
      "jq"
      "jrnxf/tap/thokr"
      "krb5"
      "kubectx"
      "kubernetes-cli"
      "lastpass-cli"
      "lazygit"
      "leaf-markdown-viewer"  # terminal markdown viewer, installs `leaf`
      "lefthook"
      "libffi"
      "libgit2"
      # sqld is pulled in as a dependency of tursodatabase/tap/turso; declare it
      # so nix-homebrew writes its formula trust into trust.json (manual `brew
      # trust` entries get wiped on every activation).
      { name = "libsql/sqld/sqld"; trusted = true; }
      "libxml2"
      "libxmu"
      "libxslt"
      "libyaml"
      "lima-additional-guestagents"
      "lsd"
      "mvfst"
      "n"
      "neonctl"
      "neovim"
      "nmap"
      "node"
      "nss"
      "nvm"
      "ollama"
      "openssl@3"
      "oven-sh/bun/bun"
      "pi-coding-agent"
      "pipx"
      "poppler"
      "postgresql@17"
      "protobuf"
      "pyenv"
      "qemu"
      "railway"
      "readline"
      "ripgrep"
      "rsync"
      "rust"
      "shared-mime-info"
      "starship"
      "stripe-cli"
      "stylua"
      "telnet"
      "temporal"
      "thefuck"
      "tilt-dev/tap/tilt"
      "tmux"
      "tree"
      "tursodatabase/tap/turso"
      "urlview"
      "uv"
      "wangle"
      "watchman"
      "webp"
      "websocat"
      "wget"
      "withgraphite/tap/graphite"
      "woff2"
      "xclip"
      "yarn"
      "yq"
      "yt-dlp"
      "zsh"
      "zsh-autosuggestions"
    ];
    # Machine-specific exclusions (e.g. an MDM-managed app that collides with the
    # Homebrew install) live in local.nix, not here.
    casks = builtins.filter (c: !(builtins.elem c (localOverrides.excludeCasks or [ ]))) [
      "1password"
      "1password-cli"
      "betterdisplay"
      "brave-browser"
      "claude-code@latest"
      "cmux"
      "codex"
      "cursor"
      "dbeaver-community"
      "deepl"
      "firefox"
      "font-geist-mono-nerd-font"
      "ghostty"
      "google-chrome"
      "grandperspective"
      "handbrake-app"
      "kap"
      "karabiner-elements"
      "keycastr"
      "linear"
      "loom"
      "megasync"
      "neohtop"
      "ngrok"
      "nordvpn"
      "notion"
      "notion-calendar"
      "obs"
      "openlens"
      "openlogi"
      "orbstack"
      "pearcleaner"
      "postman"
      "pritunl"
      "qbittorrent"
      "raycast"
      "rectangle"
      "slack"
      "spokenly"
      "spotify"
      "topnotch"
      "visual-studio-code"
      "vlc"
      "zoom"
    ];
  };
}
