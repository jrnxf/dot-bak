# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "zap"` in `configuration.nix` is intentional. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible. Do not soften it to `uninstall` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

## Persistent configuration changes

Use Nix for installation and symlinked files under `home/` for editable application configuration, including Zsh, Starship, fzf setup, and Codex. Prefer this over generated read-only configs or custom activation scripts. `home.nix` declares the packages and links every machine shares, `home-darwin.nix` and `home-linux.nix` add the per-OS ones, and `configuration.nix` manages macOS system settings. `reload` runs `rebuild.sh` and restarts Zsh. Preserve shell integrations when migrating settings, keep credentials and session data out of the repo, and verify that apps preserve file symlinks when saving. Keep Codex's global YOLO defaults in `home/.codex/config.toml`. Agent skills are declared in `agent-skills.nix` (authored ones under `home/.agents/skills/`, third-party ones as pinned flake inputs), never installed with `npx skills add`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
