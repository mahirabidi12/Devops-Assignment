# Helm

Session 15. Three tasks, all run against a single node kind cluster on `v1.37.0` with
**Helm v4.3.0**.

| Folder | Task | Covers |
|---|---|---|
| [`01-commands/`](01-commands/README.md) | Task 1 | create, lint, install, list, status, get, upgrade, history, rollback, uninstall, repo, search |
| [`02-rollback/`](02-rollback/README.md) | Task 2 | the full install → upgrade → verify → upgrade → verify → rollback → verify cycle |
| [`mini-project/`](mini-project/README.md) | Task 3 | a chart written from scratch, with dev and prod values files |

## Why Helm

Three problems met earlier in this homework, which Helm answers directly:

| Problem | Where it bit | Helm's answer |
|---|---|---|
| per-environment YAML duplication | would hit at the first real deploy | one chart, several values files |
| `kubectl apply -f dir/` has no ordering | [session 13 mini-project](../task-12-kubernetes-storage-hpa-probes/mini-project/README.md), where the namespace was created after the Deployment that needed it | Helm understands dependencies and install order |
| rolling back means finding old YAML | — | `helm rollback`, from stored revisions |

## Findings worth highlighting

**Helm's `deployed` status is not a health check.** Upgrading to a nonexistent image tag
produced `STATUS: deployed` and `Upgrade complete` while the new pod sat in
`ImagePullBackOff`. Helm reports that the API server accepted the manifests, not that the
application works. `--wait` or `--atomic` is what makes a CI pipeline fail honestly.

**Rolling update quietly saved it.** The three pods from the previous revision kept serving
throughout, because `maxUnavailable` prevented the rollout from removing working pods for a
new ReplicaSet that could never become ready.

**Rollback moves forward.** `helm rollback demo 2` created revision **4**, it did not return
to revision 2 and discard 3. Same design as `kubectl rollout undo` in task 9, and for the
same reason — the history is an audit trail.

**`--set` values are not sticky.** An upgrade that omits a flag silently reverts that
setting to the chart default unless `--reuse-values` is passed.

**Selector labels must exclude the version.** A Deployment's `spec.selector` is immutable,
so putting `app.kubernetes.io/version` in it makes the next `appVersion` bump unappliable.
This is why scaffolded charts define two label templates.

## Screenshots

| File | Shows |
|---|---|
| `15-01-create-install.png` | `helm create`, the generated tree, lint, install |
| `15-02-list-status-get.png` | list, status, get values, get manifest |
| `15-03-upgrades.png` | both upgrades, including the broken one reported as deployed |
| `15-04-rollback.png` | rollback, and the new revision 4 |
| `15-05-repo-search.png` | repo add/list/update, search repo and hub |
| `15-06-mini-project.png` | dev and prod values producing different running output |
| `15-07-uninstall.png` | uninstall, and the objects gone |

## Cleanup

    helm uninstall demo notes
