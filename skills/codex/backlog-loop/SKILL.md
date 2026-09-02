---
name: backlog-loop
description: Clear a repository's Beads backlog autonomously in budget-sized batches by driving the current compound-engineering:lfg stages through their supported child-skill seams, with CI-aware merge gates. Explicit invocation only; run before the matching long-running goal.
---

Clear this repo's issue backlog autonomously, one batch at a time, until the tracker has no actionable non-epic issue. Never ask the user anything; when a choice arises take your recommended option and record it.

A batch is 1..N sibling issues sized against a complexity budget, so one LFG-compatible pipeline is neither a wasted trip for one 15-minute chore nor an unreviewable multi-hour PR. One batch = one plan = one branch = one PR = one merge.

This procedure is the outer loop and shipping authority. For every batch, read the available `compound-engineering:lfg` skill and drive its current stages through the documented `ce-plan`, `ce-work`, review, browser-test, ship, and babysit seams. Do not invoke LFG as an indivisible child: the loop must retain control at the plan boundary to resize the batch, and must be able to replace an unavailable CI watch with local gates. Resolve every named child skill against the host's available-skills list and use host-native invocation; never guess slash or dollar syntax. Never bypass a child skill's applicable gates.

## PREFLIGHT

Resolve from the repo, report once, then start. Stop if a REQUIRED item won't resolve.

- Child skills (REQ): resolve every skill this procedure invokes against the host's available-skills list -- `compound-engineering:lfg`, `compound-engineering:ce-plan`, `compound-engineering:ce-work`, `compound-engineering:ce-simplify-code`, `compound-engineering:ce-code-review`, `compound-engineering:ce-test-browser`, `compound-engineering:ce-doc-review`, `compound-engineering:ce-commit-push-pr`, `compound-engineering:ce-babysit-pr`. Any name that does not resolve -> stop before any other item, and name every unresolved skill in the stop report so it reads as a missing prerequisite rather than a tracker or forge failure. Resolve first: this is the cheapest check here and the only one whose failure would otherwise surface at step 5, after issues are claimed and a branch is cut.
- Tracker (REQ): `bd prime` and `bd ready` work -> beads. Else the repo's real tracker, mapping the bd commands onto it. No tracker -> stop. When repo instructions make Beads the sole task tracker, treat any platform-local task-list capability requested by a child skill as unavailable; do not create a second source of task state.
- Sync: `bd dolt push` only if a dolt remote exists; else skip.
- Forge (REQ): `gh` authed on this remote. Not GitHub -> stop.
- Default branch (REQ): `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`. Require one non-empty unqualified branch name such as `main`, never `origin/main` and never a hardcoded literal.
- CI availability (REQ, non-fatal): refresh remote refs with `git fetch origin --prune`, resolve `<default-sha>` with `git rev-parse origin/<default>`, then query `gh run list --branch <default> --commit <default-sha> --limit 3 --json conclusion,status,createdAt,headSha`. CI is UNAVAILABLE if any of: no run exists for that exact SHA; the newest matching run concludes `startup_failure`; or the Actions API returns a billing, quota, or spending-limit error. Record the initial observation, but step 1 re-probes every current trunk SHA because a backlog batch can add or repair CI. UNAVAILABLE is expected and pre-authorized; never ask the user to fix billing.
- Merge capability (REQ): query `gh api repos/{owner}/{repo}/branches/<default>/protection`. 404 -> unprotected. A 403 is unprotected only when the response exactly says branch protection requires a paid plan or public repository; any other 403 is an authorization failure and stops. On 200 inspect `.required_status_checks`: none -> direct merge works; required checks with initial CI available -> continue because the pipeline waits to CI-decided and step 6 requires green; required checks with initial CI unavailable -> stop because they can never turn green. If a later batch resolves `<batch-ci>=off` while required checks exist, stop before claiming it. Any other response stops. Never pass `--admin`.
- Drop `--delete-branch` if the repo forbids branch deletion.
- Quality gate set (REQ): read CLAUDE.md/AGENTS.md/CONTRIBUTING.md/README and record every unconditional gate plus every path-conditional gate. Else use the project's test command. Do not flatten a conditional gate into one command or omit it. For example, a repo declaring one command that runs on every change plus a second that runs only when changed files touch its data-access packages contributes two gates, not one: record the conditional gate together with the paths that trigger it, and evaluate that trigger against each batch's actual changed files. Child verification, post-merge verification, and the final report use this same gate set.
- Gate coverage: on the first `<batch-ci>=off` observation, read both `.github/workflows/*.yml` and `.github/workflows/*.yaml` when present. List every command each job runs and compare it against the full gate set. Report any command CI would have run that the gates do not. Gaps are informational, not a stop, but they must appear in the final report.
- Process hygiene (REQ): record `<cores>` from `sysctl -n hw.ncpu`, or `nproc` where that is the platform's command. Every gate, test, build, or app command this loop runs is launched non-interactively (`CI=1`, watch and UI modes off), inside its own process group, and under a hard deadline `<gate-timeout>=20m`: `perl -e 'setpgrp(0,0); exec @ARGV' -- timeout -k 30s <gate-timeout> <command>`. Where `timeout` is absent, keep the process group and enforce the deadline by killing that group. Append every launched leader PID to `<owned-pgids>`, the set the step 1 machine guard resets each iteration. Never leave a watcher, dev server, or REPL alive past the command that needed it; a command that returns while its group still exists is a reap target, not a success.
- Constraints: read the repo's CLAUDE.md/AGENTS.md non-negotiables; else its documented conventions.
- Worktree safety: inventory `git status --short` before any branch move and save every pre-existing dirty path as `<excluded-paths>`. Carry the list as context through planning, simplification, and review-fix commits; when non-empty, pass the documented `exclude:<comma-separated-paths>` carrier to `ce-commit-push-pr`. Do not pass that carrier to a child that does not document it: `ce-work` inventories pre-work WIP itself and must block on collisions. Verify excluded paths remain uncommitted before every push. Never reset, clean, stash, or use a tree-wide checkout to make the tree look clean. If planned work collides with an excluded path, stop the batch rather than absorbing or discarding it.
- Owner-decision issues: find by content (body asks for a product or design call), not by hardcoded id.

Choose a unique `<run-id>` once (an ISO UTC timestamp is enough). Tag every claimed member with `bd update <id> --set-metadata backlog_loop_run=<run-id>`; remove that metadata from members dropped before implementation. Final reporting queries this run marker instead of scanning all historical closed issues.

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

State lives in the tracker. Re-read `bd ready` every iteration; never work from a remembered list. Also inspect non-epic `in_progress` issues: resume only members carrying this run's marker; never steal somebody else's claim. If no ready work exists but an externally owned in-progress issue remains, stop and report that the backlog is not clear. A failed or blocked attempted batch is marked `blocked`, so it cannot be selected again silently. CI is batch-scoped and re-resolved from the exact current trunk SHA every iteration; it may change in either direction.

## ITERATION

1. **TRUNK HEALTH.**
   MACHINE GUARD, before touching git: run step 8 REAP against the previous batch's `<owned-pgids>`, which also covers an iteration that stopped early without reaping. Then read the 1-minute load average from `sysctl -n vm.loadavg`, or `uptime` where that is the platform's source. Above `2 x <cores>` -> reap again, re-read after 60s, and STOP with a report if it is still above that line: opening a batch on a saturated machine stacks another full test run on top of whatever is already pinning the CPU, and every gate below then times out on contention instead of on code. Green -> record `<iteration-start>` as the current time and reset `<owned-pgids>` to empty.
   Update trunk safely with `git fetch origin --prune`, `git switch <default>`, and `git merge --ff-only origin/<default>`. Never use reset or a tree-wide checkout.
   Resolve the current `origin/<default>` SHA and repeat the exact-SHA CI probe from preflight. Matching usable runs -> set `<batch-ci>=on`. No matching run, `startup_failure`, or billing/quota/spending failure -> set `<batch-ci>=off`. This decision is only for the current batch; re-probe next iteration so a batch that adds CI can move the following batch from off to on.
   `<batch-ci>=on`: if the newest completed matching run failed from code, STOP and report - never pile another merge onto a broken trunk. In-progress runs are fine; never wait for them here.
   `<batch-ci>=off`: LOCAL TRUNK GATE: run the unconditional quality gates. Skip them only when the previous iteration ended with a green POST-MERGE VERIFY and `origin/<default>` still resolves to that exact verified commit; record `trunk gate: skipped (verified <sha>)`. Green -> continue. Red -> STOP and report.

2. **PICK BATCH.** `bd ready --json --exclude-type=epic`. Skip `[epic]` containers; close an epic only when all children are closed.

   ANCHOR: highest priority P0->P4, then dependency depth (unblockers first).

   ESTIMATE: `bd show <id> --json` for the anchor and every candidate sibling; read `estimated_minutes`. Unset -> derive from the BATCH BUDGET rubric and write it back.

   ANCHOR SIZING:
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

3. **BASE.** Repeat the safe fetch/switch/ff-only update from step 1. Record the resulting `origin/<default>` commit as `<batch-base-sha>`. Every batch starts from freshly merged trunk without disturbing pre-existing dirty files.

4. **CLAIM.** `bd show <id>` for every member, then atomically claim each with `bd update <id> --claim` and set its run metadata. If any claim or metadata write fails, release every member claimed by this attempt back to open, clear its assignee and run metadata, then re-read `bd ready`; never continue with a partial batch.

5. **RUN THE PIPELINE, WITH TWO CHECKS AT THE PLAN BOUNDARY.**

   Compose a brief that lists each member as its own unit, `<id> | <title> | <description> | <design> | <relevant notes> | <acceptance criteria>`, and states plainly: one plan with one unit per issue, one branch, one PR covering all members. Include `<excluded-paths>` as caller-owned WIP that every child must leave untouched. For an owner-decision member, also map the chosen design entry into LFG's settled-decisions brief with decision, provenance `user-directed` (the explicit backlog-loop invocation authorizes its recommended-option rule), rejected alternative, and reason. Use `user-approved` only when the tracker proves approval. This makes the plan carry one U-ID per issue and preserves tracker decisions instead of flattening the batch into one vague blob.

   Read the current available LFG `SKILL.md`, `references/plan-brief.md`, `references/work-return.md`, `references/review-followup.md`, and `references/shipping-tail.md`; they own the stage contracts below. Act as a headless automated pipeline caller equivalent to LFG: no child may present a user menu or ask a question, and every child returns control to this loop.

   PIPELINE:
   1. Invoke `compound-engineering:ce-plan` with the composite brief and explicit headless pipeline context. Require its reported plan path, implementation-ready code metadata, confidence receipt, and completed non-interactive doc-review envelope. The single missing-path retry and every blocked/readiness rule come from LFG's `plan-brief.md`. Do not run a duplicate doc review when that envelope is complete; if it reports `skill_unreachable`, invoke `compound-engineering:ce-doc-review mode:non-interactive <reported-path>` once and require a valid return.
   2. Perform the plan-boundary checks below. When a member is removed, delete its unit and all now-orphaned requirements, acceptance evidence, verification mappings, dependency edges, and Definition-of-Done entries; then re-run `ce-doc-review mode:non-interactive` on the edited plan and require a coherent result.
   3. Read LFG's `work-return.md`, then invoke `compound-engineering:ce-work mode:return-to-caller <reported-path>`. Do not add the unsupported `exclude:` carrier; ce-work's workspace setup owns the pre-work WIP inventory and collision gate. Only a valid `status: complete` receipt advances.
   4. Read LFG's `review-followup.md`; run `compound-engineering:ce-simplify-code` with the plan structure-pin context and explicit caller-owned WIP exclusions unless LFG's docs-only/trivial skip applies. Then run the supported review invocation `compound-engineering:ce-code-review mode:agent base:<batch-base-sha> plan:<reported-path>`. Its base scope can still observe tracked pre-existing dirt, so filter the structured return before LFG steps 5-6: a finding whose changed evidence is exclusively in `<excluded-paths>` is out of scope, must be recorded in Coverage as caller-owned pre-existing WIP, and is neither applied nor handed off as a batch residual. A finding connecting an intended batch path to an excluded path remains in scope and blocks rather than editing the excluded path. Excluded paths are never staged by review-fix commits.
   5. Invoke `compound-engineering:ce-test-browser mode:pipeline` and honor its gate.
   6. Refresh remote refs and require `git rev-parse origin/<default>` still equals `<batch-base-sha>`; if trunk moved during the pipeline, block and STOP without merging so no stale-base result can ship. Build the final reviewed path set as the union of `git diff --name-only origin/<default>` (all tracked worktree/index/branch changes versus base) and `git ls-files --others --exclude-standard` (untracked files), then subtract `<excluded-paths>`. Run the applicable local quality gate set, selecting conditional gates from that complete path set rather than an earlier child receipt.
   7. Read LFG's `shipping-tail.md`, then invoke `compound-engineering:ce-commit-push-pr mode:pipeline branding:on babysit:off exclude:<excluded-paths>` when exclusions exist, otherwise omit the `exclude:` carrier. Thread the plan path, settled-decision conflicts, and residual section required by that reference. Require a pushed branch and open PR URL.
   8. `<batch-ci>=on`: invoke `compound-engineering:ce-babysit-pr mode:pipeline <pr-url>` and require its current structured CI-decided success contract. `<batch-ci>=off`: do not invoke the babysitter; the green local pre-PR gate is the batch authority.

   **Both checks below happen at the plan gate - after planning has written and reported a plan path, and before implementation reads that plan.** Neither is a separate later step; once implementation starts it is too late for either.
   - If no plan path was reported, its own gate has failed: treat the run as blocked and go to step 7's blocked path. Never hunt the filesystem for a plan it did not report.
   - **DOC REVIEW.** Require the non-interactive document-review state returned by pipeline step 1 and fold its Apply-routed findings into the plan. Do not review the same unchanged plan twice.
   - **RE-ESTIMATE AGAINST THE BUDGET** (batches of 2+ only). The batch was a hypothesis built from tracker metadata; the plan is the first real evidence about scope and code surface. Re-estimate each unit from what the plan says it actually touches.
     - Total > CEILING, or units touch disjoint code surfaces -> drop members from the tail (lowest priority, then deepest) until the batch is back under TARGET and the remainder shares a surface. Never drop the anchor.
     - Total still far under TARGET -> do NOT go back and grow; a second grow round costs a second plan, which is what batching exists to avoid. Record the miss.

     Dropping a member requires a referentially complete plan edit: **remove that unit and every artifact that exists only for it**, or the implementation step may still build it and the drop is fiction. Then release its tracker claim so it returns to `bd ready` with `bd update <id> --status=open --assignee="" --unset-metadata backlog_loop_run`; write the re-estimate back and record `<id> | returned to pool | re-estimated <old> -> <new> min`. A dropped member is NOT counted as attempted.

   Continue the pipeline after the boundary checks. A batch advances to merge only with valid stage receipts, an open PR URL, zero canonical `needs-human` residuals, and zero unchecked entries in `## Unapplied review findings`; those findings are undecided and cannot cross an autonomous merge gate. `<batch-ci>=on` additionally requires the babysitter's mergeable CI decision. `<batch-ci>=off` requires green applicable local gates on the final diff. Any blocked, failed, malformed, red-required-check, missing-PR, or decision-needed result takes the blocked path in step 7.

6. **MERGE AFTER THE SELECTED PIPELINE GATE.** With `<batch-ci>=on`, the babysitter already decided CI; do not add another watcher. With `<batch-ci>=off`, the final local pre-PR gate is the authority. Immediately before merge, refresh remote refs and require `origin/<default>` still equals `<batch-base-sha>`; if it moved after the gate, take the merge-blocked path instead of merging an untested base. Do not use GitHub auto-merge. Run `gh pr merge <url> --squash --delete-branch`, exactly one merge per batch. Never pass `--admin`. If merge fails for any reason, do not force or retry: for every member use `bd update <id> --status=blocked --append-notes="merge blocked: <reason> | <url>"`, sync when configured, count the batch blocked, and go to step 1.

7. **VERIFY, THEN CLOSE.** `<batch-ci>=off` only: safely update trunk with fetch/switch/ff-only, resolve the squash-merge SHA, derive final changed files with `git diff-tree --no-commit-id --name-only -r <merge-sha>`, then run the applicable quality gate set once against that commit. A squash merge produces a commit that was never tested on the branch. Red -> for every member use `bd update <id> --status=blocked --append-notes="post-merge verification failed: <gate> | <url>"`, sync, and STOP; never close an issue whose merged result leaves trunk red.
   Green, or `<batch-ci>=on` -> append calibration notes before closing: `bd update <id> --append-notes="actual: <k> files"`, taking `<k>` from the final PR/merge diff, including simplification and review fixes. Add elapsed minutes only when actually measured; never fabricate them. Then `bd close <id> --reason="<one line> | <url>"` for every member and sync.
   If the selected route returned blocked or failed in step 5, no retry: for every member use `bd update <id> --status=blocked --append-notes="pipeline blocked: <reason> | <url-if-any>"`, then sync. Every member counts as attempted.
   Either way print one line per member - `<id> | <title> | <url> | merged|blocked` - plus one `batch: <id>,<id>,... | est <n> min | actual <k> files` line.

8. **REAP.** Runs at the end of every iteration - merged, blocked, or stopped early - before step 1 of the next batch and before any early-stop report returns.
   - For every `<pgid>` in `<owned-pgids>` still listed by `ps -Ao pgid=`: `kill -TERM -<pgid>`, wait 5s, then `kill -KILL -<pgid>` if it survives. Kill the group, never the leader alone. A process group outlives its leader, so the group is what reaches workers that reparented to pid 1 when their runner exited.
   - Then sweep leftovers that escaped those groups. From `ps -Ao pid,ppid,lstart,command`, take only lines satisfying ALL of: `ppid` is 1, the command references this repo's root path, and the start time is at or after `<iteration-start>`. TERM, then KILL after 5s.
   - Never kill by tool name: no `pkill -f vitest|node|go|python|pytest`. Other agent sessions, other worktrees, and the user's own editors run those same binaries on this machine, and a name-wide sweep takes them down too. A runaway process matching no owned group and no repo path is reported, not killed.
   - Record `reaped: <n> group(s), <m> orphan(s)` on the batch line and list every killed command in the FINAL REPORT.

## OWNER-DECISION ISSUES

Don't skip them. They always run solo so one PR carries one decision. Pick your recommended option, preserve any existing design text, append `<decision> | rejected: <alt> | reason: <why>` to the design field, and add the `owner-decision` label for the user's audit. Never overwrite an existing design record.

## CONSTRAINTS

Preflight constraints hold on every diff. The applicable quality gate set is green before every PR, no exceptions. Everything written to repo, git, or tracker is English: identifiers, comments, error strings, test names, issue text, commits, PR bodies.

## STOP EARLY AND REPORT

Trunk health fails (`<batch-ci>=on`: the newest completed run failed; `<batch-ci>=off`: the local trunk gate is red); 3 consecutive BATCHES end blocked or failed; any id appears in two attempted batches; two merges fail in a row; the step 1 machine guard still reads above `2 x <cores>` after a reap and a 60s recheck.

## FINAL REPORT

Build it from `bd list --metadata-field backlog_loop_run=<run-id> --json` plus the touched issues' notes - not from memory and not from all historical closed issues. Include every decision made on the user's behalf. Report batch composition with its budget and batch-scoped CI state (`batch N: <ids> | CI on|off | est <n> min | actual <k> files | reaped <n>g/<m>o -> <pr url>`), every re-estimate drop and its reason, every `oversized` anchor, and every batch-level failure. For every `CI off` batch, state explicitly that no server-side verification backed its merge, list the local gate set actually run, and repeat the gate-coverage gaps found in preflight. Report any externally owned in-progress issue that prevented the backlog from being declared clear. List every process the reap killed, and every runaway process it reported and deliberately left alone.
