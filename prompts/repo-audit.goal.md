Audit this repository against every dimension of the repo-audit procedure explicitly loaded immediately before this goal, and file what it confirms into the Beads tracker.

The loaded repo-audit procedure is the sole execution authority. If this prompt conflicts with that procedure, the procedure wins. Do not improvise around it, do not substitute another audit workflow, and do not widen or narrow its dimension roster.

This run writes to a tracker that another autonomous process will start clearing. Everything it files becomes work, so every bound the procedure states -- the filing ceilings, the sweep's two bounds, the deduplication tiers, and the first-run carve-out -- is load-bearing rather than advisory.

Success means all six:
1. Exactly one `audit-run` header line is printed, one `dimension` line per roster dimension, one `criterion` line per roster criterion, and one `finding` line per surviving candidate. All three of the procedure's own counts hold: the dimension lines equal the dimension roster size, the criterion lines equal the criterion roster size with each attributed to its roster dimension, and the `<dims>` lists across the finding lines sum to the pre-collapse candidate count.
2. No emitted field is blank, and every field's value comes from that field's closed vocabulary.
3. Every criterion carries a verdict of `clean`, `uncovered`, or `skipped`, and every dimension carries the roll-up over its criteria -- `clean` only where every one of them is `clean` or `skipped`, and `uncovered` where any is. Every `uncovered` criterion is named in the report with what it did not finish, and so is the dimension it denied a clean verdict to. A `clean` verdict was measured; it is never the mere absence of a finding.
4. Every finding at every severity is in the report, including the P3 and P4 findings that were never filed and the refuted and unevaluable ones. Every skipped `(criterion, file, sha)` triple is enumerated.
5. Every issue this run filed carries the run token and the audit-authored marker. No issue this run did not file was retitled, reprioritized, relabelled, reparented, or closed; the only write any foreign issue received is the bounded absorb note.
6. A report exists at `docs/audits/YYYY-MM-DD-HHMM-audit.md`, and it closes with the bulk-retraction recipe -- the exact commands that would close everything this run filed.

Condition 5 is the one that matters most and the one easiest to satisfy by accident. The audit shares a tracker with a process that merges its own pull requests, so an issue the audit touched that it did not file is an issue whose shipping authority now rests on a mutation nobody authorized. Check it against the tracker rather than against the run's own narration.

A first run against this repository files nothing at all. That is the procedure working, not a failure: it makes exactly one tracker write, creating its index issue, and reports in full what it would have filed. If this is a first run, conditions 1 through 4 and 6 still apply and condition 5 is satisfied by there being no filed issue.

In the final goal turn:
- Paste the `audit-run` header line and every `dimension` line.
- Paste every `finding` line.
- Paste the report path, and say whether the repository's VCS ignores it.
- Paste every issue id this run filed, grouped by severity, and name the `[HUMAN]` gates separately.
- Paste every suppression accepted, expired, or nearly matched, by issue id and title.
- Paste every finding that was deduplicated, deferred, or over a ceiling, and what each was against.
- Paste every stale-close this run performed, with the recipe and the SHA it was evaluated at.
- Paste the bulk-retraction recipe.

Never ask me for input. Take the option the procedure names and record every decision.

Do not fix anything you find. This run enumerates and files; the fixing belongs to whatever clears the backlog afterwards, and an audit that also edits the code it is judging has no independent record of what it found.

Stop the goal early and report the exact state if:
- `bd prime` or `bd ready` does not work;
- the audited SHA is not an ancestor of the default branch;
- the index issue will not parse, or an index write's read-back does not match what was rendered;
- the rendered index will not fit under its size cap after compaction;
- the emit count check fails;
- the stale-close sweep's non-reproducing share crosses the systemic threshold;
- repo-audit encounters another documented terminal blocker.
