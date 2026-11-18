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

A cycle's choice of worker, model, effort, and reviewer model resolves in this order. An issue's own pinned choice, which `codex-lfg` documents, comes first. The latest choice the user sent during this run comes next, then the run default. Pass `WORKER_EFFORT=xhigh` for a set where any issue already has `codex_delegate_attempts` of 1 and no effort was chosen. On the exec backend, an unattended Sonnet agent can stop on a permission prompt nobody answers; `codex-lfg` then parks that unit and names the permission, and the other cycles continue.

Each cycle's plan, delegation, review loop, checks, merge, sync, issue closure, and cleanup are the `codex-lfg` procedure, including its restart rules. This skill picks the work, owns the attempt count, schedules the cycles, and decides when to stop.

## Preflight (once)

Confirm that the Skill tool lists `codex-lfg`; each cycle invokes it with its arguments, so do not invoke it here. If it is not listed, stop and tell the user to install `codex-lfg` at a version whose Claude copy omits `disable-model-invocation`. Never substitute reading its file for invoking it.

Choose the backend before Recovery, Pick, any tracker write, or any checkout change. Preflight only reads. With `exec`, the backend is exec. Otherwise run these probes:
- `orca status --json` succeeds, and its `result` has `caller.orcaSessionId`, `app.running` true, and `runtime.reachable` true.
- `ORCA_TERMINAL_HANDLE` is set.
- `orca agent hooks status` reports the Claude Code hooks enabled.

When all pass, the backend is Orca. Otherwise `auto` means exec, and `orca` stops the run with zero tracker and git writes, naming the failed probe. A continued run keeps the backend its run state records: when the probes now point elsewhere, use the recorded one, and when that is Orca and Orca is unusable, stop and report it. Print one line naming the backend and the reason. With Orca, load Orca's guide once with `orca skills get orchestration`.

Run `bd prime`, `bd ready --limit 0 --json`, `gh auth status`, and `git status --short`. Run `codex --version` before the first cycle that resolves to a Codex worker. Resolve the default branch with `gh repo view --json defaultBranchRef`. Stop and report if any probe fails or the local default branch has unpushed commits. A dirty working tree stops the run unless the dirt is a plan file a `codex-lfg` planning record names, or the current branch is the branch of a cycle found in Recovery below; `codex-lfg` commits those leftover changes when it resumes that branch.

## Run state

The run lives in `codex-delegate/run.json` under `git rev-parse --git-common-dir`, and only this skill writes it. It records the run id, the start time, the backend, the Orca Run id, the run defaults, the latest choice the user sent with when it was given, a stop time once the run ends, and one record per cycle:
- an attempt id, the issue set, the branch, the unit key `codex-lfg` reported, the backend, and the resolved choices with their sources;
- the phase: `picked`, `running`, `merged` (cleanup still pending), `parked`, `failing`, `failed`, or `closed`;
- the Pick writes still to land;
- for a failure, the failure writes: each issue's target `codex_delegate_attempts` value, its note, and its final status, each marked when it lands.

Read the file before anything else in the run. When it has no stop time, this invocation continues that run, its defaults, and its latest choice. Otherwise start a new run. A new invocation's own arguments become the run defaults only for a new run; for a continued run, treat them as a choice the user sent now.

With Orca, first settle a creation intent the run state records without a Run: read `orca orchestration request-show --request <key> --json`. `completed` means the Run exists: rerun `run-create` with the same `--retry-request` key to get its id, record it, and continue. `pending` means wait as it says. `absent` with a bound Run whose id the run state does not record is unclear: stop and report both. Then read `orca orchestration run-current --json`. When this session is bound to a Run other than the run state's, report both and stop. When it is bound to none, and `orca orchestration run-show --id <run>` still finds the recorded Run, bind it with `orca orchestration run-use --id <run>`. Otherwise, or for a new run, record a creation intent with a new UUID key and create one with `orca orchestration run-create --objective "codex-delegate" --retry-request <key> --json`, then record it. Every cycle shares that Run.

When the user names a different worker, model, effort, or reviewer model during the run, write it to the file at once. It applies from the next set to start.

## Recovery (once, before the first new cycle)

Before invoking `codex-lfg` for any cycle, read every `codex-lfg` unit state for a `checkout_owner`. While one is set, an exec Codex attempt may still write in the coordinator's checkout: invoke `codex-lfg` only for the cycle that owns it, and start or recover no other exec cycle until it clears.

First reconcile every cycle in the run state, by phase:
- **`picked`:** finish its Pick writes, checking each against `bd show` first, then set it `running` and run step 2 of One cycle.
- **`running` or `merged`:** run step 2 of One cycle. `codex-lfg` resumes the unit at its first unfinished step and reattaches to an agent still running.
- **`failing`:** finish the failure writes that have not landed, then set it `failed`.
- **`failed`, `parked`, or `closed`:** nothing to do; a failed cycle is never run again under the same attempt id.

Then list issues an interrupted run left outside the run state with `bd list --status=in_progress --has-metadata-key codex_delegate_branch --json`, and read each with `bd show <id> --json`. An issue with `codex_delegate_branch` but no `codex_lfg_branch` comes from an earlier version of this skill; `codex-lfg` resumes its `codex_delegate_branch`. Group issues that share a branch (`codex_lfg_branch`, else `codex_delegate_branch`) and are in no cycle of the run state, add each group as a `running` cycle, and run it through step 2 of One cycle.

Leave `in_progress` issues without `codex_delegate_branch` alone; another agent, or an interactive `codex-lfg` run, owns them. Report each recovered cycle and the step it resumed at in the final report. Then, unless some `codex-lfg` unit state records a `checkout_owner`, switch to the default branch and `git pull --ff-only`.

## One cycle

1. **Pick.** From `bd ready --limit 0 --json`, take the highest-priority eligible issue. An issue is eligible when it is not an epic, not a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`), has `codex_delegate_attempts` below 2, and is in no `running`, `merged`, or `parked` cycle of the run state. Add other ready issues only when they share its parent epic and the same code area and resolve to the same agent choices, and keep the set small enough for one reviewable PR. While other cycles are `running`, `merged`, or `parked`, a new set must not share a parent epic with any of them, and its code area must not overlap theirs. Judge the area from the issue text and the repository layout. `<branch>` is the branch `codex-lfg` derives for the set: its `codex_lfg_branch` when one is recorded, otherwise `codex-lfg/<first issue id>` normalized as `codex-lfg` describes.

   Before any tracker write, add the cycle to the run state with a new attempt id, the set, the branch, the backend, the resolved choices with their sources, and its Pick writes, in phase `picked`. The Pick writes mark each issue as this loop's with `bd update <id> --set-metadata codex_delegate_branch=<branch>`, and record the set's area judgment and its resolved choices, each with its source, with `bd update <id> --append-notes`, ending the note with `[codex-delegate pick <attempt id>]` so a restart can see it landed. Read each back with `bd show <id> --json`. Do not claim the issues; `codex-lfg` claims them. Set the phase to `running`.
2. **Run `codex-lfg`.** Invoke it through the Skill tool with the issue ids followed by `merge unattended`, `via=<backend>`, the resolved choice arguments, and, with Orca, `RUN=<run id>`. For example: `bd-12 bd-13 merge unattended via=orca RUN=<id> worker=sonnet`. Never wait on a human.
3. **Record.** Record the unit key `codex-lfg` reports; later invocations and wakes look up the cycle's unit state by it, since a replaced unit moves to a new branch. Act on the outcome it reports:
   - `in-flight`: the cycle keeps its slot and stays `running`. A wake brings it back.
   - `merged`: set the phase to `merged`. The cycle frees its slot, and its pending cleanup is retried on each wake and before the run stops.
   - `done`: confirm every issue in the set reads `closed` with `bd show <id> --json`, keep its report for the final report, and set the phase to `closed`. An issue still open makes it a failed cycle, recorded as `failing` below.
   - `parked`: set the phase to `parked`. It frees its slot, its issues are no longer eligible for Pick whether or not their claim landed, and the final report names what a person must settle.
   - `failed`: record the failure writes and set the phase to `failing` in one update of the run state, then apply the failure rules below.
   - No outcome, or one not listed here: read the outcome the cycle's unit state records and act on that. When it records none either, set the phase to `parked`, since the unit may have started something, and report it.

With the exec backend, cycles run one at a time: start the next only when the current one is no longer `running`. With Orca, `codex-lfg` returns `in-flight` as soon as its worker starts. Pick and start further sets until `PARALLEL` cycles are `running` or no eligible set remains, then end the turn.

A wake comes from Orca when any agent reports, or from a background check watch or timer that exits. On each wake, invoke `codex-lfg` for one `running` cycle: the one the wake names, or else the oldest. With Orca, its entry step drains the Run's mail and routes every event to the unit it belongs to. Then invoke `codex-lfg` again for every other `running` or `merged` cycle whose `codex-lfg` unit state, found by the cycle's unit key under `<git common dir>/codex-lfg/units/`, following any `replaced_by`, holds pending events or pending cleanup, each with that cycle's issue ids and the same arguments. When a cycle frees its slot, start another set if one is eligible. `codex-lfg` merges one pull request at a time and sends a PR that fell behind back to its worker for a rebase.

## Loop and failure rules

Start the next cycle immediately. A failed cycle adds one to each member's `codex_delegate_attempts` metadata, exactly once. Its failure writes are recorded with the `failing` phase, before any of them is applied. For each issue they are: the target attempt count, one more than `bd show` reads now; a note with the cause and PR, ending with `[codex-delegate failure <attempt id>]`; and the final status. The final status is open and unclaimed (`--status open --assignee ''`) below 2 attempts, so a later cycle retries the issue under a new attempt id, and `blocked` at 2, left for a person. When Orca's breaker failed the cycle's Task after three failed starts, the final status is `blocked` with that cause whatever the count, so no later cycle routes around the breaker. Then apply each write with `bd update`, read it back (a note by its marker), and mark it landed. When all have landed, set the phase to `failed`. A restart finishes only the writes not yet landed, and never recomputes a target. A failed or parked cycle never stops the others; the loop continues with independent work. The attempt count lives in the tracker and the run state, not in context, so it survives compaction and restarts. The worker retry inside `codex-lfg` is part of one attempt.

Stop when no cycle is `running` and `bd ready --limit 0` offers no eligible issue, by the same test Pick uses. When a `checkout_owner` blocks every exec cycle, stop too and name it. Also stop when trunk is red for a reason no cycle can fix. Before stopping, invoke `codex-lfg` once more for each `merged` cycle. Record the stop time in the run state only when no cycle is still `merged`; otherwise leave the run open, and say in the final report that invoking `codex-delegate` again continues it and retries the pending cleanup.

## Final report

Give the backend with its reason and, with exec, why cycles ran one at a time. List each cycle Recovery resumed and the step it resumed at. List each cycle from its `codex-lfg` report: bead ids, plan path, the worker, worker model, effort, and reviewer model with each one's source, the worker outcome (success, retried, or replaced by Claude), PR number, review rounds and findings accepted, merge SHA, and cleanup result. List each `merged` cycle whose cleanup is still pending and each `parked` cycle with what a person must settle. Then list every remaining open non-epic issue with the reason it stays, every blocked issue with its cause, and every human gate with the action a person must take.
