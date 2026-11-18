---
name: codex-lfg
description: Hand one unit of work, a plan file, one or more Beads issues, or a quoted task, to a worker agent (Codex CLI by default, Claude Sonnet on request) that implements it through compound-engineering:lfg up to an open pull request; a separate reviewer agent reviews it, and Claude Code triages the findings, routes fixes back to the same worker, and gates the PR; merge only when asked. Workers run as Orca agents when Claude Code runs inside an Orca terminal, otherwise in the background. Claude Code only. Explicit invocation only, or loaded by codex-delegate for each cycle.
---

Usage: `/codex-lfg <plan-path | bead-id... | "task description"> [merge] [unattended] [via=auto|orca|exec] [worker=codex|sonnet] [WORKER_MODEL=<model>] [WORKER_EFFORT=<effort>] [REVIEWER_MODEL=<model>] [ROUNDS=<n>]`.

Run one unit of work through a worker agent and bring it back reviewed. Claude is the coordinator: it plans when needed, triages every review, sends the fixes, and owns the merge. The worker only implements the plan and the fixes the coordinator sends, and opens a pull request. The reviewer only reports. The user stays in the loop: workers run in Orca tabs or in the background, so the session stays free while they work. Write English in code, commits, PRs, and tracker fields.

This procedure runs on Claude Code. On any other host, stop before any tracker or git write and tell the user to run it from Claude Code. It needs the `compound-engineering` plugin installed for both Claude Code and Codex and `gh` working. It needs `bd` working only when the input names Beads issues, `codex` on PATH only when the worker is Codex, and Orca only for the Orca backend.

## Parameters

Overridable by the user or by `codex-delegate`:
- `VIA`: `auto` unless the arguments include `via=orca` or `via=exec`. Preflight resolves it to the Orca or the exec backend.
- `WORKER`: `codex` unless the arguments include `worker=sonnet`, which runs a Claude Sonnet worker instead.
- `WORKER_MODEL`: empty by default. A Codex worker then uses the `model` from the Codex config (`~/.codex/config.toml`), and a Sonnet worker uses `sonnet`. `CODEX_MODEL=<model>` is accepted as the same parameter.
- `WORKER_EFFORT`: empty by default, so a Codex worker uses the `model_reasoning_effort` from the Codex config. Set it to `xhigh` when the plan has three or more implementation units, touches a contract, migration, or security boundary, or a previous attempt on the same unit failed; otherwise set it only when the user names an effort. `CODEX_EFFORT=<effort>` is accepted as the same parameter.
- `REVIEWER_MODEL`: `sonnet` unless the arguments name another.
- `ROUNDS`: the most review rounds before the unit stops, 5 unless the arguments name another number.
- `MERGE`: off unless the arguments include the word `merge`.
- `UNATTENDED`: off unless the arguments include the word `unattended`, which `codex-delegate` passes. When on, never ask the user anything: take the recommended option, record it in the issue notes and the PR body, and treat every place below that would ask as the unattended rule it names.
- `RUN`: set only by `codex-delegate` as `RUN=<id>`, the Orca Run every unit of its run shares.

The operator can pin a choice on an issue. A pinned choice wins over the arguments for every unit that contains the issue:

```sh
bd update <id> --set-metadata codex_lfg_worker=sonnet
bd update <id> --set-metadata codex_lfg_worker_model=<model>
bd update <id> --set-metadata codex_lfg_worker_effort=<effort>
bd update <id> --set-metadata codex_lfg_reviewer_model=<model>
```

When issues in one unit pin different values for the same choice, stop and name them. An empty parameter adds no flag, so upgrading a model is a config change, not a skill change. The backend reference states how each choice reaches the worker.

## Input

Parse the arguments once. First remove the words `merge` and `unattended` and every `NAME=value` argument. Then classify what remains, in this order:
1. An argument naming an existing file is the plan, even when its path contains spaces. Resolve it to an absolute path. At most one plan is allowed.
2. A single remaining argument that contains whitespace, with no plan and no other argument, is a task description.
3. Every other argument must be a Beads issue id that `bd show <id> --json` returns.

With nothing left, or with an argument that fits none of these, stop and print the usage line. Refuse an issue that is closed, an epic, or a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`). Refuse an issue that is `in_progress` without `codex_lfg_branch` or `codex_delegate_branch` metadata; another agent owns it.

A plan with issue ids is allowed: the plan is used as written, and the issues are claimed and closed with it. A task description is planned first: run `/compound-engineering:ce-plan` on it, print the absolute path of the plan it writes, and continue with that plan as the plan argument. No bead is created unless the user asks. To resume that unit later, rerun with the printed plan path.

The branch name is the unit's identity, fixed by the input so a rerun finds earlier work: `codex-lfg/<plan file name without extension>` when a plan is given, otherwise `codex-lfg/<first issue id>`, lowercased with every character outside `a-z0-9._-` replaced by `-`. When an input issue already carries `codex_lfg_branch`, use that branch instead; failing that, use the `codex_delegate_branch` an earlier version of `codex-delegate` left on it, and record it as `codex_lfg_branch` in step 1. The words `merge` and `unattended` and the other parameters never change the identity.

## Preflight

1. **Choose the backend before any other probe or write.** With `via=exec`, the backend is exec. Otherwise run these probes:
   - `orca status --json` succeeds, and its `result` has `caller.orcaSessionId`, `app.running` true, and `runtime.reachable` true.
   - `ORCA_TERMINAL_HANDLE` is set. Orca refuses orchestration commands without it.
   - `orca agent hooks status` reports the Claude Code hooks enabled. Without them, Orca cannot wake this session.

   When all pass, the backend is Orca. Otherwise, with `via=auto`, a missing `orca` command or any failed probe means exec. With `via=orca`, stop before any tracker or git write and name the failed probe. Print one line naming the backend and the reason.
2. Run `gh auth status` and `git status --short`, plus `bd prime` when the input names issues and `codex --version` when the worker is Codex. Resolve the default branch with `gh repo view --json defaultBranchRef`. Stop and report if any probe fails, the local default branch has unpushed commits, or the working tree is dirty; a dirty tree belongs to the user, so never commit or stash it. The one exception is a dirty tree on this unit's own branch, which Resume handles.
3. Read the backend reference now: `references/orca.md` for Orca, `references/exec.md` for exec. It holds every backend-specific command the steps below name.

## Resume

Look up the branch and its PR with `git ls-remote --heads origin <branch>`, `git branch --list <branch>`, and `gh pr list --head <branch> --state all --json number,state,headRefOid`. For an open PR, read its review ledger, the `codex-lfg review round <n>` comments, with `gh pr view <n> --json comments`. In Orca mode, also find the unit's Task and its agents as the reference describes. Then start at the first unfinished step:
- PR `MERGED`: step 7, including any cleanup still pending.
- A worker or reviewer for this unit is still running: wait for it and never start a second one.
- PR `OPEN`: step 5, at the latest ledger round. With no ledger yet, start a review. A round with accepted findings and no recorded hand-off sends them. A recorded hand-off waits for the worker's push. A clean round at the current head goes to step 6. A clean round whose head has since moved starts a new round.
- Branch with commits ahead of the default branch but no PR: step 4. First commit leftover changes in the workspace that holds the branch as `wip: recover interrupted codex-lfg run`, and push.
- PR `CLOSED` unmerged: a closed PR is a decision someone made. Ask the user whether to start over on a fresh branch. Unattended, start over without asking on `<branch>-r<k>`, the first such name with no branch and no PR, record it with `bd update <id> --set-metadata codex_lfg_branch=<branch>-r<k>` for each issue, and go to step 1.
- Nothing yet: step 1.

Report the step a run resumed at.

## Steps

1. **Plan.** With a plan argument, read the plan and use it as written; when it lacks acceptance criteria or verification commands, state the missing ones in the brief instead of editing the user's file. With issue ids, claim each with `bd update <id> --claim`, record the branch with `bd update <id> --set-metadata codex_lfg_branch=<branch>`, and read it back with `bd show <id> --json`. Without a plan argument, run `/compound-engineering:ce-plan` with the issue ids, titles, bodies, and acceptance criteria, and record the absolute path of the plan it writes. The plan must name the bead ids, the acceptance criteria, and the verification commands.
2. **Workspace.** The backend reference sets up the workspace that will hold the branch. Only an exec Codex worker uses the coordinator's own checkout. In every other case the coordinator's checkout stays on the default branch.
3. **Delegate.** Write the brief to a file in the scratchpad and start the worker as the reference describes, then set its deadline (see Deadline). The brief says, in English: implement the plan at `<absolute plan path>` with the compound-engineering `lfg` skill on branch `<branch>`, creating it before the first commit if the workspace is on another branch; end with an open pull request against `<default>` whose body lists the bead ids, if any; do not merge, do not close or edit Beads issues, do not push to `<default>`; do not rewrite history, except that when the coordinator asks you to rebase this pull request you may push its branch with `--force-with-lease`; if blocked, stop and state the blocker in your final message.

   Tell the user what started and where to watch it: the Orca tab, or the log path. Then wait without polling. The Orca wake or the background-task notification brings the run back here. When `codex-delegate` invoked this skill in Orca mode, return to it as soon as the worker has started, so it can start other units.
4. **Check the handoff.** Find the PR with `gh pr list --head <branch> --json number,headRefOid,state`. If the worker left commits but no PR, open it with `/compound-engineering:ce-commit-push-pr` from the workspace that holds the branch. If the worker failed with no usable commits, retry it once with `WORKER_EFFORT=xhigh` and the failure reason added to the brief, as the reference describes. If that also fails, implement the plan yourself with `/compound-engineering:ce-work` in that workspace. If an unattended answer from Questions below is missing from the PR body, add it.
5. **Review loop.** Each round:
   1. Start a fresh reviewer on the PR at its current head, on `REVIEWER_MODEL`, as the reference describes. Its brief says: run `/compound-engineering:ce-code-review` on pull request `<n>` and report every finding with its severity, file, and evidence; do not edit, commit, or push.
   2. Triage each finding. Accept a finding that is valid and within the plan or its acceptance criteria. Reject a finding that is wrong, a duplicate, or out of scope, and give the reason. A valid out-of-scope finding is filed in step 7.
   3. Post the round's ledger with `gh pr comment <n> --body-file <file>`. The ledger is headed `codex-lfg review round <n>` and records the reviewed head SHA, the base SHA, the reviewer, the verdict, and each finding as accepted or rejected with its reason.
   4. With no accepted finding, the round is clean and its head is the approved head: go to step 6. Otherwise send the accepted findings to the same worker as the reference describes, edit the ledger comment to record that hand-off, and wait for the worker's push. Then start the next round.

   After `ROUNDS` rounds with accepted findings still open, ask the user whether to run more rounds, fix the rest yourself, or stop. Unattended, treat the unit as failed under Failure.
6. **Gate, then stop or merge.** Run the plan's verification commands on the approved head, in the workspace that holds it. Decide whether the PR has checks by reading `gh pr view <n> --json statusCheckRollup`, not by the exit code of `gh pr checks`, which fails when a PR has no checks. Checks can register late, so read it again after two minutes when the first read is empty.
   - **Checks present:** wait with `gh pr checks <n> --watch` run as a background command, whose exit brings the run back here. A failing check goes to the worker as an accepted finding in a new round. It is never bypassed.
   - **Still empty, and no workflow under `.github/workflows/` triggers on `pull_request`:** the repository has no PR CI. Rerun the full local test, lint, and type gates on the approved head, in the workspace that holds it, and treat their pass as the gate.
   - **Still empty, but a `pull_request` workflow exists:** checks are stuck. Push an empty commit once from the workspace that holds the branch to retrigger them; if they still do not appear, stop and report that cause.

   With `MERGE` off, stop here and report; tell the user that rerunning the same command with `merge` added resumes at this step and merges. With `MERGE` on, never use `--admin` or auto-merge. Merge one pull request at a time. Right before merging, the PR head must equal the approved head, or a new round starts. `gh pr view <n> --json mergeStateStatus` must also not read `BEHIND` or `DIRTY`. If it does, send the worker a rebase request. Then run a new round on the rebase change alone, `git range-diff <old base>..<old head> <new base>..<new head>`, and wait for checks on the new head. Merge as the reference describes, with `--match-head-commit <approved head>`, confirm `gh pr view <n> --json state` reads `MERGED`, then `git switch <default> && git pull --ff-only`.
7. **Close.** Only after the PR reads `MERGED`, close each issue with `bd close <id> --reason "Merged in #<n>"`, read it back with `bd show <id> --json`, and persist tracker changes the way this repository's Beads setup requires. Clean up the unit's workspace and agents as the reference describes. When the repository uses Beads, file each valid out-of-scope finding as a new P2-or-lower `tech-debt` issue that cites the PR; otherwise list it in the report.

## Deadline

Every worker and reviewer start has a deadline 90 minutes after it starts. On every entry to this skill, compare the deadline with the time now. Then start a background command that sleeps for the time left and names the agent it guards. Its exit only asks for an inspection. Ignore an exit for an agent that is no longer current. Past the deadline, apply the reference's hang rule.

## Questions from the worker

Answer from the plan and the repository. Ask the user only for a choice that is theirs: a scope change; a change to a contract, permission, or security stance; or starting over after a closed PR. Unattended, take the recommended option, append it to each issue's notes at once with `bd update <id> --append-notes`, and tell the worker to put it in the PR body. Step 4 checks that it is there.

## Failure

Take the recommended option on technical choices and record it in the PR body. When the unit cannot finish, stop and report the cause, the branch, the PR, and the workspace and agents kept for inspection. Do not clean up a failed unit's workspace or agents. For issues, append the cause and the PR to each with `bd update <id> --append-notes` and release the claim with `bd update <id> --status open --assignee ''`, keeping `codex_lfg_branch` so a rerun resumes the same branch.

## Report

State the input, the plan path, the branch, and the backend with its reason. Give the worker, worker model, effort, and reviewer model, each with its source: an issue pin, an argument, or the config default. Give the worker outcome (success, retried, or replaced by Claude), the PR URL, the number of review rounds, the findings accepted and rejected, the approved head SHA, and the check result. Then give either the merge SHA and the cleanup result, or that the PR is open and awaiting `merge`. For issues, give each one's final state.
