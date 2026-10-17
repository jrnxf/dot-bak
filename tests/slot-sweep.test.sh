#!/usr/bin/env bash
# Behavior tests for slot-sweep.sh. Builds the slot-sweep package from this
# checkout (so the Nix wrapper and its shellcheck run too), then sweeps fake
# slots. Nothing here touches ~/.treehouse or ~/firstmate.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v nix >/dev/null || fail "nix is required to build slot-sweep"
pkg=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths --impure --expr "
  let flake = builtins.getFlake \"git+file://$ROOT\";
  in import $ROOT/slot-sweep.nix { pkgs = flake.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}; }
") || fail "slot-sweep.nix failed to build"
SWEEP="$pkg/bin/slot-sweep"

dotfiles_test_tmproot TMP slot-sweep
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name dotfiles-test
git config --global user.email dotfiles-test@example.invalid

TH="$TMP/treehouse" STATE="$TMP/state"
mkdir -p "$STATE"

# make_slot <path>: a repo that ignores build output, with every kind of
# directory the sweep may or may not touch. Its files are made old.
make_slot() {
  dotfiles_git_init_commit "$1"
  printf 'target\n.build\nnode_modules\ndist\n.lavish\n' >"$1/.gitignore"
  mkdir -p "$1/target/debug" "$1/.build" "$1/node_modules/x" "$1/dist" "$1/.lavish" "$1/src/dist" "$1/keep"
  head -c 4096 /dev/zero >"$1/target/debug/big"
  echo x >"$1/.build/f"; echo x >"$1/node_modules/x/f"; echo x >"$1/dist/f"
  echo x >"$1/.lavish/f"; echo x >"$1/src/dist/f"
  echo tracked >"$1/keep/f"
  git -C "$1" add -f keep/f
  git -C "$1" commit -qm keep
  find "$1" -exec touch -d '3 days ago' {} + 2>/dev/null
}

make_slot "$TH/repo-aaa/1/repo"   # idle: swept
make_slot "$TH/repo-aaa/2/repo"   # a task uses it: untouched
make_slot "$TH/repo-bbb/1/repo"   # touched an hour ago: untouched
touch "$TH/repo-bbb/1/repo/src"   # a fresh edit
make_slot "$TH/repo-ccc/1/repo"   # dist is not ignored there: kept
printf 'target\n.build\nnode_modules\n' >"$TH/repo-ccc/1/repo/.gitignore"
git -C "$TH/repo-ccc/1/repo" add .gitignore
git -C "$TH/repo-ccc/1/repo" commit -qm "narrow ignore"
find "$TH/repo-ccc/1/repo" -exec touch -d '3 days ago' {} + 2>/dev/null

printf 'task=x\nworktree=%s\nagent=y\n' "$TH/repo-aaa/2/repo" >"$STATE/x.meta"

out=$(DOTSLOT_TREEHOUSE="$TH" DOTSLOT_STATE="$STATE" "$SWEEP") || fail "slot-sweep failed: $out"

idle=$TH/repo-aaa/1/repo
for d in target .build node_modules dist; do
  [ ! -e "$idle/$d" ] || fail "idle slot kept $d"
done
for p in .lavish/f src/dist/f keep/f README.md .gitignore; do
  [ -e "$idle/$p" ] || fail "idle slot lost $p"
done
pass "idle slot loses only its ignored build directories"

for d in target .build node_modules dist; do
  [ -e "$TH/repo-aaa/2/repo/$d" ] || fail "slot in use lost $d"
done
pass "slot a task uses is untouched"

for d in target .build dist; do
  [ -e "$TH/repo-bbb/1/repo/$d" ] || fail "recently touched slot lost $d"
done
pass "slot touched in the last 24 hours is untouched"

[ -e "$TH/repo-ccc/1/repo/dist" ] || fail "tracked-or-unignored dist was removed"
[ ! -e "$TH/repo-ccc/1/repo/target" ] || fail "ignored target was kept"
pass "a directory git does not ignore is kept"

assert_contains "$out" "removed $idle/target (" "log lacks the removed target"
assert_contains "$out" "freed" "log lacks the bytes freed"
assert_not_contains "$out" "repo-aaa/2" "log mentions the slot in use"
pass "log names what was removed and the bytes freed"

DOTSLOT_TREEHOUSE="$TH" DOTSLOT_STATE="$TMP/nope" "$SWEEP" >/dev/null 2>&1 && fail "sweep ran without a state dir"
[ -e "$TH/repo-ccc/1/repo/dist" ] || fail "state-less run removed something"
pass "no state dir, nothing removed"
