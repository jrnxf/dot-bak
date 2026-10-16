# dotfiles

Watch the walkthrough: https://youtu.be/5N-okeDdIuI

My personal Mac setup, managed with nix-darwin and home-manager.
One repo, one command, and a fresh Mac ends up configured the same way every time.
A headless Linux machine can take the shell and agent half of it; see "Linux machine".

## Contributing / Using This Repo

These are my personal dotfiles, shared publicly so people can read them, learn from them, and fork them freely.
Feature requests and pull requests are not accepted here, and PRs are auto-closed.
If you find a bug, please open a GitHub Issue using the bug report template.

## What you get

Running the switch builds:

- System settings (dark mode, key repeat, dock, Finder, trackpad)
- Homebrew apps (casks and CLI tools)
- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font)
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (Ghostty config with the Cursor Dark theme)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)
- Pi coding agent, theme and local extensions, generic UI settings and model overrides, plus two deliberately pinned third-party Pi packages

## Prerequisites

- Apple Silicon Mac, by default.
- Intel Mac: change one line.
  In `configuration.nix`, set `nixpkgs.hostPlatform = "x86_64-darwin";` (the comment right there tells you the same thing).

## Fresh-machine setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/jrnxf/dot.git ~/dotfiles
cd ~/dotfiles
```

Before you run it: review "Make it yours" below.
Change the host label or CPU architecture if needed, and read the Homebrew cleanup warning.
`bootstrap.sh` applies the config to your machine, so do this first.

```sh
./bootstrap.sh
```

`bootstrap.sh` does four things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Checks that this repo lives at `~/dotfiles`.
   `home.nix` points at config files through that path, so the build links to nothing if the repo lives anywhere else.
3. Checks the `user` configured in `flake.nix` against your actual macOS username, and offers to fix it for you if they differ.
4. Runs the first `darwin-rebuild switch`.
   It fetches the `darwin-rebuild` tool from the nix-darwin 26.05 release branch, then applies this repo's locked flake config.

After that, `darwin-rebuild` exists and you're on the normal workflow below.

### Validate without applying

Once Nix is installed (`bootstrap.sh` step 1 handles that), you can check that the config builds without touching your system - handy when you have edited something:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

If you renamed the host label in "Make it yours", substitute your label for `mac` in these commands.

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

That's it.
No separate build-and-copy step.

## Linux machine

A Linux machine gets the user-level half of this setup through standalone home-manager: the shell, the agent configs, and the agent toolchain at the same versions the Mac runs.
There are no system settings, no Homebrew and no GUI apps.
It is built for Debian 13 on x86_64, for a machine that only runs agents and is reached over ssh.

Prepare the machine once, as root.
Install `curl`, `git` and `xz-utils`, then create the account with its home under `/Users`:

```sh
mkdir -p /Users
useradd --create-home --home-dir /Users/jrnxf --shell /bin/bash jrnxf
```

The macOS-style home is deliberate.
The tracked agent hooks name `/Users/jrnxf` literally (see "Agent session hooks"), and so do the paths agents record about the projects they work in, so both keep working when the home directory is the same on every machine.

Install Nix the way `bootstrap.sh` does on the Mac, then, as that user, one command builds and applies everything:

```sh
git clone https://github.com/jrnxf/dot.git ~/dotfiles
~/dotfiles/rebuild.sh
```

`rebuild.sh` is the same script as on the Mac; on Linux it applies `homeConfigurations.linux` from `flake.nix` and needs no sudo.
Run it again after any change, or use `reload`.

Two things need root and are outside what home-manager can do, so finish by hand:

```sh
# Log in to the zsh this repo configures.
echo /Users/jrnxf/.nix-profile/bin/zsh >> /etc/shells
chsh --shell /Users/jrnxf/.nix-profile/bin/zsh jrnxf

# chrome-devtools-axi only looks for a browser at Google Chrome's install path.
mkdir -p /opt/google/chrome
ln -s /Users/jrnxf/.nix-profile/bin/chromium /opt/google/chrome/chrome
```

What differs from the Mac:

- `home-linux.nix` installs what Homebrew provides there: git, the GitHub CLI, Node, uv, bun, tmux, Chromium, Claude Code and Herdr.
  Codex, OpenCode and Pi are not installed; their configs are linked, so adding the package is all it would take.
- Claude Code and Herdr come from the `nixpkgs-unstable` flake input, because Homebrew follows their latest release on the Mac.
  They move only when the lock does: `nix flake update nixpkgs-unstable`, then `./rebuild.sh`.
- Logins are per machine and never in this repo: run `gh auth login` and `claude` once.
- The Semble MCP server is unverified on Linux: `uv` is installed for it, but it has not been started there yet (see "MCP servers").

### Firstmate

The Linux machine hosts [Firstmate](https://github.com/kunchenguid/firstmate) at `~/firstmate`, and there is one way to it from the Mac: herdr's saved SSH machine.
Save it once on each Mac with `herdr machine add firstmate`, then plain `herdr` shows that machine in the sidebar beside Local, in one window.
herdr runs on the Mac and draws the UI; the herdr server on the Linux machine owns the panes and the agents in them, so they keep running when the Mac disconnects.
It expects a `firstmate` entry in your own `~/.ssh/config`, which is not in this repo.
Anywhere without herdr, `ssh firstmate` and run `herdr` there.
There is no `fm` command any more: it opened a second, standalone herdr attached to that machine alone, which the saved machine made redundant.

An interactive login shell on the Linux machine starts in `~/firstmate` when that directory exists.
Only a login shell still sitting in `$HOME` moves: commands run over ssh, `scp` and `rsync` are unaffected, and shells opened inside a herdr pane or a tmux window keep the directory they were given.
The Mac's login directory does not change.

The right edge of herdr's tab bar shows the hostname, on both machines.
Herdr resolves it where the panes run, so a remote attach names the remote machine.

`home.nix` generates `~/.config/herdr-firstmate/config.toml` from the tracked config plus `terminal.new_cwd = "~/firstmate"`, and `home-linux.nix` points `HERDR_CONFIG_PATH` at it for every herdr on the Linux machine, so every new workspace, tab and pane on the Linux machine opens in `~/firstmate` rather than following the pane it came from.
Herdr resolves that on the server, so the Mac's own herdr sessions keep the default.

## Syncing machines

Every machine with this repo keeps `~/dotfiles` in step with GitHub on its own, so a change made on one shows up on the others within a minute.
`dotsync.sh` does the work:

- A `post-commit` hook pushes each commit as soon as it is made.
  `home/.gitconfig` turns on `.githooks/` for this repo only.
- A launchd agent on the Mac and a systemd user timer on Linux run `dotsync sync` every minute.
  It fast-forwards to upstream, rebases local commits onto it when the tree is clean, and pushes anything ahead.
- It never merges, stashes or force-pushes.
  When it can't sync cleanly, such as an uncommitted edit to a file that changed upstream or two commits that conflict, it leaves the repo alone and reports why.

The prompt shows a `dotfiles` marker only when something needs attention:

- `*`: uncommitted changes, the one thing that does not sync.
- `⇡`: commits not pushed yet.
- `!`: the last sync failed; `dotsync why` says why.
- `reload`: a pulled change only takes effect after `reload`.
  Most of `home/` is live-linked and applies the moment it is pulled.
  Nix files, the scripts at the root, and the few files Home Manager copies need a rebuild.

Uncommitted work stays on the machine it was made on, so commit to share.
On Linux the clone uses https, and `gh auth git-credential` signs in for it from the `gh auth login` you already ran.

## Make it yours

This repo is mine.
If you clone it, review these before you run `bootstrap.sh`:

- **Username**: run `./bootstrap.sh` (it detects your macOS username and offers to set it) OR change the single `user = "jrnxf"` line in `flake.nix`.
  Everything else (`configuration.nix`, `home.nix`, home directory paths) is threaded from that one variable.
- **Host label** `"mac"`, in three places: `flake.nix` (the `darwinConfigurations."mac"` name), `rebuild.sh` (the `#mac` at the end of the flake reference), and `bootstrap.sh`'s first-switch command (also `#mac`).
  All three have to match.
- **CPU architecture**, `hostPlatform` in `configuration.nix` (see Prerequisites above).

**Git identity:** this config deliberately does not set your git name or email.
Git will stop your first commit and tell you to set them (`git config --global user.name "Your Name"` and `git config --global user.email you@example.com`).
If you'd rather manage that declaratively, add this back to `home.nix` with your own identity:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Your Name";
    email = "you@example.com";
  };
};
```

**Homebrew cleanup warning:** `configuration.nix` sets `homebrew.onActivation.cleanup = "zap"`.
That means every time you switch, Homebrew removes any package or cask on your machine that isn't listed in the `brews` and `casks` arrays in `configuration.nix`.
If you already have Homebrew stuff installed that isn't in that list, the first switch will uninstall it.
Read through `brews` and `casks` before you run `bootstrap.sh` or `rebuild.sh` for the first time, and add anything you want to keep.

**About `herdr`:** it's in the `brews` list.
It's a real public Homebrew formula (`brew info herdr` finds it in homebrew-core, no tap needed), so it will install fine.
If you don't use it, just remove it from `brews` in your copy.

**Heads-up:**

- `home/AGENTS.md` is my personal agent policy, and `home.nix` installs it for Claude, Codex, and opencode.
  If you clone this repo, you'd silently inherit my agent instructions - edit or delete `home/AGENTS.md` if you don't want that.
- The `cc` alias in `home/.zshrc` runs `claude --dangerously-skip-permissions`; `co` runs `codex`.
  Codex's symlinked `home/.codex/config.toml` sets global `approval_policy = "never"` and
  `sandbox_mode = "danger-full-access"`.
  New Codex sessions default to no approval prompts and no sandbox across projects, unless overridden.

## Repo tour

- `flake.nix` - the entry point.
  Wires up nixpkgs, nix-darwin, home-manager, and nix-homebrew, and declares the `mac` machine and the `linux` home.
- `configuration.nix` - system-level config: macOS defaults, Homebrew.
- `home.nix` - user-level packages and the symlinks described below, shared by every machine.
- `home-darwin.nix`, `home-linux.nix` - what only one OS gets, on top of `home.nix`.
- `firstmate-tools.nix` - pinned agent CLIs, packaged once for both systems.
- `leaf.nix` - the pinned `leaf` markdown renderer the Claude Code `/mkd` mod runs.
- `rebuild.sh` - re-applies the config after the first switch, on either OS.
  Run this after changing Nix declarations or adding managed links.
- `work-overlays.sh` - applies the machine-local overlays described below on every switch.
- `dotsync.sh`, `dotsync.nix`, `.githooks/` - keep every machine's clone in step with GitHub; see "Syncing machines".
- `home/` - the actual config files that get symlinked into place; the sections below explain the shared symlink model and Pi's narrower selective setup.

## How the symlinks work

The files under `home/` are the real files - editing them here is editing your live config, no rebuild needed to see the change in your editor.
`home.nix` uses `mkOutOfStoreSymlink` to point paths like `~/.config/nvim` straight at `home/.config/nvim` in this repo, so the two never drift out of sync.
You only run `./rebuild.sh` when you change something that isn't just a symlinked file, like a package list or a system default.

Zsh settings, aliases, and fzf integration live in `home/.zshrc`; Starship settings live in `home/.config/starship.toml`. Nix installs the tools and exposes stable plugin paths under `~/.local/share/zsh-packages`. Start a new shell after editing `.zshrc`, or use `reload` to rebuild and restart it. Codex links only `config.toml`, leaving credentials and sessions in its local directory.

### Machine-local overlays

Some agent instructions and skills belong on one machine only. Give them a `.work` suffix and they stay on that machine: `.gitignore` ignores every `*.work.md` and `*.work/`, so they are never committed. Back them up yourself, for example to a password manager.

- `home/AGENTS.work.md` is appended to `home/AGENTS.md` in the global instructions for Claude, Codex, and opencode. While it exists, those instructions are a generated copy, so run `reload` after editing either file. Without it, they stay a live link to `home/AGENTS.md`.
- `home/.agents/skills/<name>.work/` is linked as `<name>` into `~/.agents/skills/`, `~/.claude/skills/`, and `~/.codex/skills/`. A rebuild removes the links of a deleted overlay.

The flake cannot see gitignored files, so `work-overlays.sh` applies these on every switch. For per-machine Nix overrides, use `local.nix` instead.

## MCP servers

Codex and Claude Code both declare Semble, shadcn, Atlassian, Grafana, and Excalidraw:

- Codex reads `home/.codex/config.toml` through its existing global config symlink.
- Claude Code auto-loads the `dotfiles-mcp@skills-dir` plugin from
  `home/.claude/skills/dotfiles-mcp/`. Home Manager links that directory into
  `~/.claude/skills/`, making the servers available across projects without CLI flags.
  This requires a Claude Code version with skills-directory plugin support
  (verified with 2.1.267); the Homebrew declaration installs `claude-code@latest`.

Run `./rebuild.sh` to install the Claude plugin link, then start new agent sessions.
Check discovery with `codex mcp list` and
`claude plugin details dotfiles-mcp@skills-dir`; use `/mcp` inside Claude to check
connections and authenticate. In Codex, use `codex mcp login atlassian` and, if
required by the server, `codex mcp login grafana`.
Each app keeps its own authentication state outside the repo.
Grafana points at a work-specific endpoint and requires the appropriate network access.
[Excalidraw](https://github.com/excalidraw/excalidraw-mcp) uses its recommended
hosted server at `https://mcp.excalidraw.com`, so no local build is needed.
Its interactive diagram interface requires a client with MCP Apps support.

When adding or changing a server, update both Codex's `mcp_servers` tables and
the Claude plugin's `.mcp.json`. Keep tokens out of these tracked files; use
OAuth or the clients' environment-variable credential settings instead.
`node` and `uv` are already declared in `configuration.nix` on the Mac and in
`home-linux.nix` on Linux; npx and uvx resolve
the shadcn and Semble packages on launch, so those package versions are not
pinned by the Nix lockfile.

## Markdown pane

`home/.claude/skills/mkd/` is a Claude Code mod: `/mkd` opens a pane beside the conversation showing Claude's last reply, rendered by [leaf](https://leaf.rivolink.mg): headings, tables, code with line numbers, math, and Mermaid diagrams.
A second `/mkd` closes it.
`home.nix` links it into `~/.claude/skills/`, where Claude Code auto-loads it, and installs the `leaf` binary that `leaf.nix` pins, since leaf is not in nixpkgs.

The pane opens, closes, takes the keyboard and scrolls the way Claude Code's own `/diff` pane does:

| To | Do |
| --- | --- |
| open or close the pane | `/mkd`; the close mark, or ctrl+x then x, also closes it |
| give the pane the keyboard | ctrl+x then tab, or click in it; Esc hands it back |
| scroll | the wheel over the pane; with the keyboard, up/down (3 rows), page up/page down, home/end |
| previous / next reply | `p` / `n` with the keyboard in the pane, or click `previous` / `next` |

The line at the top (`Reply 2 of 5`) stays put while the reply scrolls under it.
While the pane is open on the newest reply it shows each new reply as Claude finishes it; paged back to an older one, it stays there.
It never opens by itself, and it always opens on the last reply.
It keeps the last 50 replies of the session; in a resumed session it reads them from the conversation.
`/clear` and `/resume` close it.

On a fullscreen terminal the pane docks on the right and needs 110 columns, as `/diff` does; narrower, `/mkd` asks for a wider terminal.
Without the fullscreen layout (`CLAUDE_CODE_NO_FLICKER=0`) it opens above the prompt with the keyboard, as tall as the reply, and Esc closes it.

The mod runs `leaf --inline ansi:<width>`, which prints the rendered document with no TUI, and converts its colors for the pane.
leaf's own interactive screen (sidebar, search, theme picker) is not part of it; run `leaf <file>` in a terminal for that.

Things to know:

- Mods are an early-access Claude Code feature (function hooks) whose API can change between releases; this one is verified with 2.1.289.
  If `/mkd` is missing, function hooks are not enabled for that session.
- Claude Code's own diff panel takes the same dock. While both are open they are tabs of it.
- leaf's default colors are made for a dark terminal.
- Claude Code writes type declarations into `home/.claude/skills/mkd/.claude-plugin/types/` when it loads the mod. It ignores them itself, so they never show up in `git status`.

Run `tests/mkd-mod.test.sh` before committing a change to the mod.
After a Claude Code upgrade, that test is also the quickest check that the mod still loads.

## Official AXI tools

The four tools in the [official AXI catalog](https://axi.md/) are installed using
their upstream skill-based setup: `gh-axi`, `chrome-devtools-axi`, `lavish-axi`
(skill name `lavish`), and `quota-axi`. No community catalog tools are included.

Their official skills live in `home/.agents/skills/` and `agent-skills.nix` links
each one into `~/.agents/skills/`, `~/.claude/skills/`, and `~/.codex/skills/`. Run
`./rebuild.sh` after adding or changing those links. The skills invoke the CLIs
with `npx -y`; `node`, `gh`, and `google-chrome` are already declared in
`configuration.nix`. No global npm install or extra Homebrew tap is needed.
The skill files are checked in; CLI versions are resolved by npx rather than
pinned by the Nix lockfile. Update the skills from their respective
`kunchenguid/<tool>` repositories, keeping upstream content intact.

### Third-party skills

Skill repositories are flake inputs with `flake = false`, pinned by
`flake.lock`. `agent-skills.nix` links every directory under the input's
`skills/` into the same three places, so new upstream skills arrive with an
update. Currently: [emilkowalski/skills](https://github.com/emilkowalski/skills)
and [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd). To add one,
declare the input in `flake.nix` and list it in `skillInputs` there. Update
with `nix flake update <input> && ./rebuild.sh`. Do not use
`npx skills add`: it installs untracked copies a new machine would not get.

A repo that nests skills one level deeper (`skills/<category>/<skill>`, like
[mattpocock/skills](https://github.com/mattpocock/skills)) isn't added to
`skillInputs` - that would link category folders, not skills. Instead pin it
as its own flake input and have `agent-skills.nix` link only the one skill
you want, patching its `SKILL.md` `name:` field in a `pkgs.runCommand` copy
if it would otherwise collide with a built-in skill name (see
`matt-code-review`, linked from `skills/engineering/code-review`).

[Firstmate](https://github.com/kunchenguid/firstmate) needs the binaries
themselves on `PATH`, at minimum versions, so `firstmate-tools.nix` additionally
packages pinned releases of those four plus `tasks-axi`, `treehouse`, and
`no-mistakes`. The file's header describes how to bump a version.

### OpenCode

`home/.config/opencode/opencode.json` is linked into place. It defines a local
Ollama provider and defaults to `ollama/gpt-oss:20b-32k`, a 32k-context variant
that fits in 24 GB of RAM. Homebrew installs Ollama, but models are not
declarative, so create the variant once per machine (13 GB download):

```sh
ollama create gpt-oss:20b-32k -f ~/dotfiles/home/.config/opencode/gpt-oss-20b-32k.Modelfile
```

The config also lists `qwen3-coder:30b-32k`, which needs more memory than that
and is not pulled by default. It loads the caveman plugin from
`plugins/caveman/`, which caveman's own installer manages and is not tracked.

### Agent session hooks

Claude Code, Codex, and OpenCode each run herdr's agent-state reporter and
`lavish-axi`'s ambient context as session hooks. Claude Code and Codex also run
`gh-axi` and `chrome-devtools-axi` at session start. All of them are tracked and
linked by `home.nix`:

- Claude Code: `home/.claude/settings.json` and `home/.claude/hooks/`.
- Codex: `home/.codex/hooks.json` and `home/.codex/herdr-agent-state.sh`.
- OpenCode: `home/.config/opencode/plugins/`.
- Pi: `home/.pi/agent/extensions/herdr-agent-state.ts`, herdr's reporter only.

The tracked copies call `lavish-axi` by name and keep herdr's own hook form,
`bash '/Users/jrnxf/...'`, which is fine because every machine uses the `jrnxf`
account with its home at `/Users/jrnxf`, Linux included. `herdr integration install` only recognizes that exact form, so with it
in place a reinstall changes nothing; any other spelling gets a duplicate
appended. Do not run `lavish-axi setup hooks`: it rewrites the command to a
`/nix/store` path that breaks on the next upgrade. Run
`tests/agent-hooks.test.sh` before committing changes to these files. Codex
asks to trust `hooks.json` again whenever it changes (`/hooks`).

## Pi coding agent

The [Pi coding agent](https://pi.dev) is declared as `pi-coding-agent` in `configuration.nix`'s Homebrew package list. `./bootstrap.sh` or `./rebuild.sh` installs it with the other managed CLI tools. Launch it in a project:

```sh
pi
```

[Pi Launcher](https://github.com/kunchenguid/homebrew-tap) is also optional and installed from its owner, not declared by this config:

```sh
brew install --cask kunchenguid/tap/pi-launcher
```

Home Manager owns exactly two repository-authored Pi directories: `~/.pi/agent/themes` and `~/.pi/agent/extensions`. It also links `models.json` and `settings.json` as individual files. The local extension directory is for public, repository-authored extensions only - third-party package code never belongs there. Run `/reload` after editing a local extension or other Pi resources. The terminal-title extension shows a spinner while Pi is working, then a completion mark with the session name or current directory. The `rose-pine-moon` theme was authored clean-room from the public [Rosé Pine Moon palette](https://rosepinetheme.com/palette) and Pi's [public theme schema](https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json), not from a private or live theme file.

### Pi Calm

`home/.pi/agent/extensions/calm` is a standalone local Pi extension. Home Manager's existing global extensions-directory link makes Pi auto-load it without another declaration. `/calm` toggles a conversation-only presentation mode and is off by default. Its choice is stored locally in `~/.pi/agent/calm` (or the directory selected by `PI_CODING_AGENT_DIR`), not in this repository or Home Manager. Adapted from Firstmate under the bundled MIT license, Calm imports no Firstmate modules and has no Firstmate runtime dependency.

When enabled, Calm hides collapsed thinking and the call/result shells for Pi's seven built-in tools (`read`, `bash`, `edit`, `write`, `grep`, `find`, and `ls`) without leaving blank transcript rows. During an active run it replaces Pi's working row with a two-line animated blue-water, yellow-boat widget. `/calm` restores Pi's stock rendering and preserves the existing Ctrl+O tool-expansion choice.

Calm never changes prompts, tool execution, model context, session data, or ordering. `/share` and `/export` use the complete stock transcript. Generic custom tools, images, and unsupported Pi transcript classes deliberately remain visible because Pi has no safe general-purpose transcript filter. If a future Pi release no longer exports the exact collapsed-thinking rendering seam, Calm logs one diagnostic and leaves only that adapter disabled; all other behavior remains available.

Pi's package system declares two third-party sources in the linked global `settings.json`:

- `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6` - the exact public npm release from `ryan_nookpi`.
- `git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055` - the exact public `algal` commit for experimental OpenAI server-side compaction.

The version and commit are immutable pins, so Pi does not move them during package updates. Deliberate updates require a new source and security audit, followed by an explicit pin change in `home/.pi/agent/settings.json`. On Pi 0.82.0, global settings declarations install missing pinned packages automatically at startup. No one-time install command is required. Pi keeps the downloaded npm and git package trees in its own unmanaged `~/.pi/agent/npm` and `~/.pi/agent/git` runtime directories, outside Home Manager and Git tracking.

Both packages execute with your full user permissions and must be trusted like any other executable code. The compaction package is experimental, sends the relevant OpenAI compaction and continuity data to OpenAI, and upstream declares the stale peer range `>=0.80.9 <0.81.0`; this exact immutable ref was locally proven to load and perform remote compaction on Pi 0.82.0. Do not treat that proof as a guarantee for a different Pi version or a different package ref.

Home Manager deliberately does not manage `~/.pi/agent` itself, or Pi authentication, sessions, trust decisions, caches, npm/git package trees, or any other runtime state. The model overrides contain no credentials or endpoint settings, do not choose a default model, and only take effect after you authenticate Pi yourself. Use `/login` inside Pi to connect a supported subscription, then `/model` to choose a model. Homebrew manages the CLI version separately from the pinned extension packages; the Pi 0.82.0 compatibility proof above does not cover later CLI releases. A launcher and third-party package source code are not installed into this repository.

## Notes

The first time you launch `nvim`, it bootstraps [lazy.nvim](https://github.com/folke/lazy.nvim) by cloning plugins from GitHub.
That needs network access once; after that it's offline.
Neovim uses the rose-pine moon theme; Ghostty uses Cursor Dark.
Neovim keeps italics off and uses a transparent background on macOS, Windows, and WSL so it matches the terminal setup.

## License

This repo is licensed under MIT No Attribution.
See `LICENSE`.
