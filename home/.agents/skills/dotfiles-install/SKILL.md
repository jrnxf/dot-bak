---
name: dotfiles-install
description: Install or configure anything on this user's machines through their Nix dotfiles (~/dotfiles) instead of ad hoc - CLI tools, Homebrew formulae and casks, taps, agent skills, MCP servers, Claude plugins, app config. Use whenever a task would otherwise run `brew install`, `npm i -g`, `npx skills add`, `pip install --user`, `cargo install`, or edit a file in ~ directly, from any project.
---

# Installing things on this machine

Everything persistent is declared in `~/dotfiles`, a nix-darwin + Home Manager flake that also drives Linux. An ad hoc install is wrong even when it works: a new machine would not get it, and on the Mac Homebrew's `cleanup = "zap"` removes any brew or cask not listed in `configuration.nix` on the next rebuild.

Read `~/dotfiles/AGENTS.md` first. The README covers each area in depth.

## Where each thing goes

| Thing | Where |
|---|---|
| CLI tool in nixpkgs, every machine | `home.packages` in `home.nix` |
| CLI tool for one OS | `home-darwin.nix` or `home-linux.nix` |
| Mac tool that tracks upstream closely, or not in nixpkgs | `brews` in `configuration.nix` |
| Mac GUI app | `casks` in `configuration.nix` |
| Third-party tap | `taps` in `configuration.nix`, `{ name = "owner/tap"; trusted = true; }`, and the formula as `"owner/tap/formula"` in `brews` |
| Same tool on Linux, which has no Homebrew | `home-linux.nix`, from `pkgsUnstable` if the release branch lags |
| Packaged nowhere | A pinned derivation in its own file, like `leaf.nix` or `firstmate-tools.nix`; bump version and hash together |
| Agent skill you wrote | `home/.agents/skills/<name>/`, plus its name in the `authored` list in `agent-skills.nix` |
| Third-party skill checked in as a copy (only when upstream must stay pinned to a file, like the axi ones) | `home/.agents/skills/<name>/` and the `vendored` list in `agent-skills.nix` |
| Third-party agent skill repo | A flake input with `flake = false` in `flake.nix`, passed through `extraSpecialArgs` and linked in `agent-skills.nix` |
| MCP server for Claude | `home/.claude/skills/dotfiles-mcp/.mcp.json` |
| Claude settings, hooks, agents, commands | `home/.claude/` (already linked) |
| App config file | The file under `home/`, linked with `mkOutOfStoreSymlink` in `home.nix` so it stays editable |
| One machine only | A `.work` overlay (README, "Machine-local overlays") or `local.nix` |

Never commit credentials or session state. Link individual files, not a whole directory, when the app keeps runtime state next to its config.

## Doing it

1. Remove any ad hoc copy first (`brew uninstall`, the `npx skills` copy and its entry in `~/.agents/.skill-lock.json`, a hand-made symlink). Otherwise Home Manager renames it to `*.hm-backup` and leaves clutter.
2. Make the edit in `~/dotfiles`. Run `git add -N` on new files: the flake only sees files git tracks.
3. Check it without sudo:
   - Mac: `darwin-rebuild build --flake ~/dotfiles#mac`
   - Linux eval: `nix eval ~/dotfiles#homeConfigurations.linux.config.home.file --apply builtins.attrNames`
4. Applying needs sudo on the Mac, so ask the user to run `! ~/dotfiles/rebuild.sh`. On Linux `rebuild.sh` runs without sudo.
5. Confirm the result where the user will use it: the binary on `PATH`, the app in `/Applications`, the skill in a fresh agent session.
6. Run the tests in `~/dotfiles/tests/` that touch what you changed.

## Keep this skill current

This skill is a live link into `~/dotfiles/home/.agents/skills/dotfiles-install/SKILL.md`. When you install something it does not cover, or a step here turns out wrong or missing, edit that file in the same change: add the row or fix the step, keep it short, and tell the user what you added. A wrong entry is worse than a missing one, so verify before you write.
