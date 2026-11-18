---
name: codex-delegate
description: Clear a repository's Beads backlog cycle by cycle with Claude Code as the primary agent that picks, plans, reviews, fixes, and merges, and Codex CLI as the secondary agent that implements each plan through compound-engineering:lfg up to an open pull request; each cycle runs through the codex-lfg skill. Explicit invocation only; run before the matching long-running goal.
---

Clear every actionable non-epic issue from this repository's Beads tracker, one cycle at a time. Claude is the primary agent: it chooses the work, plans it, judges every result, and owns every merge. Codex CLI is the secondary agent: it only implements a plan Claude wrote and opens a pull request. Never ask the user anything; when a choice arises take your recommended option and record it in the issue notes and the PR body. Write English in code, commits, PRs, and tracker fields.

This procedure runs on Claude Code. On any other host, stop before any tracker or git write and tell the user to run it from Claude Code. It needs the `codex-lfg` skill installed beside this one, the `compound-engineering` plugin installed for both Claude Code and Codex, `bd` and `gh` working, and `codex` on PATH.

Parameters, overridable by the goal or the user:
- `CODEX_MODEL`: empty by default, so Codex uses the `model` from its config (`~/.codex/config.toml`). When the goal or the user names a model, pass it to every `codex-lfg` call as `CODEX_MODEL=<model>`.
- `CODEX_EFFORT`: empty by default, so `codex-lfg` chooses the effort by its own rules. When the goal or the user names an effort, pass it to every call as `CODEX_EFFORT=<effort>`; otherwise pass `CODEX_EFFORT=xhigh` for a set where any issue already has `codex_delegate_attempts` of 1.

Each cycle's plan, Codex delegation, handoff, review, fixes, checks, merge, sync, and issue closure are the `codex-lfg` procedure. This skill picks the work, owns the attempt count, and decides when to stop.

## Preflight (once)

Confirm that the Skill tool lists `codex-lfg`; each cycle invokes it with its arguments, so do not invoke it here. If it is not listed, stop and tell the user to install `codex-lfg` at a version whose Claude copy omits `disable-model-invocation`. Never substitute reading its file for invoking it.

Run `bd prime`, `bd ready --json`, `gh auth status`, `codex --version`, and `git status --short`. Resolve the default branch with `gh repo view --json defaultBranchRef`. Stop and report if any probe fails or the local default branch has unpushed commits. A dirty working tree stops the run unless the current branch is the branch of an issue found in Recovery below; `codex-lfg` commits those leftover changes when it resumes that branch.

## Recovery (once, before the first new cycle)

Every issue this loop hands to `codex-lfg` carries `codex_delegate_branch` metadata, so an interrupted run leaves a trail. List it with `bd list --status=in_progress --has-metadata-key codex_delegate_branch --json`, and read each issue with `bd show <id> --json`. An issue with `codex_delegate_branch` but no `codex_lfg_branch` comes from an earlier version of this skill; `codex-lfg` resumes its `codex_delegate_branch`. Group issues that share a branch (`codex_lfg_branch`, else `codex_delegate_branch`) and run each group through step 2 of One cycle; `codex-lfg` resumes it at its first unfinished step, merges it, and closes it.

Leave `in_progress` issues without `codex_delegate_branch` alone; another agent, or an interactive `codex-lfg` run, owns them. Report each recovered issue and the step it resumed at in the final report. Then switch to the default branch and `git pull --ff-only`.

## One cycle

1. **Pick.** From `bd ready --json`, take the highest-priority non-epic issue that is not a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`). Add other ready issues only when they share its parent epic and the same code area, and keep the set small enough for one reviewable PR. Skip any issue whose `codex_delegate_attempts` metadata is 2 or more. Mark each issue as this loop's with `bd update <id> --set-metadata codex_delegate_branch=<branch>`, where `<branch>` is the branch `codex-lfg` derives for the set (its `codex_lfg_branch` when one is recorded, otherwise `codex-lfg/<first issue id>` normalized as `codex-lfg` describes), and read it back with `bd show <id> --json`. Do not claim the issues; `codex-lfg` claims them.
2. **Run `codex-lfg`.** Invoke it through the Skill tool with the issue ids followed by `merge unattended` and the parameter arguments above, for example `bd-12 bd-13 merge unattended`. Follow it to its report. Never wait on a human.
3. **Record.** Keep its report for the final report. The cycle succeeded when every issue in the set reads `closed` with `bd show <id> --json`; anything else is a failed cycle under the rules below.

## Loop and failure rules

Start the next cycle immediately. A cycle that cannot finish adds one to each member's `codex_delegate_attempts` metadata and appends the cause and PR to its notes with `bd update <id> --append-notes`. Below 2 attempts, make sure the issue is open and unclaimed (`--status open --assignee ''`; `codex-lfg` normally released it already) so a later cycle retries it; at 2, set it `blocked` and leave it for a person. The loop continues with independent work. The attempt count lives in the tracker, not in context, so it survives compaction and restarts. The Codex retry inside `codex-lfg` is part of one attempt.

Stop when `bd ready` offers no non-epic issue other than human gates and every issue this loop claimed is closed or blocked with a recorded cause, or when trunk is red for a reason no cycle can fix.

## Final report

List each issue Recovery resumed and the step it resumed at. List each cycle from its `codex-lfg` report: bead ids, plan path, Codex model and effort, Codex outcome (success, retried, or replaced by Claude), PR number, findings fixed by Claude, and merge SHA. Then list every remaining open non-epic issue with the reason it stays, every blocked issue with its cause, and every human gate with the action a person must take.
