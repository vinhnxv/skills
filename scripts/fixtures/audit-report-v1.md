# Repository audit report (fixture)

Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.

## 1. Run and source snapshot

- Schema: repo-audit-report/v1
- Run ID: 20261001T031500Z-a1b2c3
- Started (UTC): 2026-10-01T03:15:00Z
- Finished (UTC): 2026-10-01T03:48:12Z
- Host/model: unspecified
- Repository: example.com/acme/widget-service
- Base SHA: 4be07a19c3d8f5e2a61b9047cd3e8f12a5b6c7d0
- Branch: audit/widget-service
- Remote default tip: 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21
- Behind: 3
- Off default branch: no
- Linked worktree: yes
- Audited scope: whole repository, working tree
- Dirty paths: none
- Visibility: private
- Restriction level: subagent tools restricted to read-only; no mutation observed
- Report VCS status: ignored by the repository; the report is deleted with the worktree unless handed off

## 2. Method and limits

- Applied project rules: stack, build-test, lint-format, conventions, and gates resolved from AGENTS.md and the manifests.
- Search allocation: one or more distinct patterns per criterion, allocated before dispatch.
- Disabled or failed checks: the advisory database lookup for dc-advisory was unreachable.
- Serial degradation: none; dimensions were audited in parallel waves.
- Changed evidence: one candidate became unevaluable when its file changed during the run.
- Instruction-shaped content: none found.

## 3. Coverage

`clean` means a covered search, not defect-free code.

### Criteria

| ID | Dimension | Search scope | Population | Surfaced | Investigated | Investigated/population | Surfaced/population | Verdict | Remaining gap |
|---|---|---|---|---|---|---|---|---|---|
| `cc-existing` | correctness and control flow | src/**/*.py bounds and None checks | 10 | 2 | 8 | 0.80 | 0.20 | clean | none |
| `cc-error-path` | correctness and control flow | src/**/*.py fallible calls | 6 | 1 | 5 | 0.83 | 0.17 | clean | none |
| `cc-stub` | correctness and control flow | TODO and NotImplemented markers | 4 | 0 | 4 | 1.00 | 0.00 | clean | none |
| `so-existing` | state, ordering, and idempotency | src/**/*.py async and shared state | 9 | 1 | 6 | 0.67 | 0.11 | clean | none |
| `so-idempotency` | state, ordering, and idempotency | retry and enqueue paths | 4 | 1 | 3 | 0.75 | 0.25 | clean | none |
| `so-two-layers` | state, ordering, and idempotency | validators in api and store layers | 3 | 0 | 3 | 1.00 | 0.00 | clean | none |
| `so-migration` | state, ordering, and idempotency | migrations against models | 3 | 0 | 3 | 1.00 | 0.00 | clean | none |
| `ib-existing` | input boundaries and untrusted data | query and command construction | 8 | 1 | 6 | 0.75 | 0.13 | clean | none |
| `ib-leak` | input boundaries and untrusted data | log and error response sites | 5 | 1 | 4 | 0.80 | 0.20 | clean | none |
| `ib-fail-open` | input boundaries and untrusted data | permissive defaults | 4 | 1 | 3 | 0.75 | 0.25 | clean | none |
| `ib-authz` | input boundaries and untrusted data | route entry points | 6 | 0 | 5 | 0.83 | 0.00 | clean | none |
| `rl-existing` | resource lifecycle and unbounded growth | open handles and caches | 7 | 1 | 5 | 0.71 | 0.14 | clean | none |
| `rl-timeout` | resource lifecycle and unbounded growth | outbound HTTP calls | 6 | 1 | 5 | 0.83 | 0.17 | clean | none |
| `rl-loop-query` | resource lifecycle and unbounded growth | queries inside loops | 3 | 0 | 3 | 1.00 | 0.00 | clean | none |
| `id-signature` | interface and contract drift | call sites against definitions | 12 | 0 | 9 | 0.75 | 0.00 | clean | none |
| `id-unregistered` | interface and contract drift | handlers against route table | 4 | 0 | 3 | 0.75 | 0.00 | clean | none |
| `id-doc-drift` | interface and contract drift | routes against openapi.yaml | 3 | 0 | 3 | 1.00 | 0.00 | clean | none |
| `id-dead-config` | interface and contract drift | config keys against readers | 5 | 1 | 4 | 0.80 | 0.20 | clean | none |
| `ti-vacuous` | test integrity and vacuous passes | assertions in tests/ | 6 | 1 | 5 | 0.83 | 0.17 | clean | none |
| `ti-mock-only` | test integrity and vacuous passes | mock-only tests | 4 | 0 | 3 | 0.75 | 0.00 | clean | none |
| `ti-skipped` | test integrity and vacuous passes | skip markers | 3 | 1 | 3 | 1.00 | 0.33 | clean | none |
| `ti-untested` | test integrity and vacuous passes | source files against tests | 15 | 1 | 10 | 0.67 | 0.07 | clean | none |
| `dd-unreached` | dead and duplicated code | exported symbols without callers | 10 | 1 | 7 | 0.70 | 0.10 | clean | none |
| `dd-duplicated` | dead and duplicated code | duplicated blocks across files | 5 | 0 | 4 | 0.80 | 0.00 | clean | none |
| `dd-rename-orphan` | dead and duplicated code | callers of renamed symbols | 3 | 0 | 3 | 1.00 | 0.00 | clean | none |
| `dd-dead-reexport` | dead and duplicated code | re-export statements, exhaustive | 0 | 0 | 0 | n/a | n/a | skipped | none |
| `rr-contradicts` | the repository's own stated rules | code against AGENTS.md rules | 6 | 1 | 4 | 0.67 | 0.17 | clean | none |
| `rr-comment-drift` | the repository's own stated rules | comments against adjacent code | 8 | 0 | 6 | 0.75 | 0.00 | clean | none |
| `rr-doc-claim` | the repository's own stated rules | README claims against code | 4 | 1 | 3 | 0.75 | 0.25 | clean | none |
| `dc-advisory` | dependency and configuration hygiene | pinned dependencies | 0 | 0 | 0 | n/a | n/a | uncovered | advisory database unreachable |
| `dc-lockfile` | dependency and configuration hygiene | lockfile against manifest | 3 | 0 | 3 | 1.00 | 0.00 | clean | none |
| `dc-dead-script` | dependency and configuration hygiene | pipeline script references | 4 | 0 | 3 | 0.75 | 0.00 | clean | none |

### Dimensions

| Dimension | Population | Surfaced | Investigated | Investigated/population | Surfaced/population | Verdict | Remaining gap |
|---|---|---|---|---|---|---|---|
| correctness and control flow | 20 | 3 | 17 | 0.85 | 0.15 | clean | none |
| state, ordering, and idempotency | 19 | 2 | 15 | 0.79 | 0.11 | clean | none |
| input boundaries and untrusted data | 23 | 3 | 18 | 0.78 | 0.13 | clean | none |
| resource lifecycle and unbounded growth | 16 | 2 | 13 | 0.81 | 0.13 | clean | none |
| interface and contract drift | 24 | 1 | 19 | 0.79 | 0.04 | clean | none |
| test integrity and vacuous passes | 28 | 3 | 21 | 0.75 | 0.11 | clean | none |
| dead and duplicated code | 18 | 1 | 14 | 0.78 | 0.06 | clean | none |
| the repository's own stated rules | 18 | 2 | 13 | 0.72 | 0.11 | clean | none |
| dependency and configuration hygiene | 7 | 0 | 6 | 0.86 | 0.00 | uncovered | dc-advisory population unproven; total population below the floor of 8 |

Cache-skipped triples: none.

## 4. Findings

### RA-166172a2cc

- Status: confirmed
- Severity: P2 - a zero quantity reaches the price division; likely on any empty order line.
- Criterion: `cc-existing`
- Dimensions: correctness and control flow
- Location: src/handlers/orders.py, `parse_quantity`
- Snapshot: commit 4be07a19c3d8f5e2a61b9047cd3e8f12a5b6c7d0
- Observation: `parse_quantity` returns 0 for an empty string and the caller divides by it.
- Verification: an independent pass re-resolved the path and lines at the snapshot and found the unguarded division.
- Reproduction: call the handler with an order line whose quantity field is empty.
- Redaction: none
- Proposed action: reject an empty quantity before the division and add a test for it.

### RA-dce059c6b5

- Status: confirmed
- Severity: P1 - an internal debug route is reachable without authorization; likely reachable from the public network.
- Criterion: `ib-authz`
- Dimensions: input boundaries and untrusted data
- Location: src/api/internal.py, `debug_dump`
- Snapshot: commit 4be07a19c3d8f5e2a61b9047cd3e8f12a5b6c7d0
- Observation: the route is registered without the authorization decorator the sibling routes carry.
- Verification: the second side of the claim, the route table, was re-read and lists no global guard.
- Reproduction: request the route without credentials.
- Redaction: none
- Proposed action: add the authorization check or remove the route.

### RA-026cce4b06

- Status: refuted
- Severity: P3 - a retry path without an idempotency key; unlikely, because the operation is naturally idempotent.
- Criterion: `so-idempotency`
- Dimensions: state, ordering, and idempotency
- Location: src/jobs/retry.py, `enqueue_retry`
- Snapshot: commit 4be07a19c3d8f5e2a61b9047cd3e8f12a5b6c7d0
- Observation: the retry re-enqueues a job without a key.
- Verification: the guard applies; the enqueue writes a fixed row keyed by job id, so a repeat changes nothing.
- Reproduction: not applicable.
- Redaction: none
- Proposed action: none; refuted with the guard named above.

### RA-2b5947bea9

- Status: unevaluable
- Severity: P3 - a cache read without an error path; the snapshot changed during the run.
- Criterion: `cc-error-path`
- Dimensions: correctness and control flow
- Location: src/store/cache.py, `load_entry`
- Snapshot: working-tree, changed during the run
- Observation: the candidate was raised before the file changed.
- Verification: unevaluable until the changed file is rechecked.
- Reproduction: not applicable.
- Redaction: none
- Proposed action: revalidate against the current tree before any action.

### RA-d065ea0469

- Status: confirmed
- Severity: P1 - a credential class value reaches a log line; likely on every failed login.
- Criterion: `ib-leak`
- Dimensions: input boundaries and untrusted data
- Location: withheld
- Snapshot: commit 4be07a19c3d8f5e2a61b9047cd3e8f12a5b6c7d0
- Observation: a login failure handler writes a secret-class field to the application log.
- Verification: an independent pass confirmed the log call at the snapshot; the value is not quoted here.
- Reproduction: trigger a failed login and read the log.
- Redaction: withheld-no-ignored-path
- Proposed action: stop logging the field; rotate the exposed credential class.

## 5. Disposition and limitations

- confirmed: 3
- refuted: 1
- unevaluable: 1
- Unfinished criteria: dc-advisory.
- Withheld evidence: the location of RA-d065ea0469; no ignored detail path was available.
- No source fix or tracker write was made during this audit.

## 6. Closing summary

Report path: docs/audits/2026-10-01-0315-20261001T031500Z-a1b2c3-audit.md, ignored by the repository.

Warning: the remote default tip is 9f2c41d7a8b3e65f0c1d2e4a7b9c8d6e5f4a3b21 and this checkout is behind it by 3 commits; it is a linked worktree. Findings may already be fixed on the default branch, or exist only on this branch.

Coverage: 31 of 32 criteria covered or proven empty, 1 uncovered. Findings: 5 records, 3 confirmed.

Recommendation: fix the two P1 findings first; revalidate RA-2b5947bea9 before acting on it.
