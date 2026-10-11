# User-level packages and links shared by every machine. The per-OS entry
# points, home-darwin.nix and home-linux.nix, import this and add their own.
{ config, lib, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  agentInstructions = "${config.xdg.stateHome}/dotfiles/AGENTS.md";
  # The prebuilt fzf-tab module has a Zsh version mismatch; use its shell fallback.
  fzfTab = pkgs.runCommand "zsh-fzf-tab-no-module" { } ''
    cp -r ${pkgs.zsh-fzf-tab} $out
    chmod -R u+w $out
    rm -rf $out/share/fzf-tab/modules
  '';
in

{
  home.username = user;
  # Linux uses the macOS-style path too (see README, "Linux machine"): tracked
  # hook commands and agent state name this home directory literally.
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
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
  ]
  # agent tooling firstmate needs on PATH
  ++ import ./firstmate-tools.nix { inherit pkgs; }
  # markdown renderer behind the Claude Code /mkd mod
  ++ [ (import ./leaf.nix { inherit pkgs; }) ];
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
  # The same config with a tinted sidebar and Firstmate's working directory,
  # for the Firstmate machine: home-linux.nix makes it that machine's config.
  # The tint shows when herdr itself runs there (over plain ssh); a Mac that
  # reaches it as a saved machine draws the UI with its own theme. herdr has
  # no include, only HERDR_CONFIG_PATH for a whole file, so this is generated
  # from the tracked config rather than copied; it follows edits to that file
  # at the next rebuild.
  home.file.".config/herdr-firstmate/config.toml".source =
    (pkgs.formats.toml { }).generate "herdr-firstmate-config.toml" (
      lib.recursiveUpdate (fromTOML (builtins.readFile ./home/.config/herdr/config.toml)) {
        # dark teal: text contrast stays within 5% of the default sidebar's
        theme.custom.sidebar_bg = "#12262b";
        # New workspaces, tabs and panes on the Firstmate machine open in
        # ~/firstmate instead of following the pane they came from. herdr
        # resolves this on the server, so it is the Linux machine's path.
        terminal.new_cwd = "~/firstmate";
      }
    );
  # Firstmate's model and effort choices per task, kept here so every machine
  # that runs Firstmate dispatches the same way and the Linux guest, which has
  # no backup, keeps them.
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

  # Share the authored skills across agents without replacing installed skills.
  home.file.".agents/skills/pr-walkthrough".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/pr-walkthrough";
  home.file.".claude/skills/pr-walkthrough".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/pr-walkthrough";
  home.file.".codex/skills/pr-walkthrough".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/pr-walkthrough";
  home.file.".agents/skills/pr-visual-evidence".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/pr-visual-evidence";
  home.file.".claude/skills/pr-visual-evidence".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/pr-visual-evidence";
  home.file.".codex/skills/pr-visual-evidence".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/pr-visual-evidence";
  home.file.".agents/skills/i-have-adhd".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/i-have-adhd";
  home.file.".claude/skills/i-have-adhd".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/i-have-adhd";
  home.file.".codex/skills/i-have-adhd".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/i-have-adhd";

  # Official axi.md catalog skills invoke their CLIs through Homebrew's npx.
  home.file.".agents/skills/gh-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/gh-axi";
  home.file.".claude/skills/gh-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/gh-axi";
  home.file.".codex/skills/gh-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/gh-axi";
  home.file.".agents/skills/chrome-devtools-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/chrome-devtools-axi";
  home.file.".claude/skills/chrome-devtools-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/chrome-devtools-axi";
  home.file.".codex/skills/chrome-devtools-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/chrome-devtools-axi";
  home.file.".agents/skills/lavish".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/lavish";
  home.file.".claude/skills/lavish".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/lavish";
  home.file.".codex/skills/lavish".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/lavish";
  home.file.".agents/skills/quota-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/quota-axi";
  home.file.".claude/skills/quota-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/quota-axi";
  home.file.".codex/skills/quota-axi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/quota-axi";

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
  # It also links any home/.agents/skills/<name>.work/ beside the skills above.
  home.activation.workOverlays = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.bash}/bin/bash ${./work-overlays.sh} \
      ${lib.escapeShellArg dotfiles} ${lib.escapeShellArg agentInstructions}
  '';
}
