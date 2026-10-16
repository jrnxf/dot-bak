#!/usr/bin/env bash
# Keeps ~/dotfiles in step across machines (README, "Syncing machines").
#
#   dotsync sync    fetch; fast-forward, or rebase local commits when the tree
#                   is clean, or follow a history GitHub rewrote when there
#                   are no local commits to keep; push what is ahead; then,
#                   when a pulled or committed change needs a rebuild, apply
#                   it with `rebuild.sh --auto`. Run every minute by a timer and after
#                   every commit by the repo's post-commit hook.
#   dotsync status  one short line, empty when all is well:
#                   * uncommitted, ⇡ unpushed, ! last sync failed (the reason is
#                   in `dotsync why`), reload when a change waits for `reload`.
#   dotsync why     why the last sync failed.
#   dotsync built   record HEAD as applied; rebuild.sh runs it.
#
# When a sync pulls commits, leaves a system change for `reload`, or fails in
# a new way, it runs $DOTSYNC_NOTIFY with <ok|warn|fail> <title> <detail>. On
# a Mac that is the HUD in dotsync-hud.js (dotsync.nix sets it); elsewhere
# nothing is shown.
#
# It never merges, stashes or force-pushes: anything it cannot do cleanly is
# left alone and reported. When GitHub's history was rewritten and this machine
# has no commits of its own, it moves to the new history with `git reset
# --keep`, which refuses rather than touch uncommitted work.
set -uo pipefail

repo=${DOTSYNC_REPO:-$HOME/dotfiles}
state=${DOTSYNC_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}
apply_cmd=${DOTSYNC_APPLY:-$repo/rebuild.sh}
mkdir -p "$state"

git() { command git -C "$repo" "$@"; }

notify() {
  [ -n "${DOTSYNC_NOTIFY:-}" ] || return 0
  "$DOTSYNC_NOTIFY" "$@" >/dev/null 2>&1 || true
}

fail() {
  # Each failure is shown once, not again every minute until it is fixed.
  if [ "$(cat "$state/sync-error" 2>/dev/null)" != "$*" ]; then
    notify fail "dotfiles sync failed" "$*"
  fi
  printf '%s\n' "$*" >"$state/sync-error"
  printf 'dotsync: %s\n' "$*" >&2
  exit 1
}

# pulled_summary <old head> <fetched upstream>: what a sync brought in.
pulled_summary() {
  local n subject
  n=$(git rev-list --count "$1..$2")
  subject=$(git log -1 --format=%s "$2")
  if [ "$n" -eq 1 ]; then
    printf 'pulled 1 commit: %s' "$subject"
  else
    printf 'pulled %s commits, latest: %s' "$n" "$subject"
  fi
}

# rebuild_pending: true when HEAD has changes that only apply after a rebuild.
rebuild_pending() {
  local built
  built=$(cat "$state/built" 2>/dev/null)
  [ "$built" != "$(git rev-parse HEAD)" ] || return 1
  [ -z "$built" ] || git diff --name-only "$built" HEAD 2>/dev/null | needs_rebuild
}

# Paths whose changes only land after `reload`. Everything else under home/ is
# a live link (mkOutOfStoreSymlink) and applies the moment it is pulled.
needs_rebuild() {
  grep -qE '\.nix$|^flake\.lock$|^[^/]+\.(sh|js)$|^home/firstmate/|^home/\.agents/'
}

# apply: rebuild.sh --auto for HEAD, then record HEAD as built. Prints
# "system" when a system change still waits for `reload`. A config that fails
# to apply fails the same way every minute, so after a failure it waits for
# the next commit.
apply() {
  local head out
  head=$(git rev-parse HEAD)
  if [ "$(cat "$state/apply-failed" 2>/dev/null)" != "$head" ]; then
    if out=$("$apply_cmd" --auto 2>"$state/apply.log"); then
      rm -f "$state/apply-failed"
      printf '%s\n' "$head" >"$state/built"
      if [ "$out" = system ]; then
        printf '%s\n' "$head" >"$state/system-pending"
        echo system
      else
        rm -f "$state/system-pending"
      fi
      return 0
    fi
    printf '%s\n' "$head" >"$state/apply-failed"
  fi
  fail "couldn't apply the config: $(grep . "$state/apply.log" | tail -n1)"
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

  # Upstream as of the last fetch, to tell a rewrite from new commits.
  local old_up
  old_up=$(git rev-parse -q --verify '@{u}')

  # No HUD for this one: a laptop without a network fails it all the time.
  if ! git fetch --quiet; then
    printf '%s\n' "fetch failed" >"$state/sync-error"
    exit 1
  fi

  local ahead behind old up followed=""
  old=$(git rev-parse HEAD)
  up=$(git rev-parse '@{u}')
  read -r ahead behind < <(git rev-list --left-right --count 'HEAD...@{u}')
  # GitHub's history was rewritten and everything here is the old history:
  # follow it. Rebasing would carry the dropped commits back.
  if [ "$ahead" -gt 0 ] && [ -n "$old_up" ] &&
    ! git merge-base --is-ancestor "$old_up" '@{u}' &&
    git merge-base --is-ancestor HEAD "$old_up"; then
    git reset --keep --quiet '@{u}' 2>/dev/null ||
      fail "can't follow rewritten history: uncommitted changes touch files that changed upstream"
    followed=1
    ahead=0
  fi
  if [ "$behind" -gt 0 ] && [ -z "$followed" ]; then
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
  local applied=""
  if rebuild_pending; then
    applied=$(apply) || exit 1
  fi
  rm -f "$state/sync-error"

  if [ -n "$followed" ]; then
    if [ "$applied" = system ]; then
      notify warn "dotfiles followed GitHub, reload for system settings" "followed rewritten history on GitHub"
    else
      notify ok "dotfiles up to date" "followed rewritten history on GitHub"
    fi
  elif [ "$behind" -gt 0 ]; then
    # Claim "up to date" only when it is checked: this machine has exactly
    # what GitHub has, all of it applied.
    if [ "$applied" = system ]; then
      notify warn "dotfiles pulled, reload for system settings" "$(pulled_summary "$old" "$up")"
    elif [ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ]; then
      notify ok "dotfiles up to date" "$(pulled_summary "$old" "$up")"
    fi
  elif [ "$applied" = system ]; then
    notify warn "dotfiles applied, reload for system settings" "$(git log -1 --format=%s)"
  fi
}

status() {
  local out="" porcelain
  porcelain=$(git status --porcelain=v2 --branch 2>/dev/null) || return 0
  grep -q '^[^#]' <<<"$porcelain" && out+="*"
  grep -qE '^# branch\.ab \+[1-9]' <<<"$porcelain" && out+="⇡"
  [ -e "$state/sync-error" ] && out+="!"
  { rebuild_pending || [ -e "$state/system-pending" ]; } && out+="${out:+ }reload"
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
  built)
    git rev-parse HEAD >"$state/built"
    rm -f "$state/system-pending" "$state/apply-failed"
    ;;
  *)
    echo "usage: dotsync sync|status|why|built" >&2
    exit 2
    ;;
esac
