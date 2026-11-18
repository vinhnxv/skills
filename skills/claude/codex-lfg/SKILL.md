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
- `WORKER_MODEL`: for a Sonnet worker, `sonnet` unless another model is chosen, and always passed to the worker. For a Codex worker, empty by default, so Codex uses the `model` from its config (`~/.codex/config.toml`). `CODEX_MODEL=<model>` is accepted as the same parameter.
- `WORKER_EFFORT`: empty by default, so a Codex worker uses the `model_reasoning_effort` from its config. When no argument or issue pin chose an effort, set it to `xhigh` when the plan has three or more implementation units, touches a contract, migration, or security boundary, or a previous attempt on the same unit failed. `CODEX_EFFORT=<effort>` is accepted as the same parameter.
- `REVIEWER_MODEL`: `sonnet` unless the arguments name another.
- `ROUNDS`: the most review rounds before the unit stops, 5 unless the arguments name another number. A round that sends fixes, failing checks, or a rebase to the worker counts as one.
- `MERGE`: off unless the arguments include the word `merge`.
- `UNATTENDED`: off unless the arguments include the word `unattended`, which `codex-delegate` passes. When on, never ask the user anything: take the recommended option, record it in the unit state, the issue notes, and the PR body, and treat every place below that would ask as the unattended rule it names.
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

Parse the arguments once, reading only the local filesystem. First remove the words `merge` and `unattended` and every `NAME=value` argument. Then classify what remains, in this order:
1. An argument naming an existing file is the plan, even when its path contains spaces. Resolve it to an absolute path. At most one plan is allowed.
2. A single remaining argument that contains whitespace, with no plan and no other argument, is a task description. Step 1 plans it.
3. Every other argument is a Beads issue id, resolved after Preflight.

With nothing left, stop and print the usage line.

## Preflight

1. **Choose the backend before any other probe or write.** With `via=exec`, the backend is exec. Otherwise run these probes:
   - `orca status --json` succeeds, and its `result` has `caller.orcaSessionId`, `app.running` true, and `runtime.reachable` true.
   - `ORCA_TERMINAL_HANDLE` is set. Orca refuses orchestration commands without it.
   - `orca agent hooks status` reports the Claude Code hooks enabled. Without them, Orca cannot wake this session.

   When all pass, the backend is Orca. Otherwise, with `via=auto`, a missing `orca` command or any failed probe means exec. With `via=orca`, stop before any tracker or git write and name the failed probe. Print one line naming the backend and the reason.
2. Run `gh auth status` and `git status --short`, plus `bd prime` when the input names issues and `codex --version` when the worker is Codex. Resolve the default branch with `gh repo view --json defaultBranchRef` and the coordinator's login with `gh api user --jq .login`. Stop and report if any probe fails, the local default branch has unpushed commits, or the working tree is dirty; a dirty tree belongs to the user, so never commit or stash it. The one exception is a dirty tree on this unit's own branch, which Resume handles.
3. Read the backend reference now: `references/orca.md` for Orca, `references/exec.md` for exec. It holds every backend-specific command the steps below name.

## Identity and unit state

Read each issue id with `bd show <id> --json`; an id it does not return stops the run with the usage line.

The branch name is the unit's identity, fixed by the input so a rerun finds earlier work: `codex-lfg/<plan file name without extension>` when a plan is given, otherwise `codex-lfg/<first issue id>`, lowercased with every character outside `a-z0-9._-` replaced by `-`. When an input issue already carries `codex_lfg_branch`, use that branch instead; failing that, use the `codex_delegate_branch` an earlier version of `codex-delegate` left on it, and record it as `codex_lfg_branch` in step 1. The words `merge` and `unattended` and the other parameters never change the identity.

The unit state is one JSON file the coordinator alone writes: `<git common dir>/codex-lfg/units/<branch with / replaced by ->.json`, where the git common dir is `git rev-parse --git-common-dir`. It records the inputs, the plan path, the branch, the default branch, the backend, the Orca Run and parent Task, the workspace, and each agent choice with its source. It also records the phase; every agent started, with its role, attempt, identity, start time, deadline, timer, and result path; each review round; a pending hand-off; the approved head; the gate; answers given to questions; routed Orca events; and pending cleanup. Write the intent to the file before each action it names and the outcome after it lands, so a restart can tell a step that never ran from one whose result is waiting. When the file is missing, rebuild what you can from the branch, the PR, and the ledger before acting.

Then check the issues against the unit. When the unit's PR reads `MERGED`, accept the input as it is, closed issues included, and go to Resume. Otherwise refuse an issue that is closed, an epic, or a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`), and refuse an issue that is `in_progress` without `codex_lfg_branch` or `codex_delegate_branch` metadata; another agent owns it.

## Resume

Look up the branch and its PR with `git ls-remote --heads origin <branch>`, `git branch --list <branch>`, and `gh pr list --head <branch> --state all --json number,state,headRefOid`, and read the unit state. In Orca mode, also run the reference's entry steps. The review ledger is the set of PR comments headed `codex-lfg review round <n>`. Trust a ledger comment only when the coordinator's login wrote it and its ID matches the round in the unit state, or, with no unit state, when the coordinator's login wrote it. Then start at the first unfinished step:
- PR `MERGED`: the end of step 6 (sync the default branch), then step 7, retrying anything the unit state lists as pending.
- An agent the unit state records as running: reattach as the reference describes, and never start a second one for the same role and attempt.
- A pending hand-off: reconcile it as step 5 describes.
- A gate recorded for the approved head: continue step 6 from the gate.
- PR `OPEN`: step 5. A round whose review result is recorded but not triaged is triaged. A clean round at the current head goes to step 6. A clean round whose head has since moved starts a new round. With no round yet, start one.
- Branch with commits ahead of the default branch but no PR: step 4. First commit leftover changes in the workspace that holds the branch as `wip: recover interrupted codex-lfg run`, and push.
- PR `CLOSED` unmerged: a closed PR is a decision someone made. Ask the user whether to start over on a fresh branch. Unattended, start over without asking on `<branch>-r<k>`, the first such name with no branch and no PR, record it with `bd update <id> --set-metadata codex_lfg_branch=<branch>-r<k>` for each issue, start a new unit state for it, and go to step 1.
- Nothing yet: step 1.

Report the step a run resumed at.

## Steps

1. **Plan.** With a plan argument, read the plan and use it as written; when it lacks acceptance criteria or verification commands, state the missing ones in the brief instead of editing the user's file. With a task description, run `/compound-engineering:ce-plan` on it, print the absolute path of the plan it writes, and use that plan; no bead is created unless the user asks, and rerunning with the printed plan path resumes the unit. With issue ids, claim each with `bd update <id> --claim`, record the branch with `bd update <id> --set-metadata codex_lfg_branch=<branch>`, and read it back with `bd show <id> --json`. Without a plan argument, run `/compound-engineering:ce-plan` with the issue ids, titles, bodies, and acceptance criteria, and record the absolute path of the plan it writes. The plan must name the bead ids, the acceptance criteria, and the verification commands.
2. **Workspace.** The backend reference sets up the workspace that will hold the branch. Only an exec Codex worker uses the coordinator's own checkout. In every other case the coordinator's checkout stays on the default branch.
3. **Delegate.** Write the build brief to a per-attempt file in the scratchpad and start the worker as the reference describes, then set its deadline (see Deadline). The build brief says, in English:
   - Implement the plan at `<absolute plan path>` with the compound-engineering `lfg` skill on branch `<branch>`, creating it before the first commit if the workspace is on another branch.
   - Stop once a pull request against `<default>` is open with your commits pushed; its body lists the bead ids, if any. Skip `lfg`'s CI watch (`ce-babysit-pr`); the coordinator owns review rounds and checks.
   - Do not merge, do not close or edit Beads issues, do not push to `<default>`, and do not rewrite history.
   - If you need a decision only the operator can make, commit and push what you have, then end your final message with a line starting `QUESTION:` that states the choices and your recommendation.
   - If blocked, stop and state the blocker in your final message.

   Tell the user what started and where to watch it: the Orca tab, or the log path. Then wait without polling. The Orca wake or the background-task notification brings the run back here. When `codex-delegate` invoked this skill in Orca mode, return to it as soon as the worker has started, so it can start other units.
4. **Check the handoff.** Read the worker's result. A `QUESTION:` line goes to Questions below before anything else. Find the PR with `gh pr list --head <branch> --json number,headRefOid,state`. If the worker left commits but no PR, open it with `/compound-engineering:ce-commit-push-pr mode:pipeline` from the workspace that holds the branch. If the worker failed with no usable commits, retry it once with `WORKER_EFFORT=xhigh` and the failure reason added to the brief, as the reference describes. If that also fails, implement the plan yourself with `/compound-engineering:ce-work mode:return-to-caller` in that workspace, then open the PR as above. If an unattended answer from Questions below is missing from the PR body, add it.
5. **Review loop.** Each round:
   1. Record the round in the unit state with the PR's current `headRefOid` and base SHA, then start a fresh reviewer on `REVIEWER_MODEL` as the reference describes. Its brief says: confirm pull request `<n>` is at head `<sha>`, and if not, stop and say so; otherwise run `/compound-engineering:ce-code-review mode:agent plan:<absolute plan path>` on pull request `<n>` and write its JSON result to `<result path>`; do not edit, commit, push, or comment. For a rebase round, the brief also names the ranges to compare: `git range-diff <old base>..<old head> <new base>..<new head>`.
   2. Accept the review only when the result file holds `status: complete` and its `scope.head_sha` equals the round's head. A reviewer that fails, returns another status, or reviewed a different head is retried once as a reviewer at the current head. When that also fails, the unit has failed: a round never passes without a usable review.
   3. Triage each finding in the result. Accept a finding that is valid and within the plan or its acceptance criteria. Reject a finding that is wrong, a duplicate, or out of scope, and give the reason. A valid out-of-scope finding is filed in step 7.
   4. Post the round's ledger with `gh pr comment <n> --body-file <file>` and record the comment's ID in the unit state. The ledger is headed `codex-lfg review round <n>` and records the reviewed head SHA, the base SHA, the reviewer, the verdict, and each finding as accepted or rejected with its reason.
   5. With no accepted finding, the round is clean: record its head and base as the approved head and go to step 6. Otherwise hand the accepted findings to the worker.

   **Hand-off.** Fixes, failing checks, and rebase requests all go to the same worker this way. Record a pending hand-off in the unit state first: its round, its kind, the old head and base, and a request ID. Then send it as the reference describes, using a fix brief: apply exactly these changes on branch `<branch>` of pull request `<n>`, run the plan's verification commands, commit, and push; do not rerun `lfg`, open another pull request, or touch Beads. A rebase brief instead asks the worker to rebase the branch onto `<default>`, resolve conflicts, run the verification commands, and push with `--force-with-lease`. Edit the ledger comment to record the hand-off. When the worker settles, compare the PR head with the old head. A new head starts the next round. An unchanged head means the attempt did not deliver: hand the same request off once more, then the unit has failed. A pending hand-off found on Resume whose send cannot be confirmed is resent with the same request ID, which the reference makes safe to repeat.

   After `ROUNDS` rounds with accepted findings still open, ask the user whether to run more rounds, fix the rest yourself, or stop. Unattended, treat the unit as failed under Failure.
6. **Gate, then stop or merge.** Record the gate in the unit state with the approved head and base, then run the plan's verification commands on the approved head, in the workspace that holds it, and record the result.

   Then decide whether the PR has checks from `gh pr view <n> --json headRefOid,statusCheckRollup`, not from the exit code of `gh pr checks`, which fails when a PR has no checks. Checks can register late, so read it again after two minutes when the first read is empty.
   - **Checks present:** unless the gate already records a watch that is still running, start `gh pr checks <n> --watch` as a background command, record its identity and a deadline 60 minutes out, and wait for its exit. On that exit, and on every entry, read the checks again and use them only when `headRefOid` equals the approved head. All passing completes the gate. A failing check goes to the worker as a hand-off of kind `checks`, which starts a new round; it is never bypassed. Checks still pending past the deadline mean the unit has failed.
   - **Still empty:** checks are expected when any workflow under `.github/workflows/` triggers on `pull_request`, `pull_request_target`, or `push`, or when the default branch's head has check runs or statuses (`gh api repos/<owner>/<repo>/commits/<default>/check-runs --jq .total_count` and `gh api repos/<owner>/<repo>/commits/<default>/status --jq '.statuses | length'`). Without either, the repository has no CI: rerun the full local test, lint, and type gates on the approved head, in the workspace that holds it, and treat their pass as the gate. When checks are expected, retrigger them once: record the retrigger in the gate, push an empty commit from the workspace that holds the branch, confirm `git diff <approved head> <new head>` is empty, record the new head as the approved head in the unit state and the ledger, and read the checks again. If they still do not appear, stop and report that cause.

   With `MERGE` off, stop here and report; tell the user that rerunning the same command with `merge` added resumes at this step and merges. With `MERGE` on, never use `--admin` or auto-merge. Merge one pull request at a time. When `gh api repos/<owner>/<repo>/rules/branches/<default>` lists a `merge_queue` rule, stop and report that this repository merges through a queue, which this skill does not drive. Right before merging:
   - The PR head must equal the approved head, or a new round starts.
   - Run `git fetch origin <default>` and require `git merge-base --is-ancestor origin/<default> <approved head>`. When it fails, the PR is behind its base: hand off a rebase, then run the new round on the rebase change and the gate on the new head.
   - `gh pr view <n> --json mergeStateStatus` must not read `BEHIND` or `DIRTY`, which the same rebase hand-off handles.

   Merge as the reference describes, with `--match-head-commit <approved head>` and without `--delete-branch`. Confirm `gh pr view <n> --json state` reads `MERGED` and record it in the unit state, then `git switch <default> && git pull --ff-only` in the coordinator's checkout.
7. **Close.** Only after the PR reads `MERGED`, record the remaining work as pending in the unit state and do each item, marking it done when it lands. A later entry retries whatever is still pending:
   1. Close each issue still open with `bd close <id> --reason "Merged in #<n>"`, read it back with `bd show <id> --json`, and persist tracker changes the way this repository's Beads setup requires.
   2. Clean up the unit's workspace, branches, and agents as the reference describes.
   3. When the repository uses Beads, file each valid out-of-scope finding as a new P2-or-lower `tech-debt` issue that cites the PR; otherwise list it in the report.

## Deadline

Every agent start has a deadline 90 minutes after it starts, recorded in the unit state. On every entry to this skill, compare each running agent's deadline with the time now. When no timer this session started already guards the agent, start a background command that sleeps for the time left, record it, and name the agent it guards. Its exit only asks for an inspection. Ignore an exit for an agent that is no longer current. Past the deadline, apply the reference's hang rule.

## Questions from the worker

A question reaches the coordinator as an Orca question or, in exec, as a worker result ending with a `QUESTION:` line. Answer from the plan and the repository. Ask the user only for a choice that is theirs: a scope change; a change to a contract, permission, or security stance; or starting over after a closed PR. Unattended, take the recommended option. Record every answer in the unit state, append it to each issue's notes with `bd update <id> --append-notes`, and tell the worker to put it in the PR body; step 4 checks that it is there. In exec, a question is not a failure: start the same phase again with the answer added to its brief.

## Failure

Take the recommended option on technical choices and record it in the PR body. When the unit cannot finish, record the cause in the unit state, then stop and report the cause, the branch, the PR, and the workspace and agents kept for inspection. Do not clean up a failed unit's workspace or agents. For issues, append the cause and the PR to each with `bd update <id> --append-notes` and release the claim with `bd update <id> --status open --assignee ''`, keeping `codex_lfg_branch` so a rerun resumes the same branch.

## Report

State the input, the plan path, the branch, and the backend with its reason. Give the worker, worker model, effort, and reviewer model, each with its source: an issue pin, an argument, or the config default. Give the worker outcome (success, retried, or replaced by Claude), the PR URL, the number of review rounds, the findings accepted and rejected, the approved head SHA, and the check result. Then give either the merge SHA and the cleanup result, or that the PR is open and awaiting `merge`. For issues, give each one's final state.
