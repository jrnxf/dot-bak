#!/usr/bin/env bash
# slot-sweep: free the build output idle treehouse worktree slots leave behind.
#
# Firstmate workers run in pooled worktrees at ~/.treehouse/<repo>-<hash>/<slot>/<repo>.
# A finished slot keeps its git-ignored target/, .build/, node_modules/ and dist/,
# which add up to many GB. For every slot that no firstmate task uses (no
# state/*.meta line `worktree=<slot>`) and that nothing touched in the last 24
# hours, this removes those four top-level directories, and only when git says
# they are ignored. Tracked files and everything else stay.
#
# DOTSLOT_TREEHOUSE, DOTSLOT_STATE and DOTSLOT_MIN_AGE_MIN (minutes) override the
# defaults, for tests.
set -uo pipefail

treehouse=${DOTSLOT_TREEHOUSE:-$HOME/.treehouse}
state=${DOTSLOT_STATE:-$HOME/firstmate/state}
min_age=${DOTSLOT_MIN_AGE_MIN:-1440}
targets=(target .build node_modules dist)

# Paths that tasks still use. Without a readable state dir nothing proves a slot
# idle, so stop rather than guess.
[ -d "$state" ] || { echo "slot-sweep: no state dir at $state, nothing removed" >&2; exit 1; }
in_use=$(cat "$state"/*.meta 2>/dev/null | sed -n 's/^worktree=//p' | sed 's:/*$::')

total=0
for slot in "$treehouse"/*/*/*; do
  [ -d "$slot" ] || continue
  slot=${slot%/}
  grep -Fxq -- "$slot" <<<"$in_use" && continue
  git -C "$slot" rev-parse --git-dir >/dev/null 2>&1 || continue

  # Recently touched: the slot's own entries (the build dirs do not count, a
  # build writes into them), or the repo's HEAD and index.
  gitdir=$(git -C "$slot" rev-parse --absolute-git-dir)
  find_args=(-mindepth 0 -maxdepth 1 -mmin "-$min_age")
  for t in "${targets[@]}"; do find_args+=(! -name "$t"); done
  recent=$(find "$slot" "${find_args[@]}" -print -quit 2>/dev/null)
  [ -n "$recent" ] || recent=$(find "$gitdir/HEAD" "$gitdir/index" -mmin "-$min_age" -print -quit 2>/dev/null)
  [ -z "$recent" ] || continue

  for t in "${targets[@]}"; do
    dir=$slot/$t
    [ -d "$dir" ] && [ ! -L "$dir" ] || continue
    git -C "$slot" check-ignore -q -- "$t" || continue
    bytes=$(du -sb -- "$dir" | cut -f1)
    if rm -rf -- "$dir"; then
      echo "slot-sweep: removed $dir ($bytes bytes)"
      total=$((total + bytes))
    else
      echo "slot-sweep: could not remove $dir" >&2
    fi
  done
done
echo "slot-sweep: freed $total bytes"
