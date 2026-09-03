---
name: backlog-loop
description: Clear a repository's Beads backlog autonomously in budget-sized batches by driving the current compound-engineering:lfg stages through their supported child-skill seams, with CI-aware merge gates. Explicit invocation only; run before the matching long-running goal.
---

Clear this repo's issue backlog autonomously, one batch at a time, until the tracker has no actionable non-epic issue. Never ask the user anything; when a choice arises take your recommended option and record it.

A batch is 1..N sibling issues sized against a complexity budget, so one LFG-compatible pipeline is neither a wasted trip for one 15-minute chore nor an unreviewable multi-hour PR. One batch = one plan = one branch = one PR = one merge.

This procedure is the outer loop and shipping authority. For every batch, read the available `compound-engineering:lfg` skill and drive its current stages through the documented `ce-plan`, `ce-work`, review, browser-test, ship, and babysit seams. Do not invoke LFG as an indivisible child: the loop must retain control at the plan boundary to resize the batch, and must be able to replace an unavailable CI watch with local gates. Resolve every named child skill against the host's available-skills list and use host-native invocation; never guess slash or dollar syntax. Never bypass a child skill's applicable gates.

## PREFLIGHT

Resolve from the repo, report once, then start. Stop if a REQUIRED item won't resolve.

Choose a unique `<run-id>` first (an ISO UTC timestamp is enough): the process-hygiene item below stamps it onto every command this loop launches, and the tracker marker below carries it.

- Child skills (REQ): resolve every skill this procedure invokes against the host's available-skills list -- `compound-engineering:lfg`, `compound-engineering:ce-plan`, `compound-engineering:ce-work`, `compound-engineering:ce-simplify-code`, `compound-engineering:ce-code-review`, `compound-engineering:ce-test-browser`, `compound-engineering:ce-doc-review`, `compound-engineering:ce-commit-push-pr`, `compound-engineering:ce-babysit-pr`. Any name that does not resolve -> stop before any other item, and name every unresolved skill in the stop report so it reads as a missing prerequisite rather than a tracker or forge failure. Resolve first: this is the cheapest check here and the only one whose failure would otherwise surface at step 5, after issues are claimed and a branch is cut.
- Tracker (REQ): `bd prime` and `bd ready` must both work. Anything else -> stop, naming Beads as the missing prerequisite. Every step below issues literal `bd` commands for claims, estimates, metadata, notes, and closure; there is no supported mapping onto another tracker, and improvising a partial one leaves tracker state half-mutated at the first unmapped operation with no defined rollback. When repo instructions make Beads the sole task tracker, treat any platform-local task-list capability requested by a child skill as unavailable; do not create a second source of task state.
- Sync: `bd dolt push` only if a dolt remote exists; else skip.
- Forge (REQ): `gh` authed on this repo. Not GitHub -> stop. Resolve `<remote>`: the git remote whose fetch URL names the same `owner/repo` that `gh repo view --json nameWithOwner` reports. No remote matches, or more than one does -> stop. Use `<remote>` for every fetch and every `<remote>/<default>` reference below; the name `origin` is not guaranteed and a fork's `origin` is not the PR base repository.
- Default branch (REQ): `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`. Require one non-empty unqualified branch name such as `main`, never `origin/main` and never a hardcoded literal.
- CI availability (REQ, non-fatal): refresh remote refs with `git fetch <remote> --prune`, resolve `<default-sha>` with `git rev-parse <remote>/<default>`, then query `gh run list --branch <default> --commit <default-sha> --limit 3 --json conclusion,status,createdAt,headSha`. CI is UNAVAILABLE if any of: no run exists for that exact SHA; the newest matching run concludes `startup_failure`; or the Actions API returns a billing, quota, or spending-limit error. Record the initial observation, but step 1 re-probes every current trunk SHA because a backlog batch can add or repair CI. UNAVAILABLE is expected and pre-authorized; never ask the user to fix billing.
- Merge capability (REQ): query `gh api repos/{owner}/{repo}/branches/<default>/protection`. 404 -> unprotected. A 403 is unprotected only when the response exactly says branch protection requires a paid plan or public repository; any other 403 is an authorization failure and stops. On 200 inspect `.required_status_checks`: none -> direct merge works; required checks with initial CI available -> continue because the pipeline waits to CI-decided and step 6 requires green; required checks with initial CI unavailable -> stop because they can never turn green. If a later batch resolves `<batch-ci>=off` while required checks exist, stop before claiming it. Merge queue is a separate query, because it is not in this response and the response itself is unavailable on a private repository under a free plan: `gh api repos/{owner}/{repo}/rules/branches/<default>` returns 200 with a rule list on every plan and visibility, `[]` when none apply. Any entry whose `type` is `merge_queue` -> stop. On such a branch `gh pr merge` enables auto-merge or enqueues the PR instead of merging it, which step 6 forbids and cannot verify. Any other response stops. Never pass `--admin`.
- Drop `--delete-branch` if the repo forbids branch deletion.
- Quality gate set (REQ): read CLAUDE.md/AGENTS.md/CONTRIBUTING.md/README and record every unconditional gate plus every path-conditional gate. Else use the project's test command. Do not flatten a conditional gate into one command or omit it. For example, a repo declaring one command that runs on every change plus a second that runs only when changed files touch its data-access packages contributes two gates, not one: record the conditional gate together with the paths that trigger it, and evaluate that trigger against each batch's actual changed files. Child verification, post-merge verification, and the final report use this same gate set.
- Gate coverage: on the first `<batch-ci>=off` observation, read both `.github/workflows/*.yml` and `.github/workflows/*.yaml` when present. List every command each job runs and compare it against the full gate set. Report any command CI would have run that the gates do not. While `<batch-ci>=off` such a gap is not informational: nothing else verifies that command, so every uncovered workflow command joins the gate set actually run, and one that cannot be run locally stops the batch rather than merging unverified. Re-resolve the whole gate set whenever a batch changes CLAUDE.md/AGENTS.md/CONTRIBUTING.md/README or anything under `.github/workflows/`; a catalog read once at preflight goes stale the moment the loop edits the files that define it.
- Process hygiene (REQ): record `<cores>` from `sysctl -n hw.ncpu`, or `nproc` where that is the platform's command. Every gate, test, build, or app command this loop runs is launched non-interactively (`CI=1`, watch and UI modes off), inside its own process group, and under a hard deadline `<gate-timeout>=20m`: `perl -e 'setpgrp(0,0); exec @ARGV' -- timeout -k 30s <gate-timeout> <command>`. Where `timeout` is absent, keep the process group and enforce the deadline by killing that group. Export `BACKLOG_LOOP_RUN=<run-id>` into every such command so ownership stays provable after a runner dies. Append every launched leader PID to `<owned-pgids>`, the set the step 1 machine guard resets each iteration. Never leave a watcher, dev server, or REPL alive past the command that needed it; a command that returns while its group still exists is a reap target, not a success.
- Constraints: read the repo's CLAUDE.md/AGENTS.md non-negotiables; else its documented conventions.
- Worktree safety: inventory `git status --short` before any branch move and save every pre-existing dirty path as `<excluded-paths>`. Carry the list as context through planning, simplification, and review-fix commits; when non-empty, pass the documented `exclude:<comma-separated-paths>` carrier to `ce-commit-push-pr`. Do not pass that carrier to a child that does not document it: `ce-work` inventories pre-work WIP itself and must block on collisions. Verify excluded paths remain uncommitted before every push. Never reset, clean, stash, or use a tree-wide checkout to make the tree look clean. If planned work collides with an excluded path, stop the batch rather than absorbing or discarding it.
- Owner-decision issues: find by content (body asks for a product or design call), not by hardcoded id.

## CLEAN-TREE GATE RUN

Every gate whose result authorizes a merge -- the step 1 trunk gate, the step 5 pre-PR gate, and step 7 post-merge verification -- runs against a throwaway worktree at an exact commit, never in the working tree.

The working tree deliberately keeps `<excluded-paths>` dirty and is forbidden from cleaning them. Subtracting those paths from a changed-file list keeps them out of the PR; it does not keep them out of the build. A dirty config, stub, or source patch sitting beside the code is loaded by the very gate that decides whether to merge, so a green result there says nothing about the commit that ships.

- `git worktree add --detach <clean-tree> <sha>`, with `<clean-tree>` a fresh path outside this repository.
- If the gate set needs installed dependencies, run the repo's documented install or bootstrap command inside `<clean-tree>` first. A gate that cannot execute there has not passed and must not be recorded as green.
- Run the gates there under the same process-hygiene rules, including the run token and `<owned-pgids>`.
- `git worktree remove --force <clean-tree>` and `git worktree prune` when they finish, on the green path and the red path alike.

Tag every claimed member with `bd update <id> --set-metadata backlog_loop_run=<run-id>`; remove that metadata from members dropped before implementation. Final reporting queries this run marker instead of scanning all historical closed issues.

Do not resolve a plans directory here. `ce-plan`, under LFG's `plan-brief.md` contract, resolves its own artifact root and reports the path it wrote; step 5 uses that reported path and nothing else.

## BATCH BUDGET

```
TARGET   = 90 minutes of estimate   # fill a batch toward this
CEILING  = 150 minutes              # never admit a member that crosses this
CONCERNS = 4 members maximum        # review cost scales with concern count, not only size
```

Estimates come from the tracker's own field (`bd show --json` -> `estimated_minutes`). When an issue has none, derive one from this rubric and write it back with `bd update <id> --estimate <minutes>` so the next session starts from data instead of a guess:

| Shape of the issue | Minutes |
|---|---|
| Docs/config/copy only, one file | 15 |
| Bug with a clear repro, one module | 30 |
| Task with 1-3 acceptance criteria, one module | 45 |
| Feature, or anything crossing modules | 90 |
| Vague, or touching auth/payments/migrations/external contracts | 120, and treat as solo |

## STATE

State lives in the tracker. Re-read `bd ready` every iteration; never work from a remembered list. Also inspect non-epic `in_progress` issues and split them by the PRESENCE of `backlog_loop_run` metadata, never by its value. A fresh `<run-id>` is chosen every invocation, so an issue left behind by an interrupted earlier run can never carry the current one; matching on the value would file this tool's own abandoned claims as somebody else's and wedge the loop permanently on the first crash.

- Marker present: an earlier run of this procedure claimed it and did not finish. Recover it through THE RUN LEDGER below.
- Marker absent: externally owned. Never steal it. If no ready work exists and one of these remains, stop and report that the backlog is not clear.

## THE RUN LEDGER

Every fact a resumed run needs lives in tracker metadata on the batch's own members, because that is the only store that survives the process dying between two commands. Write these with `bd update <id> --set-metadata` for every member, at the moment the phase is reached and before the action the next phase depends on:

| key | written at | value |
|---|---|---|
| `backlog_loop_run` | CLAIM | `<run-id>` |
| `backlog_loop_phase` | each transition | `claimed`, `built`, `pr-open`, `merge-requested`, `merged`, or `verified` |
| `backlog_loop_base` | BASE | `<batch-base-sha>` |
| `backlog_loop_branch` | pipeline step 7 | the pushed branch name |
| `backlog_loop_head` | pipeline step 6 | `<batch-head-sha>`, the gated commit |
| `backlog_loop_pr` | pipeline step 7 | the PR URL |
| `backlog_loop_merge` | step 6 | `<merge-sha>`, once the PR reports `MERGED` |

RECOVERY, by the recorded phase. Read it before touching anything; the whole point is that an interruption between merging and closing must not look like an interruption before merging.

- `merged` or `verified`: the merge is proven. Finish the interrupted close - post-merge verification if `<batch-ci>=off` and `backlog_loop_merge` has not been verified, then the calibration note and `bd close` against `backlog_loop_pr`.
- `merge-requested`: the outcome is unknown, which is exactly what this phase exists to record. Query `backlog_loop_pr`. `MERGED` -> treat as `merged` above. Any other state -> reclaim, and report the PR as left open.
- `pr-open`, `built`, or `claimed`: nothing shipped. Reclaim. Never resume a half-built branch into a merge; the branch is left in place, named in the FINAL REPORT, and never merged by this run, because no gate receipt survived the interruption to say it was ever green.

Reclaim means `bd update <id> --status=open --assignee="" --unset-metadata backlog_loop_run --append-notes="reclaimed from interrupted run <old-run-id> at phase <phase>"`, plus unsetting every other ledger key, returning the issue to `bd ready`.

Before any of that, reap the dead run's escaped processes by its `<old-run-id>` token exactly as step 8 does; a killed runner leaves its children behind, and they will contend with this run's gates.

Two things are deliberately NOT in the ledger. The consecutive-blocked and consecutive-merge-failure counters reset on a new invocation: they bound one run's thrash, and a human choosing to start the loop again is a new decision, not a continuation. `<owned-pgids>` is in-memory by design, which is why every command also carries the run token - the token is what makes a dead run's processes findable when its PID list is gone. A failed or blocked attempted batch is marked `blocked`, so it cannot be selected again silently. CI is batch-scoped and re-resolved from the exact current trunk SHA every iteration; it may change in either direction.

## ITERATION

1. **TRUNK HEALTH.**
   MACHINE GUARD, before touching git: run step 8 REAP against the previous batch's `<owned-pgids>`, which also covers an iteration that stopped early without reaping. Then read the 1-minute load average from `sysctl -n vm.loadavg`, or `uptime` where that is the platform's source. Above `2 x <cores>` -> reap again, re-read after 60s, and STOP with a report if it is still above that line: opening a batch on a saturated machine stacks another full test run on top of whatever is already pinning the CPU, and every gate below then times out on contention instead of on code. Green -> record `<iteration-start>` as the current time and reset `<owned-pgids>` to empty.
   Update trunk safely with `git fetch <remote> --prune`, `git switch <default>`, and `git merge --ff-only <remote>/<default>`. Never use reset or a tree-wide checkout. Then require `git rev-parse HEAD` to equal `git rev-parse <remote>/<default>`. `--ff-only` succeeds and changes nothing when the local branch is AHEAD of the remote, so it does not by itself prove the two match; a local default branch carrying unpushed commits passes it untouched. Ahead -> STOP and report those commits without moving them. They are the user's, they were never offered to this loop, and branching from that HEAD would push and self-merge them inside the batch's PR.
   Resolve the current `<remote>/<default>` SHA and repeat the exact-SHA CI probe from preflight. Matching usable runs -> set `<batch-ci>=on`. No matching run, `startup_failure`, or billing/quota/spending failure -> set `<batch-ci>=off`. This decision is only for the current batch; re-probe next iteration so a batch that adds CI can move the following batch from off to on.
   `<batch-ci>=on`: if the newest completed matching run failed from code, STOP and report - never pile another merge onto a broken trunk. If the newest matching run is still in progress, wait for it under a bounded deadline of 10 minutes, re-reading every 30s; still undecided at the deadline -> STOP and report. An undecided run is not a green one: later probes only ever look at their own exact SHA, so a trunk failure ignored here is never observed again and every following batch stacks onto it.
   `<batch-ci>=off`: LOCAL TRUNK GATE: run the unconditional quality gates through CLEAN-TREE GATE RUN at the current `<remote>/<default>` SHA. Skip them only when the previous iteration ended with a green POST-MERGE VERIFY and `<remote>/<default>` still resolves to that exact verified commit; record `trunk gate: skipped (verified <sha>)`. Green -> continue. Red -> STOP and report.

2. **PICK BATCH.** `bd ready --json --exclude-type=epic`. Skip `[epic]` containers; close an epic only when all children are closed.

   ANCHOR: highest priority P0->P4, then dependency depth (unblockers first).

   ESTIMATE: `bd show <id> --json` for the anchor and every candidate sibling; read `estimated_minutes`. Unset -> derive from the BATCH BUDGET rubric and write it back.

   ANCHOR SIZING:
   - anchor is an owner-decision issue -> the batch is the anchor alone; skip GROW entirely, because OWNER-DECISION ISSUES below requires one PR to carry one decision. The GROW rule only bars an owner-decision *sibling*, so without this line the anchor's own case is left to the executor and two of them would batch it differently.
   - anchor estimate >= TARGET -> the batch is the anchor alone; admit nobody.
   - anchor estimate > CEILING -> still run it alone, and record `oversized` on its line and in the final report: that issue wants splitting, not batching. Never skip it, the loop must make progress.

   GROW (only when the anchor is under TARGET): take the anchor's parent epic from its `bd show --json`, then `bd ready --parent <epic-id> --json --exclude-type=epic`, ordered the same way. Admit a sibling only if ALL hold:
   - same parent epic as the anchor
   - same priority band
   - not an owner-decision issue
   - batch total + its estimate <= CEILING
   - resulting member count <= CONCERNS

   Stop growing once the batch total reaches TARGET. Otherwise the batch is the anchor alone. Never batch across epics. `bd ready` already excludes a sibling blocked by another unfinished issue.

   Record `batch estimate: <n> min across <k> issues`.

3. **BASE.** Repeat the safe fetch/switch/ff-only update from step 1. Record the resulting `<remote>/<default>` commit as `<batch-base-sha>`. Every batch starts from freshly merged trunk without disturbing pre-existing dirty files.

4. **CLAIM.** `bd show <id>` for every member, then atomically claim each with `bd update <id> --claim` and set its run metadata, including `backlog_loop_phase=claimed` and `backlog_loop_base=<batch-base-sha>`. If any claim or metadata write fails, release every member claimed by this attempt back to open, clear its assignee and run metadata, then re-read `bd ready`; never continue with a partial batch.

5. **RUN THE PIPELINE, WITH TWO CHECKS AT THE PLAN BOUNDARY.**

   Compose a brief that lists each member as its own unit, `<id> | <title> | <description> | <design> | <relevant notes> | <acceptance criteria>`, and states plainly: one plan with one unit per issue, one branch, one PR covering all members. Include `<excluded-paths>` as caller-owned WIP that every child must leave untouched. For an owner-decision member, also map the chosen design entry into LFG's settled-decisions brief with decision, provenance `user-directed` (the explicit backlog-loop invocation authorizes its recommended-option rule), rejected alternative, and reason. Use `user-approved` only when the tracker proves approval. This makes the plan carry one U-ID per issue and preserves tracker decisions instead of flattening the batch into one vague blob.

   Read the current available LFG `SKILL.md`, `references/plan-brief.md`, `references/work-return.md`, `references/review-followup.md`, and `references/shipping-tail.md`; they own the stage contracts below. Act as a headless automated pipeline caller equivalent to LFG: no child may present a user menu or ask a question, and every child returns control to this loop.

   PIPELINE:
   1. Invoke `compound-engineering:ce-plan` with the composite brief and explicit headless pipeline context. Require its reported plan path, implementation-ready code metadata, confidence receipt, and completed non-interactive doc-review envelope. The single missing-path retry and every blocked/readiness rule come from LFG's `plan-brief.md`. Do not run a duplicate doc review when that envelope is complete; if it reports `skill_unreachable`, invoke `compound-engineering:ce-doc-review mode:non-interactive <reported-path>` once and require a valid return.
   2. Perform the plan-boundary checks below. When a member is removed, delete its unit and all now-orphaned requirements, acceptance evidence, verification mappings, dependency edges, and Definition-of-Done entries; then re-run `ce-doc-review mode:non-interactive` on the edited plan and require a coherent result.
   3. Read LFG's `work-return.md`, then invoke `compound-engineering:ce-work mode:return-to-caller <reported-path>`. Do not add the unsupported `exclude:` carrier; ce-work's workspace setup owns the pre-work WIP inventory and collision gate. Only a valid `status: complete` receipt advances.
   4. Read LFG's `review-followup.md`; run `compound-engineering:ce-simplify-code` with the plan structure-pin context and explicit caller-owned WIP exclusions unless LFG's docs-only/trivial skip applies. Then run the supported review invocation `compound-engineering:ce-code-review mode:agent base:<batch-base-sha> plan:<reported-path>`. Its base scope can still observe tracked pre-existing dirt, so filter the structured return before LFG steps 5-6: a finding whose changed evidence is exclusively in `<excluded-paths>` is out of scope, must be recorded in Coverage as caller-owned pre-existing WIP, and is neither applied nor handed off as a batch residual. A finding connecting an intended batch path to an excluded path remains in scope and blocks rather than editing the excluded path. Excluded paths are never staged by review-fix commits. Require `status: complete`; a `degraded`, `blocked`, `skipped`, or malformed return takes the blocked path in step 7 -- a review whose reviewers all failed returns no findings, which is not the same as finding nothing. Then execute that reference's apply and residual-handoff stages before moving on, and reconcile every finding the review returned against either an applied fix or an entry in `## Unapplied review findings`. An absent section clears the merge gate only when the review returned no findings; a review that returned findings while that section is missing is unreconciled, not clean.
   5. Invoke `compound-engineering:ce-test-browser mode:pipeline` and honor its gate.
   6. Refresh remote refs and require `git rev-parse <remote>/<default>` still equals `<batch-base-sha>`; if trunk moved during the pipeline, block and STOP without merging so no stale-base result can ship. Commit every remaining batch change first, including review fixes, never staging `<excluded-paths>`, so the gate runs against exactly what will ship; `git status --porcelain` may then list nothing outside `<excluded-paths>`. Record the branch head as `<batch-head-sha>` and write `backlog_loop_head` plus `backlog_loop_phase=built` for every member. Build the final reviewed path set from `git diff --name-only <batch-base-sha> <batch-head-sha>` and subtract `<excluded-paths>`; if an excluded path appears in that diff it was committed by mistake, so block. Run the applicable local quality gate set through CLEAN-TREE GATE RUN at `<batch-head-sha>`, selecting conditional gates from that complete path set rather than an earlier child receipt. While `<batch-ci>=off` this set must also cover every workflow command found by preflight's gate-coverage read, re-resolved against this batch's own tree.
   7. Read LFG's `shipping-tail.md`, then invoke `compound-engineering:ce-commit-push-pr mode:pipeline branding:on babysit:off exclude:<excluded-paths>` when exclusions exist, otherwise omit the `exclude:` carrier. Thread the plan path, settled-decision conflicts, and residual section required by that reference. Require a pushed branch and open PR URL, then write `backlog_loop_branch`, `backlog_loop_pr`, and `backlog_loop_phase=pr-open` for every member.
   8. `<batch-ci>=on`: record the PR head, invoke `compound-engineering:ce-babysit-pr mode:pipeline <pr-url>`, and require its current structured CI-decided success contract. That contract authorizes the babysitter to commit and push fixes, and every gate above already ran, so re-read the PR head afterwards. Moved -> the new head has passed CI but has been through no code review, no browser test, and no local gate; return to pipeline step 4 for that head and repeat, at most twice, then block. Unchanged -> continue. `<batch-ci>=off`: do not invoke the babysitter; the green clean-tree pre-PR gate is the batch authority.

   **Both checks below happen at the plan gate - after planning has written and reported a plan path, and before implementation reads that plan.** Neither is a separate later step; once implementation starts it is too late for either.
   - If no plan path was reported, its own gate has failed: treat the run as blocked and go to step 7's blocked path. Never hunt the filesystem for a plan it did not report.
   - **DOC REVIEW.** Require the non-interactive document-review state returned by pipeline step 1 and fold its Apply-routed findings into the plan. Do not review the same unchanged plan twice.
   - **RE-ESTIMATE AGAINST THE BUDGET** (batches of 2+ only). The batch was a hypothesis built from tracker metadata; the plan is the first real evidence about scope and code surface. Re-estimate each unit from what the plan says it actually touches.
     - Total > CEILING, or units touch disjoint code surfaces -> drop members from the tail (lowest priority, then deepest) until the batch is back under TARGET and the remainder shares a surface. Never drop the anchor.
     - Total still far under TARGET -> do NOT go back and grow; a second grow round costs a second plan, which is what batching exists to avoid. Record the miss.

     Dropping a member requires a referentially complete plan edit: **remove that unit and every artifact that exists only for it**, or the implementation step may still build it and the drop is fiction. Then release its tracker claim so it returns to `bd ready` with `bd update <id> --status=open --assignee="" --unset-metadata backlog_loop_run`; write the re-estimate back and record `<id> | returned to pool | re-estimated <old> -> <new> min`. A dropped member is NOT counted as attempted.

   Continue the pipeline after the boundary checks. A batch advances to merge only with valid stage receipts, an open PR URL, zero canonical `needs-human` residuals, and zero unchecked entries in `## Unapplied review findings`; those findings are undecided and cannot cross an autonomous merge gate. `<batch-ci>=on` additionally requires the babysitter's mergeable CI decision. `<batch-ci>=off` requires green applicable local gates on the final diff. Any blocked, failed, malformed, red-required-check, missing-PR, or decision-needed result takes the blocked path in step 7.

6. **MERGE AFTER THE SELECTED PIPELINE GATE.** With `<batch-ci>=on`, the babysitter already decided CI; do not add another watcher. With `<batch-ci>=off`, the final local pre-PR gate is the authority. Immediately before merge, refresh remote refs and require `<remote>/<default>` still equals `<batch-base-sha>`, and require the PR's current head to still equal `<batch-head-sha>`; if either moved after the gate, take the merge-blocked path. Checking the base alone leaves the reviewed head unpinned, and anyone pushing to the PR branch in that window would have their unreviewed commit merged. Do not use GitHub auto-merge. Before issuing the merge, set `backlog_loop_phase=merge-requested` on every member: an interruption between the merge and the close is otherwise indistinguishable from an interruption before it, and THE RUN LEDGER's recovery reads exactly this phase to decide whether to finish the close or return the issue to the pool. Then run `gh pr merge <url> --squash --delete-branch --match-head-commit <batch-head-sha>`, exactly one merge per batch. Never pass `--admin`.

   A zero exit from that command is a request, not a merge: on a merge-queue branch `gh pr merge` enables auto-merge or enqueues the PR and still returns success. Poll `gh pr view <url> --json state,mergeCommit` every 30s under a bounded 10-minute deadline and require `state` to reach `MERGED`; record its merge commit as `<merge-sha>`, then write `backlog_loop_merge` and `backlog_loop_phase=merged` for every member. Any other terminal state, or the deadline expiring, takes the merge-blocked path -- and if auto-merge ended up enabled, run `gh pr merge <url> --disable-auto` first so the loop never walks away leaving an unattended merge armed. Closing issues on an unproven merge is how a tracker ends up clear while the code never landed. If merge fails for any reason, do not force or retry: for every member use `bd update <id> --status=blocked --append-notes="merge blocked: <reason> | <url>"`, sync when configured, count the batch blocked, and go to step 1.

7. **VERIFY, THEN CLOSE.** `<batch-ci>=off` only: safely update trunk with fetch/switch/ff-only, derive final changed files with `git diff-tree --no-commit-id --name-only -r <merge-sha>`, then run the applicable quality gate set once through CLEAN-TREE GATE RUN at `<merge-sha>`. A squash merge produces a commit that was never tested on the branch. Red -> for every member use `bd update <id> --status=blocked --append-notes="post-merge verification failed: <gate> | <url>"`, sync, and STOP; never close an issue whose merged result leaves trunk red.
   Green -> write `backlog_loop_phase=verified`. Green, or `<batch-ci>=on` -> append calibration notes before closing: `bd update <id> --append-notes="actual: <k> files"`, taking `<k>` from the final PR/merge diff, including simplification and review fixes. Add elapsed minutes only when actually measured; never fabricate them. Then `bd close <id> --reason="<one line> | <url>"` for every member and sync.
   If the selected route returned blocked or failed in step 5, no retry: for every member use `bd update <id> --status=blocked --append-notes="pipeline blocked: <reason> | <url-if-any>"`, then sync. Every member counts as attempted.
   Either way print one line per member - `<id> | <title> | <url> | merged|blocked` - plus one `batch: <id>,<id>,... | est <n> min | actual <k> files` line.

8. **REAP.** Runs at the end of every iteration - merged, blocked, or stopped early - before step 1 of the next batch and before any early-stop report returns.
   - For every `<pgid>` in `<owned-pgids>` still listed by `ps -Ao pgid=`: `kill -TERM -<pgid>`, wait 5s, then `kill -KILL -<pgid>` if it survives. Kill the group, never the leader alone. A process group outlives its leader, so the group is what reaches workers that reparented to pid 1 when their runner exited.
   - Then sweep only what this run provably owns: processes whose environment carries `BACKLOG_LOOP_RUN=<run-id>`, read with the platform's environment-listing form of `ps`. TERM, then KILL after 5s. Also remove any `<clean-tree>` worktree still registered by `git worktree list`.
   - Everything else is reported, never killed. Repo path plus start time is not ownership: a second agent session, another worktree, or the user's own detached dev server started from this same checkout matches both and would be terminated with their state lost. Never kill by tool name either: no `pkill -f vitest|node|go|python|pytest`, since other sessions run those same binaries on this machine.
   - Record `reaped: <n> group(s), <m> orphan(s)` on the batch line and list every killed command in the FINAL REPORT.

## OWNER-DECISION ISSUES

Don't skip them. They always run solo so one PR carries one decision. Pick your recommended option, preserve any existing design text, append `<decision> | rejected: <alt> | reason: <why>` to the design field, and add the `owner-decision` label for the user's audit. Never overwrite an existing design record.

## CONSTRAINTS

Preflight constraints hold on every diff. The applicable quality gate set is green before every PR, no exceptions. Everything written to repo, git, or tracker is English: identifiers, comments, error strings, test names, issue text, commits, PR bodies.

## STOP EARLY AND REPORT

Trunk health fails (`<batch-ci>=on`: the newest completed run failed, or is still undecided after the bounded wait; `<batch-ci>=off`: the local trunk gate is red); the local default branch is ahead of `<remote>/<default>`; the default branch requires a merge queue; a workflow command is uncovered by the gate set while `<batch-ci>=off` and cannot be run locally; a merge request never reaches `MERGED` within its deadline; 3 consecutive BATCHES end blocked or failed; any id appears in two attempted batches; two merges fail in a row; the step 1 machine guard still reads above `2 x <cores>` after a reap and a 60s recheck.

## FINAL REPORT

Build it from `bd list --all --limit 0 --metadata-field backlog_loop_run=<run-id> --json` plus the touched issues' notes - not from memory and not from all historical closed issues. Both flags are load-bearing: `bd list` hides closed issues unless `--all` is passed and returns at most 50 rows unless `--limit 0` is, so the plain form omits precisely the members a successful run has just closed. Include every decision made on the user's behalf. Report batch composition with its budget and batch-scoped CI state (`batch N: <ids> | CI on|off | est <n> min | actual <k> files | reaped <n>g/<m>o -> <pr url>`), every re-estimate drop and its reason, every `oversized` anchor, and every batch-level failure. For every `CI off` batch, state explicitly that no server-side verification backed its merge, list the local gate set actually run, and repeat the gate-coverage gaps found in preflight. Report any externally owned in-progress issue that prevented the backlog from being declared clear. List every process the reap killed, and every runaway process it reported and deliberately left alone.
