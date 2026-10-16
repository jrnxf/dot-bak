# User-level packages and links shared by every machine. The per-OS entry
# points, home-darwin.nix and home-linux.nix, import this and add their own.
{ config, lib, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  agentInstructions = "${config.xdg.stateHome}/dotfiles/AGENTS.md";
  dotsync = import ./dotsync.nix { inherit pkgs; };
  # The prebuilt fzf-tab module has a Zsh version mismatch; use its shell fallback.
  fzfTab = pkgs.runCommand "zsh-fzf-tab-no-module" { } ''
    cp -r ${pkgs.zsh-fzf-tab} $out
    chmod -R u+w $out
    rm -rf $out/share/fzf-tab/modules
  '';
in

{
  imports = [ ./agent-skills.nix ];

  home.username = user;
  # Linux uses the macOS-style path too (see README, "Linux machine"): tracked
  # hook commands and agent state name this home directory literally.
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  # Building the home-configuration.nix man page makes Determinate Nix warn
  # "derivation named 'options.json' ... without a proper context" on every
  # rebuild. The options are documented online anyway.
  manual.manpages.enable = false;
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    zsh
    starship
    jq        # json on the command line
    lazygit
    neovim
    flock     # one rebuild.sh at a time
  ]
  # agent tooling firstmate needs on PATH
  ++ import ./firstmate-tools.nix { inherit pkgs; }
  # markdown renderer behind the Claude Code /mkd mod
  ++ [ (import ./leaf.nix { inherit pkgs; }) ]
  # keeps this repo in step across machines; each OS module runs it on a timer
  ++ [ dotsync ];
  home.sessionVariables.EDITOR = "nvim";
  # A chrome-devtools-axi bridge and its headless Chrome run until someone
  # calls `chrome-devtools-axi stop`, and agents rarely do: finished workers
  # left browsers holding gigabytes for most of a day. With this set, a bridge
  # stops itself after 30 minutes without a command, and the next command
  # starts a fresh one.
  home.sessionVariables.CHROME_DEVTOOLS_AXI_IDLE_TIMEOUT_MS = "1800000";

  # Stable package paths for the editable shell configuration.
  home.file.".local/share/zsh-packages/zsh".source = pkgs.zsh;
  home.file.".local/share/zsh-packages/autosuggestions".source = pkgs.zsh-autosuggestions;
  home.file.".local/share/zsh-packages/syntax-highlighting".source = pkgs.zsh-syntax-highlighting;
  home.file.".local/share/zsh-packages/fzf-tab".source = fzfTab;
  home.file.".local/share/zsh-packages/oh-my-zsh".source = pkgs.oh-my-zsh;

  home.file.".zshrc".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.zshrc";
  home.file.".zshenv".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.zshenv";
  home.file.".config/starship.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/starship.toml";
  home.file.".codex/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.codex/config.toml";

  # Session hooks for Codex and OpenCode. `lavish-axi setup hooks` writes a
  # /nix/store path into these that breaks on upgrade, so stable versions are
  # tracked here; link files, not directories, because both tools keep runtime
  # state alongside.
  home.file.".codex/hooks.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.codex/hooks.json";
  home.file.".codex/herdr-agent-state.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.codex/herdr-agent-state.sh";
  home.file.".config/opencode/opencode.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/opencode/opencode.json";
  home.file.".config/opencode/plugins/axi-lavish-axi.js".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/opencode/plugins/axi-lavish-axi.js";
  home.file.".config/opencode/plugins/herdr-agent-state.js".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/opencode/plugins/herdr-agent-state.js";

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  # Firstmate's model and effort choices per task, kept here so every machine
  # that runs Firstmate dispatches the same way.
  home.file."firstmate/config/crew-dispatch.json".source =
    ./home/firstmate/crew-dispatch.json;
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/statusline-command.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/statusline-command.sh";
  home.file.".claude/agents".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/agents";
  home.file.".claude/hooks".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/hooks";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/commands";

  # Claude auto-loads plugins in its skills directory, including MCP-only plugins.
  home.file.".claude/skills/dotfiles-mcp".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/dotfiles-mcp";
  # The /mkd mod: a pane showing Claude's replies, rendered by the leaf package above.
  home.file.".claude/skills/mkd".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/mkd";

  home.file.".curl-format.txt".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.curl-format.txt";

  home.file.".gitconfig".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.gitconfig";
  home.file.".gitignore".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.gitignore";
  home.file.".tmux.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.tmux.conf";

  # Keep Pi's credential and runtime state local by linking only authored files and directories.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";

  # The global agent instructions go through a path work-overlays.sh owns: a
  # live link to home/AGENTS.md, or that file plus the gitignored
  # home/AGENTS.work.md when this machine has one. The overlay is invisible to
  # the flake, so it can only be detected at activation, and keeping the
  # generated file outside Home Manager's links means a switch never collides
  # with it.
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink agentInstructions;
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink agentInstructions;
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink agentInstructions;
  # It also links any home/.agents/skills/<name>.work/ beside agent-skills.nix's.
  home.activation.workOverlays = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.bash}/bin/bash ${./work-overlays.sh} \
      ${lib.escapeShellArg dotfiles} ${lib.escapeShellArg agentInstructions}
  '';
}
