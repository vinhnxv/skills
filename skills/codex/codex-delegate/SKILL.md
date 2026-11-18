---
name: codex-delegate
description: Clear a repository's Beads backlog cycle by cycle with Claude Code as the coordinator that picks, plans, triages reviews, and merges, and a worker agent (Codex CLI by default, Claude Sonnet when chosen) that implements each plan through compound-engineering:lfg up to an open pull request; each cycle runs through the codex-lfg skill, several at once when Claude Code runs inside an Orca terminal. Explicit invocation only; run before the matching long-running goal.
---

Clear every actionable non-epic issue from this repository's Beads tracker, cycle by cycle. Claude is the coordinator: it chooses the work, plans it, triages every review, and owns every merge. The worker only implements a plan and the fixes the coordinator sends, and opens a pull request. Never ask the user anything; when a choice arises take your recommended option and record it in the issue notes and the PR body. Write English in code, commits, PRs, and tracker fields.

This procedure runs on Claude Code. On any other host, stop before any tracker or git write and tell the user to run it from Claude Code. It needs the `codex-lfg` skill installed beside this one, the `compound-engineering` plugin installed for both Claude Code and Codex, and `bd` and `gh` working. It needs `codex` on PATH only when a cycle runs a Codex worker, and Orca only for the Orca backend.

Parameters, overridable by the goal or the user:
- `VIA`: `auto` unless the goal or the user names `orca` or `exec`.
- `PARALLEL`: the most cycles in flight at once, 2 by default. It applies only to the Orca backend; exec runs one cycle at a time.
- The run defaults for each cycle's agents: `worker` (`codex` or `sonnet`), `WORKER_MODEL`, `WORKER_EFFORT`, and `REVIEWER_MODEL`. Empty unless the goal or the user names one, so `codex-lfg` applies its own defaults. `CODEX_MODEL` and `CODEX_EFFORT` are accepted as `WORKER_MODEL` and `WORKER_EFFORT`.

A cycle's choice of worker, model, effort, and reviewer model resolves in this order. An issue's own pinned choice, which `codex-lfg` documents, comes first. The latest choice the user sent during this run comes next, then the run default. Pass `WORKER_EFFORT=xhigh` for a set where any issue already has `codex_delegate_attempts` of 1 and no effort was chosen.

Each cycle's plan, delegation, review loop, checks, merge, sync, issue closure, and cleanup are the `codex-lfg` procedure. This skill picks the work, owns the attempt count, schedules the cycles, and decides when to stop.

## Preflight (once)

Confirm that the Skill tool lists `codex-lfg`; each cycle invokes it with its arguments, so do not invoke it here. If it is not listed, stop and tell the user to install `codex-lfg` at a version whose Claude copy omits `disable-model-invocation`. Never substitute reading its file for invoking it.

Choose the backend before Recovery, Pick, any tracker write, or any checkout change. With `exec`, the backend is exec. Otherwise run these probes:
- `orca status --json` succeeds, and its `result` has `caller.orcaSessionId`, `app.running` true, and `runtime.reachable` true.
- `ORCA_TERMINAL_HANDLE` is set.
- `orca agent hooks status` reports the Claude Code hooks enabled.

When all pass, the backend is Orca. Otherwise `auto` means exec, and `orca` stops the run with zero tracker and git writes, naming the failed probe. Print one line naming the backend and the reason. With Orca, load Orca's guide once with `orca skills get orchestration` and create this run's Orca Run with `orca orchestration run-create --objective "codex-delegate" --json`. Every cycle shares that Run.

Run `bd prime`, `bd ready --json`, `gh auth status`, and `git status --short`. Run `codex --version` before the first cycle that resolves to a Codex worker. Resolve the default branch with `gh repo view --json defaultBranchRef`. Stop and report if any probe fails or the local default branch has unpushed commits. A dirty working tree stops the run unless the current branch is the branch of an issue found in Recovery below; `codex-lfg` commits those leftover changes when it resumes that branch.

## Run state

This run's defaults and the user's latest mid-run choice live in `codex-delegate/run.json` under `git rev-parse --git-common-dir`. The file records a run id, the start time, the backend, the Orca Run id, the run defaults, and the latest choice with when it was given. When Recovery finds issues of an interrupted run, keep the file and continue that run, rebinding its Orca Run. Otherwise replace it with a new run. When the user names a different worker, model, effort, or reviewer model during the run, write it to the file at once. It applies from the next set to start, and the file keeps it through compaction and restarts.

## Recovery (once, before the first new cycle)

Every issue this loop hands to `codex-lfg` carries `codex_delegate_branch` metadata, so an interrupted run leaves a trail. List it with `bd list --status=in_progress --has-metadata-key codex_delegate_branch --json`, and read each issue with `bd show <id> --json`. An issue with `codex_delegate_branch` but no `codex_lfg_branch` comes from an earlier version of this skill; `codex-lfg` resumes its `codex_delegate_branch`. Group issues that share a branch (`codex_lfg_branch`, else `codex_delegate_branch`) and run each group through step 2 of One cycle; `codex-lfg` resumes it at its first unfinished step and reattaches to a worker still running.

Leave `in_progress` issues without `codex_delegate_branch` alone; another agent, or an interactive `codex-lfg` run, owns them. Report each recovered issue and the step it resumed at in the final report. Then switch to the default branch and `git pull --ff-only`.

## One cycle

1. **Pick.** From `bd ready --json`, take the highest-priority non-epic issue that is not a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`). Skip any issue whose `codex_delegate_attempts` metadata is 2 or more. Add other ready issues only when they share its parent epic and the same code area and resolve to the same agent choices, and keep the set small enough for one reviewable PR. While other cycles are in flight, a new set must not share a parent epic with any of them, and its code area must not overlap theirs. Judge the area from the issue text and the repository layout. Mark each issue as this loop's with `bd update <id> --set-metadata codex_delegate_branch=<branch>`, where `<branch>` is the branch `codex-lfg` derives for the set (its `codex_lfg_branch` when one is recorded, otherwise `codex-lfg/<first issue id>` normalized as `codex-lfg` describes), and read it back with `bd show <id> --json`. Record the set's area judgment and its resolved choices, each with its source, with `bd update <id> --append-notes`. Do not claim the issues; `codex-lfg` claims them.
2. **Run `codex-lfg`.** Invoke it through the Skill tool with the issue ids followed by `merge unattended`, `via=<backend>`, the resolved choice arguments, and, with Orca, `RUN=<run id>`. For example: `bd-12 bd-13 merge unattended via=orca RUN=<id> worker=sonnet`. Never wait on a human.
3. **Record.** Keep its report for the final report. The cycle succeeded when every issue in the set reads `closed` with `bd show <id> --json`; anything else is a failed cycle under the rules below.

With the exec backend, follow `codex-lfg` to its report, then start the next cycle; cycles run one at a time. With Orca, `codex-lfg` returns as soon as its worker starts. Pick and start further sets until `PARALLEL` are in flight or no eligible set remains, then end the turn. Orca wakes the session when any agent reports. On each wake, the Task's title names the unit's branch. Invoke `codex-lfg` again with that unit's issue ids and the same arguments, and it resumes the unit. When a cycle finishes, start another set if one is eligible. `codex-lfg` merges one pull request at a time and sends a PR that fell behind back to its worker for a rebase.

## Loop and failure rules

Start the next cycle immediately. A cycle that cannot finish adds one to each member's `codex_delegate_attempts` metadata and appends the cause and PR to its notes with `bd update <id> --append-notes`. Below 2 attempts, make sure the issue is open and unclaimed (`--status open --assignee ''`; `codex-lfg` normally released it already) so a later cycle retries it; at 2, set it `blocked` and leave it for a person. When Orca's breaker failed the cycle's Task after three failed starts, set its issues `blocked` at once with that cause, whatever their attempt count, so no later cycle routes around the breaker. A failed or stopped cycle never stops the others; the loop continues with independent work. The attempt count lives in the tracker, not in context, so it survives compaction and restarts. The worker retry inside `codex-lfg` is part of one attempt.

Stop when no cycle is in flight, `bd ready` offers no non-epic issue other than human gates, and every issue this loop claimed is closed or blocked with a recorded cause. Also stop when trunk is red for a reason no cycle can fix.

## Final report

Give the backend with its reason and, with exec, why cycles ran one at a time. List each issue Recovery resumed and the step it resumed at. List each cycle from its `codex-lfg` report: bead ids, plan path, the worker, worker model, effort, and reviewer model with each one's source, the worker outcome (success, retried, or replaced by Claude), PR number, review rounds and findings accepted, merge SHA, and cleanup result. Then list every remaining open non-epic issue with the reason it stays, every blocked issue with its cause, and every human gate with the action a person must take.
