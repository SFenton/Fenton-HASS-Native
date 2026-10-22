#!/usr/bin/env bash
# Commit everything tracked or new (minus .gitignore), push the branch and optionally open the PR.
# Replaces the hand-built trailer, `git add -A`, push and `gh pr create` / assignee sequence.
#
# Usage: tools/ship.sh "Subject line" [--body-file FILE | --body TEXT] [--pr] [--draft] [--base main] [--no-push]
#   Refuses on main/master and when the change includes env files, keys or provisioning profiles.
#   SHIP_COAUTHOR  trailer identity (default "Claude Sonnet 5.5 <noreply@anthropic.com>")
#   SHIP_ASSIGNEE  PR assignee (default SFenton)
#   Nothing merges: the coordinator merges (AGENTS.md). Without --pr only the branch is pushed.
set -euo pipefail

SUBJECT="${1:-}"
[[ -n "$SUBJECT" && "$SUBJECT" != -* ]] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift
BODY=""; PR=0; DRAFT=0; BASE="main"; PUSH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body) BODY="$2"; shift 2 ;;
    --body-file) BODY="$(cat "$2")"; shift 2 ;;
    --pr) PR=1; shift ;;
    --draft) DRAFT=1; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --no-push) PUSH=0; shift ;;
    *) echo "ship: unknown option $1" >&2; exit 2 ;;
  esac
done

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "$BRANCH" in
  main|master|HEAD) echo "ship: refusing to commit on '$BRANCH'; make a lane first (tools/lane_new.sh)" >&2; exit 1 ;;
esac

git add -A
if BAD="$(git diff --cached --name-only | grep -E '(^|/)(\.env[^/]*|[^/]*\.env|[^/]*\.p12|[^/]*\.p8|[^/]*\.mobileprovision)$' | grep -v '\.env\.example$' || true)" && [[ -n "$BAD" ]]; then
  git reset -q
  echo "ship: refusing, these must never be committed:" >&2; echo "$BAD" >&2; exit 1
fi

COAUTHOR="${SHIP_COAUTHOR:-Claude Sonnet 5.5 <noreply@anthropic.com>}"
if git diff --cached --quiet; then
  echo "ship: nothing to commit"
else
  git commit -q -m "$SUBJECT" -m "Co-Authored-By: $COAUTHOR"
  echo "committed $(git rev-parse --short HEAD) on $BRANCH: $SUBJECT"
fi

[[ $PUSH == 1 ]] || exit 0
git push -q -u origin "$BRANCH"
echo "pushed $BRANCH"

if [[ $PR == 1 ]]; then
  FOOTER="🤖 Generated with [Claude Code](https://claude.com/claude-code)"
  ARGS=(pr create --base "$BASE" --head "$BRANCH" --title "$SUBJECT" --body "${BODY:+$BODY

}$FOOTER" --assignee "${SHIP_ASSIGNEE:-SFenton}")
  [[ $DRAFT == 1 ]] && ARGS+=(--draft)
  gh "${ARGS[@]}"
fi
