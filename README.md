# poof

An agent skill that does one task, then deletes its own session. Give it a
task. When the work is delivered, the session's chat transcript and job-list
entry go away, along with a Claude Code background session's worktree. One
log line records what happened.

Use it for errands you don't want cluttering your session list: ship a fix,
answer a question, run a chore.

```
/poof bump the lodash version and open a PR          # Claude Code
$poof bump the lodash version and open a PR          # Codex
```

## Install

**Any agent, through [skills.sh](https://skills.sh):**

```bash
npx skills add kualta/poof -g                        # every detected agent
npx skills add kualta/poof -g -a claude-code codex   # just these two
```

**Claude Code plugin:**

```bash
claude plugin marketplace add kualta/poof
claude plugin install poof@poof
```

Plugin skills are namespaced, so you get `/poof:poof`. If nothing else is
called `/poof`, plain `/poof` works too.

**Codex plugin:**

```bash
codex plugin marketplace add kualta/poof
```

**By hand:** copy `skills/poof` into `~/.claude/skills/` (Claude Code) or
`~/.agents/skills/` (Codex).

Requirements: macOS or Linux, `bash`, `perl`, and `jq`.

## How it works

The agent does the task, then puts the work somewhere that outlives the chat
(a pushed branch, a PR, a file). Its last tool call is
`scripts/poof.sh "<result headline>"`. The script returns at once, and a
detached process in its own process group waits for the session to finish,
then deletes it with the agent's own CLI:

| Where it runs | Waits for | Then |
| --- | --- | --- |
| Claude Code background session | `claude agents` shows it idle and done | `claude stop`, `claude rm`, delete transcript files |
| Claude Code interactive session | you exit | delete transcript files |
| Codex (`codex exec` or the TUI) | the `codex` process exits | `codex delete --force` |
| Codex app-server thread | the turn's `task_complete` event | `codex delete --force` |

Each session leaves one line in `~/.local/state/poof/log` (override the
location with `POOF_STATE_DIR`):

```
2026-11-21T14:59:23Z claude 8473534a deleted: bump-lodash | Opened #42 bumping lodash to 4.17.22
```

## Safety

- **Explicit only.** The agent never runs it on its own. Claude Code sees
  `disable-model-invocation: true`, and Codex sees
  `allow_implicit_invocation: false`.
- **Done, or nothing.** The agent arms it only after delivering the task. A
  Claude Code background job that ends blocked or failed is left alone.
- **Unpushed work survives.** `claude rm` refuses to remove a worktree with
  unpushed commits. Then poof deletes nothing and logs why.
- **Cancel anytime.** `scripts/poof.sh --cancel` from the same session
  disarms it. `--status` tells you whether it's armed.

## Codex notes

The Codex sandbox blocks `ps` and writes outside the workspace, so the agent
asks to run the arm command with escalated permissions. Approve it, or let
your approvals reviewer decide. Codex has no argument substitution, so the
skill reads the task from your message after `$poof`.

## Limits

- Tested end to end in a Claude Code background session and in `codex exec`.
  Interactive Claude Code, the Codex TUI, and Codex app-server threads follow
  the same paths but haven't had a full run yet.
- Your prompt stays in the agent's input history
  (`~/.claude/history.jsonl`, `~/.codex/history.jsonl`).
- Cloud sessions (claude.ai/code, Codex Cloud) aren't supported.

## License

MIT
