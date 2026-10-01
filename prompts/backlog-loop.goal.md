Clear every actionable non-epic issue from the Beads tracker by following the backlog-loop procedure explicitly loaded immediately before this goal.

The loaded backlog-loop procedure is the sole execution authority for every batch. If this prompt conflicts with that procedure, the procedure wins. Do not improvise around it or substitute another workflow.

Success means all three:
1. The backlog-loop census proves that no legal agent-executable action remains: no issue sits in its loop-responsible set except an issue whose open linked PR REPORT lists as awaiting a required approval and whose issue is reported as awaiting a person, and no PR its RESIDUE PASS stripped is still `OPEN`. A human gate, a label defect, and a quarantined issue each wait on a person, sit outside that set, and do not block success.
2. No non-epic issue remains in progress, except one explicitly identified as externally owned and reported as a blocker under the backlog-loop procedure, or a merged member held by a recorded post-merge watch and reported with its `backlog_loop_postmerge_ci` queue entry.
3. The census names every remaining non-closed non-epic issue with the reason it stays.

Condition 1 is stated as a census result because `bd ready` cannot tell a finished backlog from a stuck one. It excludes blocked, deferred, hooked, and in-progress issues, and backlog-loop marks a failed batch's members `blocked`, so an empty ready list is also what a run in which every issue failed and nothing merged leaves behind. It also stays non-empty on a backlog that holds a human gate identified only by its `human-gate` label, a label defect, or a quarantined issue, because the tracker still offers all three as ready work. The census separates the two: an issue the loop is responsible for is unfinished work, and an issue it is not responsible for is accounted for and reported.

The procedure deliberately leaves some blocked issues alone. A cause that has reached its attempt ceiling, or a repair that proved it needs unavailable human input, is work a person must pick up, and no later run may reopen it. A code-caused post-merge verification failure is different: backlog-loop keeps the merged members recoverable and runs TRUNK REPAIR before deciding that a person is needed.

The census covers **every** marker, not only this run's. Every invocation picks a fresh run id, and blocked issues are neither ready nor in progress, so a restart after a failed run sees an empty ready list, nothing in progress, and no blocked issue bearing its own new id -- and would declare the backlog cleared over work the previous run failed to land.

In the final goal turn:
- Paste the census header line and every census line, one per non-closed non-epic issue.
- Paste the relevant non-epic result from `bd list --status=in_progress --json`.
- Paste the blocked issues carrying any run marker, not only this run's, each with its recorded cause.
- Paste every pending post-merge watch with its `backlog_loop_postmerge_ci` queue entry.
- Produce the backlog-loop final report from tracker state.

Never ask me for input. Take the recommended option and record every decision.

Every batch follows the backlog-loop procedure's CI route, quality gates, and merge procedure exactly. This prompt adds no CI or merge rule of its own.

Do not stop the goal merely because trunk is red, one issue or batch failed, a merge failed, or a prior issue ID is encountered again. Follow backlog-loop's TRUNK REPAIR path for code-caused red gates, park only the scoped work that cannot complete, skip repeated IDs, and continue every independent agent-executable issue.

Stop the goal early only when backlog-loop has run its census and proved that no legal agent-executable action remains. The final report must name the human action, external owner, unavailable capability, or external-state change required, and explain why it prevents every remaining issue from reaching the merge gates. Event counters are never sufficient proof of that terminal condition.
