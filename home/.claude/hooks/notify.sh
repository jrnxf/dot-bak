#!/bin/bash
# Desktop notification for Claude Code's Stop and Notification hooks. It
# replaces the built-in "preferredNotifChannel": "ghostty", which notified on
# every finished turn of every session, firstmate's workers included.
#
# Per event:
#   - firstmate worker (FM_TASK_INBOX set): never notify.
#   - firstmate supervisor (cwd under ~/firstmate): notify only when the turn's
#     last assistant message has content, i.e. is not exactly
#     "Captain, shipshape.".
#   - any other session: notify.
#
# A hook has no tty on stdout, and Claude may have no controlling terminal for
# it either, so this walks up the process tree to the first ancestor that owns
# a tty (Claude itself) and writes the escape sequences to that device.
set -u

input=$(cat 2>/dev/null || true)

[ -z "${FM_TASK_INBOX:-}" ] || exit 0

field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

event=$(field .hook_event_name)
cwd=$(field .cwd)
[ -n "$cwd" ] || cwd=$PWD

title="Claude Code"
body="Turn finished"

case "$event" in
  Notification)
    msg=$(field .message)
    [ -z "$msg" ] || body=$msg
    ;;
  *)
    case "$cwd" in
      /Users/jrnxf/firstmate | /Users/jrnxf/firstmate/*)
        transcript=$(field .transcript_path)
        [ -r "$transcript" ] || exit 0
        # Last assistant record with text. Tool-use-only records are skipped.
        last=$(jq -rs '
          [ .[] | select(.type == "assistant")
            | [ .message.content[]? | select(.type == "text") | .text ] | join("\n")
            | select(length > 0) ] | last // empty
        ' "$transcript" 2>/dev/null)
        trimmed=$(printf '%s' "$last" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        { [ -z "$trimmed" ] || [ "$trimmed" = "Captain, shipshape." ]; } && exit 0
        title="Firstmate"
        body=$(printf '%s' "$trimmed" | head -n 1 | cut -c1-120)
        ;;
    esac
    ;;
esac

# Test hook: print instead of writing to a terminal.
if [ -n "${CLAUDE_NOTIFY_OUT:-}" ]; then
  printf '%s | %s\n' "$title" "$body" >>"$CLAUDE_NOTIFY_OUT"
  exit 0
fi

pid=$$
dev=
while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
  t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  case "$t" in
    '' | '?' | '??' | '-') ;;
    *)
      if [ -w "/dev/$t" ]; then
        dev=/dev/$t
        break
      fi
      ;;
  esac
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
done
[ -n "$dev" ] || exit 0

# Escape sequences must not contain control characters from the message.
clean() { printf '%s' "$1" | tr -d '\000-\037;' ; }
# OSC 777 desktop notification (Ghostty), then a plain bell.
printf '\033]777;notify;%s;%s\a\a' "$(clean "$title")" "$(clean "$body")" >"$dev" 2>/dev/null || true
exit 0
