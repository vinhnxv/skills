# backlog-loop rationale

Why the rules in this skill's `SKILL.md` exist, and the incidents behind them. Nothing here is a rule: every rule, table, constant, ledger key, and command lives in `SKILL.md`, and this file adds none. Entries are keyed by the `SKILL.md` section heading, then by the rule they explain. Steps are cited `I<n>` for the numbered ITERATION steps and `P<n>` for the numbered PIPELINE steps inside I5.

This is the rationale of this skill, not of LFG: the `references/` files LFG owns (`plan-brief.md`, `work-return.md`, `review-followup.md`, `shipping.md`) are a different directory.


## Opening paragraphs

- **A batch is 1..N sibling issues.** Batches are sized against a complexity budget so that one LFG-compatible pipeline is neither a wasted trip for one 15-minute chore nor an unreviewable multi-hour PR.
- **Do not invoke LFG as an indivisible child.** LFG is not invoked as an indivisible child because the loop must retain control at the plan boundary to resize the batch, and must be able to replace an unavailable CI watch with local gates.

## PREFLIGHT

- **Child skills and contracts: stop condition.** This is the cheapest check here and prevents a missing stage contract from surfacing only after issues are claimed and a branch is cut.
- **Tracker.** There is no supported mapping onto another tracker because improvising a partial one leaves tracker state half-mutated at the first unmapped operation, with no defined rollback.
- **Forge: `origin` only.** A correctly resolved `upstream` would pass every other check and then fail at shipping with the batch already claimed and built. Resolving the remote rather than assuming it is still what makes the mismatch a preflight stop instead of a late failure, and it is what keeps `<remote>/<default>` correct if a checkout has several GitHub remotes.
- **CI probes.** A commit carries one run per workflow, so reasoning about a singular newest run lets a fast lint workflow speak for a slow test workflow that is still running or already red.
- **Merge capability: paid-plan 403.** Measured 2026-09-04: a private repository under a free organization plan answers 403 `Upgrade to GitHub Pro or make this repository public` on `/protection`, `/rulesets` and `/rules/branches/<default>` alike, so that exact 403 reads as no applicable rules. Neither protection nor a ruleset can exist on that plan and visibility.
- **Quality gate set.** Isolating where a gate RUNS while selecting it from a checkout that deliberately keeps `<excluded-paths>` dirty leaves the whole point undone: an uncommitted edit to AGENTS.md swapping `npm test` for `npm run smoke` makes the loop record and run the weaker command against the exact commit and merge code the committed gate rejects.
- **Quality gate set: conditional gate example.** For example, a repo declaring one command that runs on every change plus a second that runs only when changed files touch its data-access packages contributes two gates, not one.
- **Gate coverage.** A catalog read once at preflight goes stale when the loop edits the files that define it.
- **Process hygiene: run token.** A child cannot be wrapped in the process-group launcher, so the token is the only ownership it gets.
- **Process hygiene: restated sentence.** Never leave a watcher, dev server, or REPL alive past the command that needed it; a command that returns while its group still exists is a reap target, not a success.
- **Owner-decision issues.** The owner-decision scan cannot run in preflight because no census has classified anything yet, and a content scan that runs first is exactly how a gate asking for a production approval gets read as a product call and shipped.

## CLEAN-TREE GATE RUN

- **Lead paragraph (why a clean tree).** Any worktree this loop works in may keep `<excluded-paths>` dirty, and the loop is forbidden from cleaning them. Subtracting those paths from a changed-file list keeps them out of the PR; it does not keep them out of the build. A dirty config, stub, or source patch sitting beside the code is loaded by the very gate that decides whether to merge, so a green result there says nothing about the commit that ships.
- **`<clean-tree>` identity.** A path invented per gate has no identity after a crash: the worktree stays registered, its installed dependencies stay on disk, and no later run can tell which registered worktree was whose.
- **Default Compose project.** The repository's default Compose project is never reused because ownership must remain exact after the runner dies.
- **`<worktree-root>` location.** "Outside this repository" alone is ambiguous from a linked worktree, where the linked path and the main path are both checkouts.
- **`<trunk-tree>` is detached.** The trunk tree is detached on purpose: it holds no branch, so it never collides with the operator's checkout of `<default>`.
- **Bootstrap in every run-owned worktree.** A fresh worktree carries no installed dependencies, so verification and the `ce-test-browser` server would fail there and the failure would be charged as a batch block.
- **Tracked change after bootstrap.** A bootstrap that regenerates a checked-in artifact turns the gate into a test of locally regenerated content that is then deleted with the worktree, while the stale committed version is what merges.
- **Compose cleanup trap.** A trailing `docker compose down` line is not equivalent because `set -e`, a timeout, or any earlier failure skips it.
- **Compose teardown before removal.** A failed teardown keeps the worktree because deleting the tree first loses the Compose file needed to bring the project down.
- **Run marker.** Tagging every claimed member lets final reporting query this run marker instead of scanning all historical closed issues.

## BATCH BUDGET

- **Estimate write-back.** The estimate is written back so the next session starts from data instead of a guess.

## STATE

- **Split by presence of `backlog_loop_run`.** A fresh `<run-id>` is chosen every invocation, so an issue left behind by an interrupted earlier run can never carry the current one; matching on the value would file this tool's own abandoned claims as somebody else's and wedge the loop permanently on the first crash.

## THE RUN LEDGER

- **Why the ledger lives in tracker metadata.** Every fact a resumed run needs lives in tracker metadata on the batch's own members because that is the only store that survives the process dying between two commands.
- **LIVENESS consequences.** A finished run therefore never blocks the next invocation, and a parked member never reads as a live run.
- **LIVENESS, overlapping invocations.** Two overlapping scheduled invocations would otherwise each treat the other as wreckage, kill its running gates, and rebuild its work while it is still moving toward its own merge.
- **HEARTBEAT REFRESHER.** One long child stage (`ce-work`, a babysit, the merge poll) outlasts the 30-minute window, and a child carries no run token, so a heartbeat written only at step boundaries lets a sibling invocation read a live run as dead and reclaim its work.
- **RECOVERY intro.** The point of reading the phase first is that an interruption between merging and closing must not look like an interruption before merging.
- **`pr-open`, `built`, `claimed` arm.** A branch with no PR carries no review or gate receipt, so it is rebuilt rather than resumed into a merge.
- **Heartbeat on every `blocked` write.** A parked member is not running, and a fresh heartbeat left on it reads as a live run for 30 minutes, which makes LIVENESS stop the next invocation over work nobody is doing.
- **ADOPTION: named status and assignee.** The status and assignee are named because `bd heartbeat` refuses a `blocked` issue and `--claim` cannot be combined with `--if-status`.
- **Parking an open PR.** Rebuilding an issue whose PR is open could create a duplicate PR.
- **Reclaim keeps DURABLE keys.** Keeping every DURABLE key keeps a rebuild cycle bounded and a quarantined issue quarantined.
- **Reap before reclaim.** A killed runner leaves its children behind, and they contend with this run's gates.
- **No run-global counter.** A scoped failure parks its members and CENSUS continues to independent work; an event count does not prove the remaining work is impossible.
- **Attempt count bounds an issue.** The attempt count bounds one issue across its whole life so a scheduled loop cannot rebuild the same failure forever.

## CENSUS

- **Intro: why one shared section.** A shared section removes drift between two texts; it does not by itself make a model deterministic, which is why every test below is a lookup over recorded fields rather than a reading.
- **Intro: empty ready list.** An empty ready list has at least six causes and only one of them is "finished", so nothing in this section infers termination from it.
- **`<census-run>` is a separate key.** `<census-run>` is a separate key from the claim marker because "claimed by this run" is itself a category below; reusing one key would make the categories overlap.
- **ENUMERATE: every flag is load-bearing.** Without `--limit 0` the query returns at most 50 rows, without `--include-gates` it omits native gate issues entirely, and without `--all` it omits `pinned` issues, because `--pinned` filters a different attribute and does not surface them. `--all` also returns the repository's whole closed history, which is why discarding closed rows is part of the query and not an afterthought.
- **The ready explanation is the authority for dependencies.** The tracker propagates blocking through a blocked parent, so a child whose only edge is `parent-child` to an open epic is offered as ready when that epic is ready and withheld when it is blocked, and no walk over an issue's own edge list can see that. Re-deriving it produced four ready issues on a backlog where the tracker reported one.
- **Metadata is not relied on in the enumeration.** One query per marker key is five queries whatever the backlog's size, where reading the same fact per issue would be one `bd show` per issue and would put the census's cost on the tracker's.
- **BACKFILL runs first.** BACKFILL runs before the precedence walk because rows 6 and 7 read the cause key, and a blocked issue that reaches the walk without one would otherwise be filed by a key that is merely missing.
- **BACKFILL: one exception.** This is the one place the procedure reads its own prose to decide a class, and the bounds above are what stop the exception spreading.
- **CLASSIFY: precedence walk.** Walking the table top-down and stopping at the first match files an issue that satisfies several rows once, and files the same issue the same way on every run.
- **CLASSIFY: why each row sits where it does.** Every ordering above is load-bearing, and each one exists because the opposite order sends work somewhere destructive:

  - Rows 1 and 2 sit above everything because a gate must never be claimed whatever else is true of it, and a mislabeled gate must not fall through to `ready` and get built.
  - Row 3 sits above the rest because a quarantined issue is waiting on a person's eyes, not on the loop, and any lower row would put it back in the pool the quarantine exists to keep it out of.
  - Rows 6 and 7 sit above row 8 so that an issue THIS run blocked is filed as blocked rather than as still claimed. Below row 8 they would be shadowed entirely, and every self-block this run wrote would stay in the loop-responsible set, so the run could never report the backlog clear.
  - Rows 6 and 7 also sit above rows 13 and 14 because an issue this loop blocked can also carry a dependency edge, and the loop's own wreckage is the actionable half of that pair.
  - Row 13 sits above row 14 because a `blocked` issue that no dependency explains is not dependency-blocked, and filing it as though it were hides it among issues that will clear themselves. It is a block written by an earlier form of this procedure, before any marker was recorded -- the legacy population BACKFILL describes -- and it is recognized the way everything else here is, from the ABSENCE of fields rather than from reading the note: no marker to own it, and no unmet dependency to explain it. The note is reported, never tested. A block a person wrote by hand has the same shape and gets the same treatment, which is correct: both need a person, and neither is this loop's to reopen.
  - Rows 9, 10, and 11 sit above row 12 because this procedure never writes `hooked`, `pinned` or `deferred`: a status it does not write was written by a person or by a sibling skill, so the dead marker underneath one is residue lying beneath a parking decision somebody has already made. Below row 12 that issue is filed as this loop's own wreckage instead, and RECOVERY returns it to `open` -- putting it straight back in the pool the person removed it from, on every run that meets it. The second cost is quieter and it is what wedged the loop: while the parked rows sat below `dep-blocked`, a parked issue with an unmet dependency on ready work was counted `dep-blocked` and walked transitively into the loop-responsible set, so no run could ever report the backlog clear.
  - Row 12 exists because rows 4, 5, and 8 between them do NOT cover an issue left `in_progress` by a run that has since died: row 4 requires that run to be live, row 5 requires no marker at all, and row 8 requires the marker to be this run's. Without row 12 such an issue reaches row 15 and is offered as ready work, and the loop claims an issue that may still have an open PR -- the exact double-shipping THE RUN LEDGER warns about.
  - Row 12's status test is an exclusion list -- not `blocked`, `hooked`, `pinned` or `deferred` -- rather than a list of the statuses this procedure writes, because the tracker accepts operator-defined statuses this table does not enumerate. A status with no row of its own must keep reaching row 12 and therefore RECOVERY. A closed list would let an unknown status fall through to row 15 and be claimed, which is the double-shipping row 12 exists to prevent.
- **Marker presence versus value.** Confusing the presence rule and the value rule is what wedges the loop.
- **EMIT: same output for fixture and operator.** The shape is exact so a fixture suite and an operator read the same output.
- **EMIT: no blank third field.** Every category has a cause so no line is ever left with a blank third field.
- **ACCOUNT FOR THE COUNT.** The census line count and the enumerated row count differ only if a per-issue read failed, and such a read can fail without saying so -- one `bd show` in fifty-three returned nothing on a live tracker, silently, and a run that did not count would have reported a backlog one issue smaller than it is.
- **ACCOUNT FOR THE COUNT: verify, do not assert.** The census claims to have accounted for every issue, so it verifies that claim rather than asserting it.
- **Header line prefixes.** A header that also began `census ` would be indistinguishable from a data line to anything counting them, and a reader downstream would report one more issue than the tracker holds.
- **LOOP-RESPONSIBLE SET.** Counting `quarantined` would make a run that quarantined anything unable to ever report the backlog clear. `legacy-blocked` is excluded for a stronger reason: reopening one means overriding a decision an earlier run recorded and a person has not revisited, and the recorded reasons are routinely ones no later run can re-derive -- a release boundary the epic declares, a collision with work its caller owned, a unit no agent can build. Reopening those rebuilds what somebody deliberately stopped.
- **WRITE GATE: repair ceiling.** Letting an unrelated run of gate repairs stall recovery would leave blocked work unreopened for a reason that has nothing to do with it.
- **WRITE GATE: census heartbeat.** Without the census heartbeat the check above is unarmed: `backlog_loop_heartbeat` is first written at CLAIM, so two invocations that start together both find no live run and both mutate. The value carries `<census-run>` and not a bare timestamp because ownership has to be decidable from the field alone: a run that published an unattributable heartbeat and then re-read it would read its OWN heartbeat as a competitor's and skip every pass it had just armed, which is a deadlock that gets worse the more correctly the rest of the rule is followed.
- **WRITE GATE: re-read per mutation.** Re-reading before each individual mutation means a run that went live in between is not invisible for the rest of the pass.
- **Repairs are idempotent.** The ledger's premise is that recovery facts live on a batch's own members, and a census has no members, so there is no natural key to phase repairs against.
- **Repairs are idempotent: no partial state.** Re-reading current state leaves no partial-completion state to reason about.
- **REOPEN PASS: no cause is exempt.** Without a count that never resets, a scheduled loop rebuilds the same failure forever.
- **REOPEN PASS: stale PR link.** Reopening preserves every metadata key it does not name, so a stale `backlog_loop_pr` left behind would be read as this run's own PR at the next claim.
- **REOPEN PASS: census stamp.** The `backlog_loop_census` stamp is what lets `## FINAL REPORT` find the issues a census touched without re-deriving them, and stamping only the issues actually written keeps the marker meaning "this census changed this issue".
- **RESIDUE PASS: parking decision stands.** An earlier run wrote it and stopped; the parking decision under it is somebody else's and stands.
- **RESIDUE PASS: heartbeat goes with the run key.** The heartbeat goes with the run key because both are RUN class: a heartbeat with no run to own it is a timestamp no rule reads.
- **RESIDUE PASS: no status flag.** The status is the parking decision this pass exists to leave standing; a pass that repaired residue and also reopened the issue would undo the very decision that told it the residue was residue.
- **RESIDUE PASS: the PR is not retired.** `backlog_loop_pr` is only ever written by this procedure for its own batch, and that batch may hold members that are not parked, so closing the PR would discard their work.
- **REPORT: legacy-blocked note.** A legacy-blocked issue's note is the only record of why it was stopped, and a person cannot decide without it.
- **REPORT: mutations are always printed.** A run that mutates a person's tracker and does not say so is the failure this section exists to prevent.
- **REPORT: two figures.** One combined number hides the pairing an operator most needs: a ready issue sitting in front of a gate is where a person-minute buys the most agent work.
- **DIAGNOSTIC RUN: readonly.** The flag means a write is refused by the tracker rather than merely avoided by this prose.
- **DIAGNOSTIC RUN: gating items.** The forge, default-branch, CI, and merge-capability items do not gate a diagnostic run because diagnosing a backlog must work in a repository this loop could never merge into.

## ITERATION

- **I1 machine guard: saturated machine.** Opening a batch on a saturated machine stacks another full test run on top of whatever is already pinning the CPU, and every gate below then times out on contention instead of on code.
- **I1 machine guard: heartbeat renewal.** A stale heartbeat is what lets the next invocation tell an abandoned run from a live one, so it is renewed on a schedule and at every boundary, never written once at CLAIM.
- **I1: POST-MERGE VERIFY term.** "POST-MERGE VERIFY" is not a section or a state of this skill. Earlier text used it for the exact-merge verification of I7 (VERIFY, THEN CLOSE); the I1 skip of the pending local trunk gate applies only when that verification was green at the exact commit trunk still resolves to.
- **I2: ANCHOR SIZING owner-decision.** The GROW rule only bars an owner-decision *sibling*, so without this line the anchor's own case is left to the executor and two of them would batch it differently.
- **I2: pool.** `quarantined` and `abandoned-claim` are separate categories, so neither can reach the pool and no subtraction is needed at selection.
- **I3: BASE.** I3 repeats I1's trunk update so every batch starts from freshly merged trunk without disturbing pre-existing dirty files.
- **I5: brief.** Listing each member as its own unit makes the plan carry one U-ID per issue and preserves tracker decisions instead of flattening the batch into one vague blob.
- **P4: review that returns no findings.** A review whose reviewers all failed returns no findings, which is not the same as finding nothing.
- **P4: apply stage pushes.** LFG's apply stage pushes the branch when a remote exists, which would publish it at phase `claimed`, and a crash then leaves a remote branch RECOVERY cannot find.
- **P5: browser test working directory.** The skill starts its own server from its working directory, so an invocation from the invoking tree serves that tree with its dirty `<excluded-paths>`, and the background server it leaves behind is findable only by its port.
- **P5: browser-affected decision.** `ce-test-browser` starts its server from a fixed launcher list before it maps changed files to routes, so a repository with no web surface cannot start one and every backend-only batch would stop on a gate that has nothing to test. Deciding from the batch's path set first makes an empty route list a pass, while a UI batch whose server cannot start still stops rather than being waved through.
- **P5: working-tree runtime config.** Run against the working tree and an excluded uncommitted runtime config - a mock auth path, a stub endpoint - is loaded by the browser, passes, and is absent from the PR.
- **P6: stale base.** Blocking without merging when trunk moved means no stale-base result can ship.
- **P6: commit before gate.** Committing every remaining batch change first means the gate runs against exactly what will ship.
- **P6: head-only pull_request workflow.** The head trigger alone does not establish that GitHub will run a `pull_request` workflow introduced only at the batch head for this PR.
- **P7: shipping-requested.** `shipping-requested` is written before invoking the child because the push and the PR it creates are irreversible and the ledger must already know they might exist.
- **P7: PR base check.** A PR opened against another base merges nothing into trunk while every base-and-head guard below still passes.
- **P8: CI-off empty rollup.** The babysitter's pipeline success needs at least one observed check, and on a repository that runs pull-request CI nowhere the rollup stays empty for the life of the PR, so every loop PR would end at the babysitter's time budget and never reach the merge gate. The exception re-evaluates the babysitter's own success terms minus that one, so a conflict, unresolved feedback, a base or stack blocker, or a moved head still stops the PR, and the exact-head local gates and I7's exact-merge verification stay the evidence that replaces CI.
- **I5: re-estimate hypothesis.** The batch was a hypothesis built from tracker metadata; the plan is the first real evidence about scope and code surface.
- **I5: no second grow round.** A second grow round costs a second plan, which is what batching exists to avoid.
- **I5: referentially complete drop.** A drop that leaves the unit or its artifacts in the plan is fiction, because the implementation step may still build it.
- **I6: guarded merge head pin.** Checking the base alone leaves the reviewed head unpinned, and anyone pushing to the PR branch in that window would have their unreviewed commit merged.
- **I6: merge-requested before the merge.** An interruption between the merge and the close is otherwise indistinguishable from an interruption before it, and THE RUN LEDGER's recovery reads exactly this phase to decide whether to finish the close or return the issue to the pool.
- **I6: exit status decides nothing.** A zero exit is a request, not a merge: on a merge-queue branch `gh pr merge` enables auto-merge or enqueues the PR and still returns success. A non-zero exit is not a failure either: GitHub can complete the squash merge and the connection drop before the response arrives.
- **I6: members stay in_progress.** Recovery scans `in_progress`, not `blocked`, so moving members early strands a merge that may have succeeded.
- **I6: merge proven on trunk.** The ancestry check proves the commit is on the branch this loop was working against and not merely merged somewhere.
- **I8: recycled PGID.** A PID and therefore a PGID is recycled, so a recorded number alone can name the user's unrelated build started after this run's own group exited.
- **I8: kill the group.** A process group outlives its leader, so the group is what reaches workers that reparented to pid 1 when their runner exited.
- **I8: everything else is reported.** A second agent session, another worktree, or the user's own detached dev server started from this same checkout matches both repo path and start time, and would be terminated with their state lost.
- **I8: never kill by tool name.** Other sessions run those same binaries on this machine.

## HUMAN GATES

- **RECOGNITION: label signal.** A label is queryable in the same pass that finds the issue, and its absence is a fact rather than a reading.
- **RECOGNITION: `[HUMAN]` prefix.** The `[HUMAN]` prefix is a human convention that no query can rely on, which is why it protects but does not certify.
- **RECOGNITION: author-only labels.** The never-write invariant is what makes the declaration below mean something: a label carries no author, no timestamp, and no namespace, so nothing at read time can tell this loop's own writing from a person's. The only defense is never to write it, and to record what was observed so a later mistake is at least visible.
- **Recognition before the owner-decision scan.** A gate and an owner-decision issue look alike from the body text -- a gate asking for a production approval reads like a product call -- and `## OWNER-DECISION ISSUES` says not to skip those and to pick a recommended option, which on a gate means shipping the thing a person reserved.
- **REPORTING: incomplete gate.** An empty gate is reported as incomplete because a gate nobody can act on blocks as hard as one nobody has seen.
- **REPAIR: provable from absence.** The contradiction is provable from a field's absence rather than from reading prose.
- **REPAIR: declaration is the label.** A rule that turns on a reading is a rule the executor decides differently on different days.
- **ADOPTION GATE.** The adoption gate is not caution for its own sake -- the label is introduced by this procedure, so on the day it ships no gate can carry one, and an unguarded first run would strip every gate edge in the tracker including the ones a person meant.
- **REPAIR: native gate.** Blocking is the whole of what a native gate is for.
- **REPAIR SEQUENCE: write before the destructive step.** The reason is the one P7 gives for writing `shipping-requested` before invoking the child: the record has to exist before the thing it explains can disappear. That includes the quarantine, not just the removal record: the quarantine is what keeps the freed issue out of the pool, and an issue whose edge is gone and whose quarantine was never written is indistinguishable from ordinary ready work, so the loop would build and merge exactly the thing the gate was holding back, with the evidence already deleted.
- **REPAIR SEQUENCE 1: two-part record.** The removal record is written in two parts because one metadata key cannot hold several records and a gate can hold several issues.
- **REPAIR SEQUENCE 1: notes append.** Notes append, so a second repair on the same gate cannot overwrite the first one's record. Recording the labels observed at decision time is what makes a later mistaken `hard-blocker` detectable after the fact, since nothing can prevent one at read time.
- **REPAIR SEQUENCE 1: metadata list.** A key per edge is not available: a metadata key may not contain `-` or `:` while every issue id does, so the list has to be a value that round-trips.
- **REPAIR SEQUENCE 2: release condition check.** Requiring the release condition is what makes the check mean anything on a gate whose acceptance was empty -- the empty string is a substring of every value including an empty one, so the original-text half alone passes vacuously on precisely the gates that carry the least information.
- **REPAIR SEQUENCE 4: quarantine.** The marker is durable on purpose -- "until the next invocation" buys nothing under a loop that runs on a timer, where the next invocation arrives an hour later and nobody has read anything. Until it is cleared the work waits, which is the point: a person gets to see the edge disappear before the code that edge was holding back reaches trunk.
- **REPAIR SEQUENCE 5: dependent first.** Because the swapped command exits 0 and changes nothing, a swapped repair would rewrite the gate's acceptance, quarantine the dependent, report a successful repair, and change nothing -- and the skip test above would then treat the edge as repaired forever.
- **CLEARING A QUARANTINE.** The acknowledgement key exists so a person can release one specific freed issue without releasing the others or hand-editing the loop's own bookkeeping.

## CONSTRAINTS

- **Three statuses never written.** A run that wrote one of the three would be parking work under the authority of whoever reads that status next.
- **`blocked` with a recorded cause.** Reporting an unfinished member without writing the status would leave it in the loop-responsible set and in the ready list, so the next PICK BATCH would select it again.
- **No fifth status.** A status outside the four reaches CLASSIFY's exclusion list and comes back as this loop's own wreckage.

## FINAL REPORT

- **Previous run's block must still appear.** Scoping the report to the current run is what let a restart report a backlog cleared over work an earlier run failed to land.
- **Both flags are load-bearing.** `bd list` hides closed issues unless `--all` is passed and returns at most 50 rows unless `--limit 0` is, so the plain form omits precisely the members a successful run has just closed.
- **Scope of the report.** An unscoped report covering every marker ever written grows without bound.

## RESIDUAL RECOVERY AND MERGE RULES

- **CLAIM records ownership.** I1 creates the trunk worktree and fixes `<worktree-root>` before CLAIM. A crash between I1 and CLAIM claimed no members and leaves an unowned empty root. RECOVERY never sweeps roots no ledger names, because their ownership cannot be proved. CLAIM records the root on every claimed member; the first CLEAN-TREE GATE RUN rewrites it idempotently.
- **Optional checks can be unavailable.** Optional `startup_failure` and billing or quota errors count as missing on purpose. A stricter reading would block every merge when Actions quota is exhausted even though the complete exact-head local gates pass. Completed optional failures of other kinds still block.
