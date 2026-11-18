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
- `ROUNDS`: the most corrective hand-offs before the unit stops, 5 unless the arguments name another number. Fixes, failing checks or verification, rebases, and a check retrigger each count as one.
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
2. A single remaining argument that contains whitespace, with no plan and no other argument, is a task description, planned after Preflight.
3. Every other argument is a Beads issue id, resolved after Preflight.

With nothing left, stop and print the usage line.

## Preflight

Preflight only reads; it writes nothing.
1. **Choose the backend before any other probe.** With `via=exec`, the backend is exec. Otherwise run these probes:
   - `orca status --json` succeeds, and its `result` has `caller.orcaSessionId`, `app.running` true, and `runtime.reachable` true.
   - `ORCA_TERMINAL_HANDLE` is set. Orca refuses orchestration commands without it.
   - `orca agent hooks status` reports the Claude Code hooks enabled. Without them, Orca cannot wake this session.

   When all pass, the backend is Orca. Otherwise, with `via=auto`, a missing `orca` command or any failed probe means exec. With `via=orca`, stop and name the failed probe. Print one line naming the backend and the reason. A unit that already has state keeps its recorded backend, as `references/state.md` describes.
2. Run `gh auth status` and `git status --short`, plus `bd prime` when the input names issues and `codex --version` when the worker is Codex. Resolve the repository with `gh repo view --json nameWithOwner,defaultBranchRef` and the coordinator's login with `gh api user --jq .login`. Stop and report if any probe fails, the local default branch has unpushed commits, or the working tree is dirty; a dirty tree belongs to the user, so never commit or stash it. The one exception is a dirty tree on this unit's own branch, which Resume handles.
3. Read `references/state.md` and the backend reference: `references/orca.md` for Orca, `references/exec.md` for exec. They hold the restart rules and every backend-specific command the steps below name.

## Planning a task description

A task description has no file to name the unit by yet, so plan it first. Its planning record is `units/text-<the first 12 hex digits of the SHA-256 of the description>.json` under the state directory. When the record holds a plan path, use that plan. Otherwise record a planning intent, run `/compound-engineering:ce-plan` on the description, and record the absolute path of the plan it writes; the intent check in `references/state.md` finds a plan a restart left unrecorded. Print the plan path. From here on, the plan is the input; no bead is created unless the user asks.

## Identity and unit state

Read each issue id with `bd show <id> --json`; an id it does not return stops the run with the usage line.

The branch name is the unit's identity, fixed by the input so a rerun finds earlier work: `codex-lfg/<plan file name without extension>` when a plan is given, otherwise `codex-lfg/<first issue id>`, lowercased with every character outside `a-z0-9._-` replaced by `-`. When an input issue already carries `codex_lfg_branch`, use that branch instead; failing that, use the `codex_delegate_branch` an earlier version of `codex-delegate` left on it, and record it as `codex_lfg_branch` in step 1. The words `merge` and `unattended` and the other parameters never change the identity.

Load the unit state that `references/state.md` defines, or start one with the identity and the choices. Then, before anything else: apply the backend lock, check every intent without a receipt, and, with Orca, run the reference's entry steps. A unit whose recorded inputs differ from this invocation's, other than the words `merge` and `unattended` and the choice parameters, is a different unit under the same name: stop and name both.

Bind the pull request as `references/state.md` describes. When the bound PR reads `MERGED`, accept the input as it is, closed issues included, and go to Resume. Otherwise refuse an issue that is closed, an epic, or a human gate (`[HUMAN]` title, `human-gate` label, or type `gate`). Refuse an issue that is `in_progress` without `codex_lfg_branch` or `codex_delegate_branch` metadata, unless this unit's state records a claim intent for it; another agent owns it.

## Resume

Start at the first match:
- Outcome `parked`: show what parked the unit. Interactive, ask the user whether the parked action took effect, did not, or should stay parked, record the answer, and continue from it. Unattended, stop with the outcome `parked`.
- PR `MERGED`: the end of step 6 (sync the default branch), then step 7, retrying anything the unit state lists as pending.
- An agent the unit state records as running: reattach as the reference describes, and never start a second one for the same role and attempt.
- A check watch the gate records as running: wait for it.
- A pending hand-off: reconcile it as step 5 describes.
- A gate recorded for the approved head, with the PR head still equal to it: continue step 6 from the gate. A gate for any other head is stale: clear it and the approval, and start a new round.
- PR `OPEN`: step 5. A round whose review result is recorded but not triaged is triaged. With no round at the current head, start one.
- Branch with commits ahead of the default branch but no PR: step 4. First commit leftover changes in the workspace that holds the branch as `wip: recover interrupted codex-lfg run`, and push.
- PR `CLOSED` unmerged: a closed PR is a decision someone made. Ask the user whether to start over on a fresh branch. Unattended, start over without asking on `<branch>-r<k>`, the first such name with no branch and no PR, record it with `bd update <id> --set-metadata codex_lfg_branch=<branch>-r<k>` for each issue, start a new unit state for it, and go to step 1.
- Nothing yet: step 1.

Report the step a run resumed at.

## Steps

1. **Plan.** With a plan, read it and use it as written; when it lacks acceptance criteria or verification commands, state the missing ones in the brief instead of editing the user's file. With issue ids, claim and mark each in one call, `bd update <id> --claim --set-metadata codex_lfg_branch=<branch>`, and read it back with `bd show <id> --json`. Without a plan argument, plan the issues as `Planning a task description` does, keyed by the issue ids instead of the text, with their titles, bodies, and acceptance criteria. The plan must name the bead ids, the acceptance criteria, and the verification commands.
2. **Workspace.** The backend reference sets up the workspace that will hold the branch. Only an exec Codex worker uses the coordinator's own checkout. In every other case the coordinator's checkout stays on the default branch.
3. **Delegate.** Write the build brief and start the worker as the reference describes, then set its deadline (see Deadline). The build brief says, in English:
   - Implement the plan at `<absolute plan path>` with the compound-engineering `lfg` skill on branch `<branch>`, creating it before the first commit if the workspace is on another branch.
   - Stop once a pull request against `<default>` is open with your commits pushed. Its body includes the line `codex-lfg unit: <branch>` and lists the bead ids, if any. Skip `lfg`'s CI watch (`ce-babysit-pr`); the coordinator owns review rounds and checks.
   - Do not merge, do not close or edit Beads issues, do not push to `<default>`, and do not rewrite history.
   - If you need a decision only the operator can make, commit and push what you have, then end your final message with a line starting `QUESTION:` that states the choices and your recommendation.
   - If blocked, stop and state the blocker in your final message.

   Tell the user what started and where to watch it: the Orca tab, or the log path. Then end the invocation with the outcome `in-flight`. The Orca wake or the background-task notification brings the run back here.
4. **Check the handoff.** Read the worker's result. A `QUESTION:` line goes to Questions below before anything else. Bind the PR. If the worker left commits but no PR, open it with `/compound-engineering:ce-commit-push-pr mode:pipeline babysit:off` from the workspace that holds the branch, then add the `codex-lfg unit: <branch>` line to its body. If the worker failed with no usable commits, retry it once with `WORKER_EFFORT=xhigh` and the failure reason added to the brief, as the reference describes. If that also fails, implement the plan yourself with `/compound-engineering:ce-work mode:return-to-caller` in that workspace, then open the PR as above. If an unattended answer from Questions below is missing from the PR body, add it.
5. **Review loop.** Each round:
   1. Fetch the branch and record the round in the unit state: its head is the PR's `headRefOid`, and its base is `git merge-base <the PR's baseRefOid> <head>`. Create the round's review checkout, `git worktree add --detach <state dir>/review/<branch slug>-<round> <head>`.
   2. Start a fresh reviewer on `REVIEWER_MODEL` as the reference describes. Its brief says: work only in `<review checkout>`; confirm `git rev-parse HEAD` is `<head>` and `git status --short` is empty, and if not, stop and say so; run `/compound-engineering:ce-code-review mode:agent base:<base> plan:<absolute plan path>` there and write its JSON result to `<result path>`; do not edit, commit, push, or comment. For a rebase round, the brief also names the ranges to compare: `git range-diff <old base>..<old head> <new base>..<new head>`.
   3. Accept the review only when the result file holds `status: complete`, a `findings` array, `scope.head_sha` equal to the round's head, and `scope.base` equal to its base, and the review checkout is still clean at that head. Otherwise retry the reviewer once, in a new round if the PR head has moved. When that also fails, the unit has failed: a round never passes without a usable review. Remove the review checkout once the round's result is settled.
   4. Triage each finding in the result. Accept a finding that is valid and within the plan or its acceptance criteria. Reject a finding that is wrong, a duplicate, or out of scope, and give the reason. A valid out-of-scope finding is filed in step 7.
   5. Post the round's ledger with `gh pr comment <n> --body-file <file>` and record the comment's ID. The ledger is headed `codex-lfg review round <n>`, carries the marker `references/state.md` names, and records the reviewed head SHA, the base SHA, the reviewer, the verdict, and each finding as accepted or rejected with its reason.
   6. With no accepted finding, the round is clean: record its head and base as the approved head and go to step 6. Otherwise hand the accepted findings to the worker.

   **Hand-off.** Fixes, failing checks or verification, and rebase requests all go to the same worker this way.
   - Before sending, count the hand-offs and retriggers already sent. At `ROUNDS`, do not send: ask the user whether to allow more, fix the rest yourself, or stop. Unattended, the unit has failed.
   - Record a pending hand-off: its round, its kind, the old head, an intent key, and for a rebase the target base SHA, `origin/<base>` after a fetch. Clear the approval and the gate; whatever the worker pushes needs a new review.
   - A fix brief says: apply exactly these changes on branch `<branch>` of pull request `<n>`, run the plan's verification commands, commit, and push; do not rerun `lfg`, open another pull request, or touch Beads. A rebase brief says: rebase the branch onto `<target base SHA>`, resolve conflicts, run the verification commands, and push with `git push --force-with-lease=refs/heads/<branch>:<old head> origin <branch>`; if the push is rejected, stop and say so. Either brief allows the `QUESTION:` line the build brief allows.
   - Send it as the reference describes, then edit the ledger comment to record the hand-off.
   - When the worker settles, read its result first: a `QUESTION:` line goes to Questions below, and a rejected rebase push parks the unit, since someone else pushed to the branch. Then compare the PR head with the old head. The hand-off is delivered when the head changed and, for a rebase, the target base is an ancestor of the new head (`git merge-base --is-ancestor`). A delivered hand-off starts the next round. An undelivered one is handed off once more, as a new operation with a new key, then the unit has failed.
6. **Gate, then stop or merge.** Record the gate with the approved head and base. Confirm the PR head still equals the approved head; otherwise the gate is stale, and a new round starts.

   Run the plan's verification commands in a clean detached checkout of the approved head, created and removed like a review checkout, and record the result. A failure is handed to the worker as a hand-off of kind `verify`.

   Then read the checks with `gh pr view <n> --json headRefOid,statusCheckRollup`, not from the exit code of `gh pr checks`, which fails when a PR has no checks. Checks can register late: when the first read is empty, read again after two minutes and again after five more.
   - **Checks present:** unless a recorded watch is still running, start `gh pr checks <n> --watch --fail-fast` as a background command, record it with a deadline 60 minutes out, and guard it with a timer (see Deadline). On its exit, its timer, or any entry, read the checks again and use them only when `headRefOid` equals the approved head. All passing completes the gate. A failing check is handed to the worker as a hand-off of kind `checks`; it is never bypassed. Still pending before the deadline, watch again; past the deadline, the unit has failed. A read or watch that errors is retried once; a second error in a row fails the unit with that cause.
   - **Still empty:** checks are expected when any workflow under `.github/workflows/` triggers on `pull_request`, `pull_request_target`, or `push`; when the base branch's head has check runs or statuses (`gh api repos/<owner>/<repo>/commits/<base>/check-runs --jq .total_count` and `gh api repos/<owner>/<repo>/commits/<base>/status --jq '.statuses | length'`); or when any of the last five merged pull requests had checks (`gh pr list --state merged --limit 5 --json statusCheckRollup`). Any of these calls that errors fails the unit with that cause; an error is not an empty answer. With no evidence, the repository has no CI: rerun the full local test, lint, and type gates in the gate checkout, and treat their pass as the gate. When checks are expected, retrigger them once per unit. A retrigger counts as a hand-off against `ROUNDS`. Make an empty commit on the approved head in the workspace that holds the branch, record its SHA as the intent, and push it. The new head starts a new round, so it is reviewed and gated like any other head. If the checks still do not appear on it after the same waits, the unit has failed with that cause.

   With `MERGE` off, stop here with the outcome `awaiting-merge` and report; tell the user that rerunning the same command with `merge` added resumes at this step and merges. With `MERGE` on, never use `--admin` or auto-merge. Merge one pull request at a time. Read `gh api repos/<owner>/<repo>/rules/branches/<base>` for the PR's base. When it lists a `merge_queue` rule, stop and report that this repository merges through a queue, which this skill does not drive. When the call errors, stop and report it. Right before merging:
   - The PR head must equal the approved head, and its base must be the bound base, or a new round starts.
   - Run `git fetch origin <base>`, record `origin/<base>` as the checked base tip, and require `git merge-base --is-ancestor origin/<base> <approved head>`. When it fails, the PR is behind its base: hand off a rebase.
   - `gh pr view <n> --json mergeStateStatus` must not read `BEHIND` or `DIRTY`, which the same rebase hand-off handles.

   Merge as the reference describes, pinned to the approved head. Confirm `gh pr view <n> --json state,mergeCommit` reads `MERGED` and record the merge commit. When its parent is not the checked base tip, another push landed on the base in between: after the sync below, run the verification commands on the default branch and report the result. Then `git switch <default> && git pull --ff-only` in the coordinator's checkout.
7. **Close.** Only after the PR reads `MERGED`, record the remaining work as pending in the unit state and do each item, marking it done when it lands. A later entry retries whatever is still pending:
   1. Close each issue still open with `bd close <id> --reason "Merged in #<n>"`, read it back with `bd show <id> --json`, and persist tracker changes the way this repository's Beads setup requires.
   2. Clean up the unit's workspace, branches, and agents as the reference describes.
   3. When the repository uses Beads, file each valid out-of-scope finding as a new P2-or-lower `tech-debt` issue that cites the PR; otherwise list it in the report.

   While anything is pending, the outcome is `merged`; when nothing is, it is `done`.

## Deadline

Every agent start has a deadline 90 minutes after it starts, and every check watch has the deadline step 6 gives it. Both are recorded in the unit state. On every entry to this skill, compare each running agent's or watch's deadline with the time now. When no timer this session started already guards it, start a background command that sleeps for the time left, record it, and name what it guards. Its exit only asks for an inspection. Ignore an exit for an agent or watch that is no longer current. Past an agent's deadline, apply the reference's hang rule.

## Questions from the worker

A question reaches the coordinator as an Orca question or, in exec, as a worker result ending with a `QUESTION:` line, in any phase: build, fix, or rebase. Answer from the plan and the repository. Ask the user only for a choice that is theirs: a scope change; a change to a contract, permission, or security stance; or starting over after a closed PR. Unattended, take the recommended option. Record every answer in the unit state, append it to each issue's notes with `bd update <id> --append-notes`, and tell the worker to put it in the PR body; step 4 checks that it is there. In exec, a question is not a failure: start the same phase again as a new attempt with the answer added to its brief.

## Failure

Take the recommended option on technical choices and record it in the PR body. When the unit cannot finish, record the cause and the outcome `failed`, then stop and report the cause, the branch, the PR, and the workspace and agents kept for inspection. Do not clean up a failed unit's workspace or agents. For issues, append the cause and the PR to each with `bd update <id> --append-notes` and release the claim with `bd update <id> --status open --assignee ''`, keeping `codex_lfg_branch` so a rerun resumes the same branch.

## Outcome and report

End every invocation by recording and stating the unit's outcome: `in-flight` while it waits on an agent, a check watch, or a timer; `awaiting-merge`; `merged` while step 7 has work pending; `done`; `failed`; or `parked`. `codex-delegate` acts on it.

The report states the input, the plan path, the branch, and the backend with its reason. It gives the worker, worker model, effort, and reviewer model, each with its source: an issue pin, an argument, or the config default, and the effective value the launch reported. It gives the worker outcome (success, retried, or replaced by Claude), the PR URL, the number of review rounds and hand-offs, the findings accepted and rejected, the approved head SHA, and the check result. Then it gives either the merge SHA and the cleanup result, or that the PR is open and awaiting `merge`. For issues, it gives each one's final state.
