#!/bin/bash
# Regenerates skills/self-destruct-after from skills/poof, the single source.
# CI runs this and fails if it changes anything.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/skills/poof"
dst="$root/skills/self-destruct-after"

rm -rf "$dst"
mkdir -p "$dst/scripts" "$dst/agents"
cp -p "$src/scripts/poof.sh" "$dst/scripts/poof.sh"

sed -e 's/^name: poof$/name: self-destruct-after/' \
  -e 's|^description: Do a task|description: Alias of poof. Do a task|' \
  -e 's|as /poof <task> in Claude Code or \$poof <task> in Codex|as /self-destruct-after <task> in Claude Code or $self-destruct-after <task> in Codex|' \
  -e 's/^# poof$/# self-destruct-after (alias of poof)/' \
  "$src/SKILL.md" >"$dst/SKILL.md"

sed -e 's/display_name: "poof"/display_name: "self-destruct-after"/' \
  "$src/agents/openai.yaml" >"$dst/agents/openai.yaml"
