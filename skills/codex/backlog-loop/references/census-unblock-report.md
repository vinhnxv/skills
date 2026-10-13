# Unblock Report.

This text belongs to this skill's `SKILL.md` and is read in full before it runs.

<!-- body -->
UNBLOCK REPORT. Both modes print it as the last block of a census, so the operator reads the answer to "which blocked issues can the agent decide, and how do they unblock" instead of asking for it. It prints one line, in this exact shape, for every non-closed, non-epic issue that the loop is not clearing unaided and for every issue a mutation pass returned to the loop in this run:

```
unblock <id> | <class> | <action> | <command>
```

`<class>` is exactly one of `agent-done` (a repair or reopen this run performed), `agent-queued` (the loop reopens or decides it itself on a later pass), `person` (a human act is required), or `external` (an owner, service, or state change outside the repository). The class and the recommendation come from the recorded category and cause, never from reading a body, and they follow this table:

| category and state | `<class>` | `<action>` | `<command>` |
|---|---|---|---|
| an issue whose open linked PR REPORT lists as awaiting a required approval | `person` | approve the PR, naming its URL and the approvals missing | `gh pr view <url>` |
| `self-blocked-needs-person` with `backlog_loop_ceiling` | `person` | the ESCALATION DOSSIER's strongest remaining suspicion | the grant command the dossier prints |
| `self-blocked-needs-person` released by a person-close | `person` | decide whether the closed PR's work should be rebuilt | the reopen command REPORT prints |
| `self-blocked-needs-person`, any other cause or none recorded | `person` | the first line of its newest note, which holds the question | answer it in the issue, then `bd update <id> --status=open` |
| `legacy-blocked` | `person` | the reason its newest note states, because the status is a person's parking decision | `bd update <id> --status=open`, printed for the person and never run by the loop |
| `quarantined` | `person` | the edge its dependents wait on | the exact key and value CLEARING A QUARANTINE reports |
| `label-defect` | `person` | apply the label the census line names | the label-add command for that label |
| `human-gate`, `label` or `native` | `person` | what the person must do, from its description, acceptance criteria, or design | `bd gate resolve <id>` for a native gate, and the tracker's close command once the act is done for a labeled one |
| `external-wip` whose lease has expired | `agent-queued` | EXTERNAL LEASE PASS reclaims it | none |
| `external-wip`, any other state | `external` | the assignee and the lease state `bd show <id> --json` reports | contact that assignee |
| `dep-blocked` on a blocker outside the loop-responsible set | the blocker's class | the blocker's own line | `unblock <blocker-id>` |
| `self-blocked-transient` | `agent-queued` | the next REOPEN PASS reopens it once its cause is gone | none |
| an issue a mutation pass returned to the loop in this run | `agent-done` | name the pass | none |

Walk the table top-down and stop at the first row that matches, as CLASSIFY does, so no issue matches two rows.

For every `person` and `external` line, count the issues its resolution makes reachable: the issue itself plus every `dep-blocked` issue that transitively waits on it, over the same visited-set walk as above. Begin `<action>` with `unlocks <n>: ` and sort the block by `<n>` descending, then by id ascending, so the one act that frees the most work comes first. Every `unblock` line names an issue that has a `census` line and no issue has two. The UNBLOCK REPORT writes nothing of its own, in either mode: the `agent-done` and `agent-queued` lines describe repairs that other passes made, or will make, under WRITE GATE, and a diagnostic run labels every would-be repair `would evaluate`.

