---
name: poof
description: Delete this agent session (its chat transcript and job entry), right away or once a given task is delivered. Works in Claude Code and Codex. Use only when the person invokes it explicitly, as /poof [task] in Claude Code or $poof [task] in Codex.
argument-hint: [task]
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/poof.sh *)
---

# poof

Do the task below the way you'd do any other, following every instruction
that normally applies (AGENTS.md, CLAUDE.md, memory, repo rules). When it's
delivered, this session deletes itself.

Task: $ARGUMENTS

If the line above literally reads `$ARGUMENTS` or is empty, the task is
whatever the person wrote along with invoking this skill.

**No task means delete now.** If the person invoked the skill with nothing
else, they want this session gone as it stands. Don't ask for a task, and
don't start new work. Skip "Before you finish" and arm it straight away with a
headline that sums up what the session did. Use "ended with no task" if it did
nothing. If you know of work from this session that exists only here
(uncommitted changes, an answer that wasn't saved), name it in your final
message before you stop.

Once the session is deleted, its chat is gone. Anything that exists only in
the chat is lost with it.

## Before you finish

1. Put the work somewhere that outlives the chat: commit and push code, open
   or merge the PR, write files to disk, or post where you were asked. If the
   deliverable is an answer, put it in the result headline when it fits on
   one line. When it doesn't, write it to a file and give that file's path.
2. Run the sanity check you'd normally run.

## Arm it as your last tool call

Arm it only when the task is delivered, or at once when there's no task. If
you're blocked, need input, or failed, don't arm it: report as usual, and the
session stays.

The script is `scripts/poof.sh` in this skill's folder. Pass it a one-line
result headline:

- **Claude Code:** `"${CLAUDE_SKILL_DIR}/scripts/poof.sh" "<result headline>"`
- **Codex:** `"<this skill's folder>/scripts/poof.sh" "<result headline>"`.
  Request escalated permissions to run it outside the sandbox. It has to
  inspect processes and, later, run `codex delete`. Justification: "Delete
  this session after it finishes, as the person asked."

The command returns at once, and a detached process does the rest:

- **Claude Code, background session:** waits until the session is idle and
  its job is marked done. Then runs `claude stop` and `claude rm`, and deletes
  the transcript files. `claude rm` refuses when the worktree has unpushed
  work, and then nothing is deleted.
- **Claude Code, interactive:** waits until the person exits, then deletes
  the transcript files.
- **Codex:** waits until the `codex` process exits (`codex exec`, or the
  person quitting the TUI), then runs `codex delete --force`. App-server
  threads (desktop app, `codex agents`) are deleted once the turn completes.

The headline is appended to `~/.local/state/poof/log`, the only record that
remains.

After arming, write your final message and stop, with no more tool calls. In
a Claude Code background session, include the `result:` line, which marks
the job done. If the person replies before deletion, the script waits for
that turn to finish too. If they ask to keep the session, run the script with
`--cancel` instead of a headline.
