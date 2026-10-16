#!/usr/bin/env bash
# Behavior tests for dotsync.sh. Builds the dotsync package from this checkout
# (so the Nix wrapper and its shellcheck run too), then syncs two fixture
# clones through a local bare remote. Nothing here touches ~/dotfiles or GitHub.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v nix >/dev/null || fail "nix is required to build dotsync"
pkg=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths --impure --expr "
  let flake = builtins.getFlake \"git+file://$ROOT\";
  in import $ROOT/dotsync.nix { pkgs = flake.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}; }
") || fail "dotsync.nix failed to build"
DOTSYNC="$pkg/bin/dotsync"

dotfiles_test_tmproot TMP dotsync
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name dotfiles-test
git config --global user.email dotfiles-test@example.invalid
git config --global init.defaultBranch main

git init -q --bare "$TMP/origin.git"
dotfiles_git_init_commit "$TMP/seed"
git -C "$TMP/seed" push -q "$TMP/origin.git" HEAD:main
git clone -q "$TMP/origin.git" "$TMP/a"
git clone -q "$TMP/origin.git" "$TMP/b"

# run <clone> <command>: dotsync against that clone with its own state dir.
# Notifications are recorded to notes-<clone>, one per line, instead of shown.
cat >"$TMP/notify" <<'SH'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$NOTES"
SH
chmod +x "$TMP/notify"
run() {
  NOTES="$TMP/notes-$1" DOTSYNC_NOTIFY="$TMP/notify" \
    DOTSYNC_REPO="$TMP/$1" DOTSYNC_STATE="$TMP/state-$1" "$DOTSYNC" "$2"
}
# notes <clone>: the notifications since the last call, then forget them.
notes() { cat "$TMP/notes-$1" 2>/dev/null; rm -f "$TMP/notes-$1"; }
commit() { # commit <clone> <file> <content>
  printf '%s\n' "$3" >"$TMP/$1/$2"
  git -C "$TMP/$1" add "$2"
  git -C "$TMP/$1" commit -qm "$1 edits $2"
}
head_of() { git -C "$TMP/$1" rev-parse HEAD; }

# --- push and fast-forward ------------------------------------------------------

commit a one.txt "from a"
assert_contains "$(run a status)" "⇡" "an unpushed commit must show ⇡"
run a sync || fail "sync with a fresh commit should succeed"
[ "$(git -C "$TMP/origin.git" rev-parse main)" = "$(head_of a)" ] || fail "sync must push local commits"
run b sync || fail "sync behind upstream should succeed"
[ "$(head_of b)" = "$(head_of a)" ] || fail "sync must fast-forward to upstream"
pass "sync pushes commits and fast-forwards the other clone"

# --- uncommitted work ------------------------------------------------------------

printf 'draft\n' >"$TMP/b/draft.txt"
assert_contains "$(run b status)" "*" "an uncommitted file must show *"
commit a two.txt "from a"
run a sync
run b sync || fail "unrelated uncommitted work must not block a fast-forward"
[ "$(head_of b)" = "$(head_of a)" ] && [ -e "$TMP/b/draft.txt" ] || fail "fast-forward must keep uncommitted work"
rm "$TMP/b/draft.txt"

printf 'b draft\n' >"$TMP/b/two.txt"
commit a two.txt "a again"
run a sync
run b sync 2>/dev/null && fail "a fast-forward over an edited file must fail"
[ "$(cat "$TMP/b/two.txt")" = "b draft" ] || fail "a blocked sync must leave the edited file alone"
assert_contains "$(run b status)" "!" "a failed sync must show !"
assert_contains "$(run b why)" "uncommitted" "why must explain the failure"
git -C "$TMP/b" checkout -q two.txt
run b sync || fail "sync must succeed once the edit is gone"
assert_not_contains "$(run b status)" "!" "a successful sync must clear !"
pass "uncommitted work is kept, and blocks only a conflicting fast-forward"

# --- diverged ------------------------------------------------------------------

commit a three.txt "from a"
run a sync
commit b four.txt "from b"
run b sync || fail "diverged commits on different files should rebase"
[ "$(git -C "$TMP/origin.git" rev-parse main)" = "$(head_of b)" ] || fail "the rebased commit must be pushed"
git -C "$TMP/b" merge-base --is-ancestor "$(head_of a)" HEAD || fail "the rebase must sit on upstream"
run a sync
pass "diverged commits on different files rebase and push"

commit a five.txt "from a"
run a sync
commit b five.txt "from b"
before=$(head_of b)
run b sync 2>/dev/null && fail "conflicting diverged commits must fail"
[ "$(head_of b)" = "$before" ] || fail "a conflicting rebase must be aborted, leaving the local commit"
[ ! -d "$TMP/b/.git/rebase-merge" ] || fail "no rebase may be left in progress"
assert_contains "$(run b why)" "conflict" "why must name the conflict"
git -C "$TMP/b" reset -q --hard '@{u}'
run b sync
pass "conflicting commits are left alone and reported"

# --- reload marker -------------------------------------------------------------

assert_contains "$(run b status)" "reload" "never rebuilt must show reload"
run b built
[ -z "$(run b status)" ] || fail "a clean, rebuilt, synced repo must print nothing"
commit a notes.txt "docs only"
run a sync && run b sync
[ -z "$(run b status)" ] || fail "a live-linked change must not ask for reload"
commit a home.nix "{ }"
run a sync && run b sync
assert_contains "$(run b status)" "reload" "a pulled .nix change must ask for reload"
pass "reload shows only for changes that need a rebuild"

# --- notifications ---------------------------------------------------------------

notes a >/dev/null; notes b >/dev/null
run a built; run b built
run b sync
[ -z "$(notes b)" ] || fail "a sync that pulls nothing must not notify"

commit a six.txt "from a"
run a sync
[ -z "$(notes a)" ] || fail "a sync that only pushes must not notify"
run b sync
[ "$(notes b)" = "ok|dotfiles up to date|pulled 1 commit: a edits six.txt" ] || fail "a live-linked pull must notify ok with its subject"
run b built

commit a seven.txt "1"; commit a eight.nix "{ }"
run a sync
run b sync
[ "$(notes b)" = "warn|dotfiles pulled, reload to apply|pulled 2 commits, latest: a edits eight.nix" ] \
  || fail "a pull that needs a rebuild must notify warn"
run b built

commit a nine.txt "from a"; run a sync
commit b ten.txt "from b"
run b sync
[ "$(notes b)" = "ok|dotfiles up to date|pulled 1 commit: a edits nine.txt" ] \
  || fail "after a rebase, only the upstream commits count as pulled"
run a sync; notes a >/dev/null

commit a eleven.txt "from a"; run a sync
commit b eleven.txt "from b"
run b sync 2>/dev/null
assert_contains "$(notes b)" "fail|dotfiles sync failed|local and upstream commits conflict" "a new failure must notify fail"
run b sync 2>/dev/null
[ -z "$(notes b)" ] || fail "the same failure must not notify again"
git -C "$TMP/b" reset -q --hard '@{u}'
run b sync
pass "notifications say what a sync did, and each failure once"

git -C "$TMP/b" remote set-url origin "$TMP/missing.git"
run b sync 2>/dev/null && fail "a fetch from a missing remote must fail"
[ -z "$(notes b)" ] || fail "a fetch failure (offline) must not notify"
assert_contains "$(run b why)" "fetch failed" "why must still name the fetch failure"
pass "an offline fetch fails quietly"
