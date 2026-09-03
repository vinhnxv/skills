Account for every issue in the Beads tracker by running the CENSUS section of the backlog-loop procedure explicitly loaded immediately before this goal, and change nothing.

The loaded backlog-loop procedure is the sole execution authority. If this prompt conflicts with that procedure, the procedure wins. Run its CENSUS section as a diagnostic run and stop there: do not run the ITERATION loop, do not claim an issue, do not plan, build, branch, push, or merge anything.

Every `bd` command carries the global `--readonly` flag, so a write is refused by the tracker rather than merely avoided. This is the point of the run: an operator reaches for it when the backlog is already in a state they do not trust.

Success means all four:
1. Every non-closed non-epic issue appears exactly once in the census output, on its own `census <id> | <category> | <cause>` line.
2. The header line names the census token, the count per category, and the enumeration flags the run used.
3. Every repair and every reopen a loop run would perform is reported, with the issues involved and the marker state it would rely on -- and none of them is performed.
4. The tracker's exported issue records are unchanged. Compare `bd export` output taken before and after; a filesystem diff is not a valid check, because a plain `bd show` rewrites tracker bookkeeping without changing any issue field.

In the final goal turn:
- Paste the census header line and every census line.
- Paste the loop-responsible count and, when it is zero, say so plainly.
- Paste every open human gate with what the person must do, and every labeling defect with the exact label to apply.
- Paste every reported dependency cycle.
- Paste every repair and reopen the run would have performed, and say that none was.
- Paste the `bd export` comparison result.

Never ask me for input. Report what you found; do not act on it.

Authorizing the reported repairs is a separate act: start an ordinary backlog-loop run. Nothing in this run asks for that authorization or infers it.

Stop the goal early and report the exact state if:
- `bd prime` or the enumeration query does not work;
- an issue cannot be placed in exactly one category;
- any `bd` command in this run is refused for a reason other than `--readonly`;
- the `bd export` comparison shows the tracker changed;
- backlog-loop encounters another documented terminal blocker.
