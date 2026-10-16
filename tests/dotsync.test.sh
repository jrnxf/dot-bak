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
# Applies go to a fake rebuild.sh that logs each call to applies-<clone> and
# does what apply-mode says: succeed, leave a system change, or fail.
cat >"$TMP/notify" <<'SH'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$NOTES"
SH
cat >"$TMP/apply" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$APPLIES"
case $(cat "$APPLY_MODE" 2>/dev/null) in
  system) echo "activating" >&2; echo system ;;
  fail) echo "activating" >&2; echo "error: attribute 'nope' missing" >&2; exit 1 ;;
  *) echo "activating" >&2 ;;
esac
SH
chmod +x "$TMP/notify" "$TMP/apply"
run() {
  NOTES="$TMP/notes-$1" DOTSYNC_NOTIFY="$TMP/notify" \
    APPLIES="$TMP/applies-$1" APPLY_MODE="$TMP/apply-mode" DOTSYNC_APPLY="$TMP/apply" \
    DOTSYNC_REPO="$TMP/$1" DOTSYNC_STATE="$TMP/state-$1" "$DOTSYNC" "$2"
}
# applies <clone>: how many applies ran since the last call, then forget them.
applies() { grep -c . "$TMP/applies-$1" 2>/dev/null || echo 0; rm -f "$TMP/applies-$1"; }
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

# --- apply --------------------------------------------------------------------

# Every sync above applied once: neither clone had been built yet.
applies a >/dev/null; applies b >/dev/null
run b built
[ -z "$(run b status)" ] || fail "a clean, rebuilt, synced repo must print nothing"
commit a notes.txt "docs only"
run a sync && run b sync
[ "$(applies b)" = 0 ] || fail "a live-linked change must not apply"
[ -z "$(run b status)" ] || fail "a live-linked change must not ask for reload"
commit a home.nix "{ }"
run a sync
[ "$(applies a)" = 1 ] || fail "a committed .nix change must apply where it was committed"
run b sync
[ "$(cat "$TMP/applies-b")" = "--auto" ] || fail "a pulled .nix change must apply with --auto"
applies b >/dev/null
[ -z "$(run b status)" ] || fail "an applied change must not ask for reload"
run b sync
[ "$(applies b)" = 0 ] || fail "an applied HEAD must not apply again"
pass "a change that needs a rebuild applies itself, once"

echo system >"$TMP/apply-mode"
commit a configuration.nix "{ }"
run a sync && run b sync
assert_contains "$(run b status)" "reload" "a waiting system change must show reload"
run b built
[ -z "$(run b status)" ] || fail "a reload must clear the system marker"
pass "a system change waits for reload"

echo fail >"$TMP/apply-mode"
notes b >/dev/null
commit a home.nix "{ broken }"
run a sync 2>/dev/null; run b sync 2>/dev/null && fail "a failed apply must fail the sync"
assert_contains "$(notes b)" "fail|dotfiles sync failed|couldn't apply the config: error: attribute 'nope' missing" \
  "a failed apply must notify with its last error line"
assert_contains "$(run b status)" "!" "a failed apply must show !"
assert_contains "$(run b status)" "reload" "a failed apply must still show reload"
applies b >/dev/null
run b sync 2>/dev/null && fail "the same HEAD must keep failing"
[ "$(applies b)" = 0 ] || fail "a HEAD that failed to apply must not retry every minute"
[ -z "$(notes b)" ] || fail "a failed apply must notify once"
rm -f "$TMP/apply-mode"
commit a home.nix "{ fixed }"
run a sync; run b sync || fail "a new commit must retry the apply"
assert_not_contains "$(run b status)" "!" "a successful apply must clear !"
pass "a failed apply is reported once and retried on the next commit"

# --- notifications ---------------------------------------------------------------

notes a >/dev/null; notes b >/dev/null
run a built; run b built
run b sync
[ -z "$(notes b)" ] || fail "a sync that pulls nothing must not notify"

commit a six.txt "from a"
run a sync
[ -z "$(notes a)" ] || fail "a sync that only pushes must not notify"
run b sync
[ "$(notes b)" = "ok|dotfiles synced|a edits six.txt" ] || fail "a live-linked pull must notify ok with its subject"
run b built

commit a seven.txt "1"; commit a eight.nix "{ }"
run a sync
run b sync
[ "$(notes b)" = "ok|dotfiles synced and rebuilt|2 commits, latest: a edits eight.nix" ] \
  || fail "a pull applied in full must notify ok"

echo system >"$TMP/apply-mode"
commit a nine.nix "{ }"
run a sync
[ "$(notes a)" = "warn|dotfiles synced, run reload|a edits nine.nix" ] \
  || fail "a committed system change must notify warn"
commit a ten.nix "{ }"
run a sync
run b sync
[ "$(notes b)" = "warn|dotfiles synced, run reload|2 commits, latest: a edits ten.nix" ] \
  || fail "a pulled system change must notify warn"
rm -f "$TMP/apply-mode"
notes a >/dev/null; run a built; run b built

commit a nine.txt "from a"; run a sync
commit b ten.txt "from b"
run b sync
[ "$(notes b)" = "ok|dotfiles synced|a edits nine.txt" ] \
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

# --- rewritten history --------------------------------------------------------------

# rewrite_upstream: force-push origin back to the parent of its newest commit,
# the way a captain drops test commits from GitHub.
rewrite_upstream() {
  git -C "$TMP/a" fetch -q
  git -C "$TMP/origin.git" update-ref refs/heads/main "$(git -C "$TMP/origin.git" rev-parse main~1)"
}

git -C "$TMP/b" remote set-url origin "$TMP/origin.git"
run a sync; run b sync
git -C "$TMP/a" commit -q --allow-empty -m "test commit"
run a sync; run b sync
run a built; run b built; notes b >/dev/null
rewrite_upstream
want=$(git -C "$TMP/origin.git" rev-parse main)
run b sync || fail "a rewrite with no local commits should be followed"
[ "$(head_of b)" = "$want" ] || fail "a machine with no commits of its own must end at the new upstream"
[ "$(git -C "$TMP/origin.git" rev-parse main)" = "$want" ] || fail "following a rewrite must push nothing"
[ "$(notes b)" = "ok|dotfiles synced|followed rewritten history" ] || fail "following a rewrite must notify ok"
assert_not_contains "$(run b status)" "!" "following a rewrite must not fail"
run a sync || fail "the machine that made the dropped commit should follow too"
[ "$(head_of a)" = "$want" ] || fail "every machine must end at the rewritten upstream"
pass "a rewrite with no local commits is followed, not pushed back"

git -C "$TMP/a" commit -q --allow-empty -m "test commit"
run a sync; run b sync
run a built; run b built
rewrite_upstream
commit b own.txt "mine"
run b sync || fail "a rewrite with a local commit should rebase it"
[ "$(git -C "$TMP/origin.git" rev-parse main)" = "$(head_of b)" ] || fail "the local commit must be pushed"
[ "$(git -C "$TMP/b" log -1 --format=%s)" = "b edits own.txt" ] || fail "the local commit must be kept"
git -C "$TMP/origin.git" merge-base --is-ancestor "$want" main || fail "the push must never discard upstream history"
run a sync; run a built; run b built
pass "a rewrite with a local commit keeps it and never force-pushes"

# An uncommitted edit to a file the rewrite does not change is kept.
git -C "$TMP/a" commit -q --allow-empty -m "test commit"
run a sync; run b sync
rewrite_upstream
printf 'wip\n' >>"$TMP/b/one.txt"
run b sync || fail "an edit to an unrelated file must not block following"
[ "$(head_of b)" = "$(git -C "$TMP/origin.git" rev-parse main)" ] || fail "following must end at the new upstream"
grep -q wip "$TMP/b/one.txt" || fail "following a rewrite must keep uncommitted work"
git -C "$TMP/b" checkout -q one.txt
run a sync; run a built; run b built

# An uncommitted edit to a file the rewrite changes makes it refuse cleanly.
commit a rewritten.txt "v1"
run a sync; run b sync
commit a rewritten.txt "v2"
run a sync; run b sync
printf 'wip\n' >"$TMP/b/rewritten.txt"
before=$(head_of b)
rewrite_upstream
git -C "$TMP/origin.git" update-ref refs/heads/main "$(git -C "$TMP/origin.git" rev-parse main~1)"
run b sync 2>/dev/null && fail "following over an edited file must fail"
[ "$(head_of b)" = "$before" ] || fail "a refused follow must leave HEAD alone"
[ "$(cat "$TMP/b/rewritten.txt")" = wip ] || fail "a refused follow must leave the edited file alone"
assert_contains "$(run b why)" "rewritten history" "why must explain the refusal"
git -C "$TMP/b" checkout -q rewritten.txt 2>/dev/null || rm -f "$TMP/b/rewritten.txt"
run b sync || fail "following must succeed once the edit is gone"
[ "$(head_of b)" = "$(git -C "$TMP/origin.git" rev-parse main)" ] || fail "following must end at the new upstream"
pass "uncommitted work survives a rewrite, or the follow is refused"
