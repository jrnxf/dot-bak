#!/usr/bin/env bash
# Keeps ~/dotfiles in step across machines (README, "Syncing machines").
#
#   dotsync sync    fetch; fast-forward, or rebase local commits when the tree
#                   is clean; push what is ahead. Run every minute by a timer
#                   and after every commit by the repo's post-commit hook.
#   dotsync status  one short line for the prompt, empty when all is well:
#                   * uncommitted, ⇡ unpushed, ! last sync failed (the reason is
#                   in `dotsync why`), reload when nix-applied files changed
#                   since the last rebuild.
#   dotsync why     why the last sync failed.
#   dotsync built   record HEAD as applied; rebuild.sh runs it.
#
# It never merges, stashes or force-pushes: anything it cannot do cleanly is
# left alone and reported.
set -uo pipefail

repo=${DOTSYNC_REPO:-$HOME/dotfiles}
state=${DOTSYNC_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}
mkdir -p "$state"

git() { command git -C "$repo" "$@"; }

fail() {
  printf '%s\n' "$*" >"$state/sync-error"
  printf 'dotsync: %s\n' "$*" >&2
  exit 1
}

# Paths whose changes only land after `reload`. Everything else under home/ is
# a live link (mkOutOfStoreSymlink) and applies the moment it is pulled.
needs_rebuild() {
  grep -qE '\.nix$|^flake\.lock$|^[^/]+\.sh$|^home/firstmate/|^home/\.agents/|^home/\.config/herdr/config\.toml$'
}

sync() {
  local gitdir
  gitdir=$(git rev-parse --absolute-git-dir) || fail "$repo is not a git repository"
  # Someone (a person or an agent) is mid-operation; try again next time.
  for f in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD index.lock; do
    [ -e "$gitdir/$f" ] && return 0
  done
  git symbolic-ref -q HEAD >/dev/null || return 0
  git rev-parse -q --verify '@{u}' >/dev/null || return 0

  git fetch --quiet || fail "fetch failed"

  local ahead behind
  read -r ahead behind < <(git rev-list --left-right --count 'HEAD...@{u}')
  if [ "$behind" -gt 0 ]; then
    if [ "$ahead" -eq 0 ]; then
      # Refuses on its own when an uncommitted file would be overwritten.
      git merge --ff-only --quiet '@{u}' 2>/dev/null ||
        fail "can't fast-forward: uncommitted changes touch files that changed upstream"
    elif git diff --quiet && git diff --cached --quiet; then
      if ! git rebase --quiet '@{u}' >/dev/null 2>&1; then
        git rebase --abort
        fail "local and upstream commits conflict; rebase by hand"
      fi
    else
      fail "local and upstream both have commits; commit or stash, then run dotsync sync"
    fi
    ahead=$(git rev-list --count '@{u}..HEAD')
  fi
  if [ "$ahead" -gt 0 ]; then
    git push --quiet 2>/dev/null || fail "push failed"
  fi
  rm -f "$state/sync-error"
}

status() {
  local out="" porcelain built
  porcelain=$(git status --porcelain=v2 --branch 2>/dev/null) || return 0
  grep -q '^[^#]' <<<"$porcelain" && out+="*"
  grep -qE '^# branch\.ab \+[1-9]' <<<"$porcelain" && out+="⇡"
  [ -e "$state/sync-error" ] && out+="!"
  built=$(cat "$state/built" 2>/dev/null)
  if [ "$built" != "$(git rev-parse HEAD)" ]; then
    if [ -z "$built" ] || git diff --name-only "$built" HEAD 2>/dev/null | needs_rebuild; then
      out+="${out:+ }reload"
    fi
  fi
  [ -n "$out" ] && printf 'dotfiles %s\n' "$out"
  return 0
}

case ${1:-} in
  sync)
    # One sync at a time: the timer and the commit hook can overlap.
    exec 9>"$state/sync.lock"
    flock -n 9 || exit 0
    sync
    ;;
  status) status ;;
  why) cat "$state/sync-error" 2>/dev/null || echo "last sync succeeded" ;;
  built) git rev-parse HEAD >"$state/built" ;;
  *)
    echo "usage: dotsync sync|status|why|built" >&2
    exit 2
    ;;
esac
