# Agent skills, linked into every agent's skills directory: ~/.agents/skills
# (shared, read by most agents), ~/.claude/skills and ~/.codex/skills.
# Install skills here, never with `npx skills add`: that writes untracked
# copies outside this repo that a new machine would not get.
{ config, lib, pkgs, skillInputs, mattSkills, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";

  linkSkill = name: source:
    lib.listToAttrs (map
      (dir: lib.nameValuePair "${dir}/${name}" { inherit source; })
      [ ".agents/skills" ".claude/skills" ".codex/skills" ]);

  # Every skill directory in a source, so an update picks up new skills.
  skillsIn = dir:
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));

  # Skills written in this repo, under home/.agents/skills, editable in place.
  authored = [
    "pr-walkthrough"
    "pr-visual-evidence"
    "dotfiles-install"
  ];

  # The official axi.md catalog skills, checked in beside the authored ones
  # and kept identical to their kunchenguid/<tool> upstreams. They invoke
  # their CLIs through npx.
  vendored = [
    "gh-axi"
    "chrome-devtools-axi"
    "lavish"
    "quota-axi"
  ];

  # mattpocock/skills nests one level deeper than skillInputs expects
  # (skills/<category>/<skill>), so it isn't in skillInputs - that would link
  # category folders, not skills. Pick just the one skill we want instead.
  # Its SKILL.md also declares `name: code-review`, which would collide with
  # Claude Code's built-in /code-review, so patch only that line in a copy.
  mattCodeReview = pkgs.runCommand "matt-code-review-skill" { } ''
    cp -r ${mattSkills}/skills/engineering/code-review $out
    chmod -R u+w $out
    sed -i '0,/^name: code-review$/s//name: matt-code-review/' $out/SKILL.md
  '';
in

{
  home.file = lib.mkMerge (
    map (name:
      linkSkill name (config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/${name}")
    ) (authored ++ vendored)
    # Third-party skills come from flake inputs, pinned by flake.lock.
    ++ lib.concatMap (src:
      map (name: linkSkill name "${src}/skills/${name}") (skillsIn "${src}/skills")
    ) (lib.attrValues skillInputs)
    ++ [ (linkSkill "matt-code-review" mattCodeReview) ]
  );
}
