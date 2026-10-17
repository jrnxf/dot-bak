#!/usr/bin/env bash
# Checks home/.claude/hooks/notify.sh, the Stop and Notification hook that
# replaces Claude Code's built-in Ghostty notifications: workers never notify,
# the firstmate supervisor notifies only on a turn with content, every other
# session always notifies. CLAUDE_NOTIFY_OUT makes the hook print instead of
# writing to a terminal.
# Run this before committing a change to the hook.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK="$ROOT/home/.claude/hooks/notify.sh"
SETTINGS="$ROOT/home/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found for the notify hook checks"; exit 0; }

dotfiles_test_tmproot tmp notify-hook
out="$tmp/out"
transcript="$tmp/transcript.jsonl"

# transcript <text>: a turn whose last text reply is <text>, followed by a
# tool-only record that must not count as the reply.
transcript() {
  printf '{"type":"user","message":{"content":"hi"}}\n{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"x"}]}}\n' "$1" >"$transcript"
}

# fire <cwd> <worker 0|1> [event] [message]: run the hook, print what it sent.
fire() {
  : >"$out"
  local json
  json=$(printf '{"hook_event_name":"%s","cwd":"%s","transcript_path":"%s","message":"%s"}' \
    "${3:-Stop}" "$1" "$transcript" "${4:-}")
  if [ "$2" = 1 ]; then
    printf '%s' "$json" | env FM_TASK_INBOX=/x CLAUDE_NOTIFY_OUT="$out" bash "$HOOK"
  else
    printf '%s' "$json" | env -u FM_TASK_INBOX CLAUDE_NOTIFY_OUT="$out" bash "$HOOK"
  fi
  cat "$out"
}

transcript "Captain, shipshape."
[ -z "$(fire /Users/jrnxf/firstmate 1)" ] || fail "worker must never notify"
[ -z "$(fire /tmp 1 Notification 'needs input')" ] || fail "worker must not notify on Notification either"
[ -z "$(fire /Users/jrnxf/firstmate 0)" ] || fail "supervisor must stay quiet on Captain, shipshape."
assert_contains "$(fire /tmp 0)" "Claude Code" "other sessions notify on every turn end"
assert_contains "$(fire /tmp 0 Notification 'needs input')" "needs input" "Notification hook carries the message"
transcript "Done: PR ready"
assert_contains "$(fire /Users/jrnxf/firstmate 0)" "Done: PR ready" "supervisor notifies on a turn with content"
assert_contains "$(fire /Users/jrnxf/firstmate/sub 0)" "Done: PR ready" "supervisor rule covers subdirectories"
pass "notify hook decides per session kind"

for event in Stop Notification; do
  count=$(jq --arg e "$event" '[.hooks[$e][]?.hooks[]? | select(.command == "bash '"'"'/Users/jrnxf/.claude/hooks/notify.sh'"'"'")] | length' "$SETTINGS")
  [ "$count" = 1 ] || fail "settings.json should run notify.sh exactly once on $event, got $count"
done
channel=$(jq -r '.preferredNotifChannel' "$SETTINGS")
[ "$channel" = "notifications_disabled" ] || fail "built-in notification channel must stay off, got $channel"
pass "settings.json wires notify.sh and disables the built-in channel"
