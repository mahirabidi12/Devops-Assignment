# Kubernetes Troubleshooting

Session 14. Three tasks, all run against a single node kind cluster on `v1.37.0`.

| Folder | Task | Covers |
|---|---|---|
| [`01-commands/`](01-commands/README.md) | Task 1 | `get`, `describe`, `logs`, `exec`, `events`, `explain`, `top`, `-o wide` |
| [`02-scenarios/`](02-scenarios/README.md) | Task 2 | five broken pods, each identified, investigated, root-caused, fixed and verified |
| [`mini-project/`](mini-project/README.md) | Task 3 | a stack with one broken pod, triaged end to end |

## The single most useful idea

**Did the container run?**

- It ran and died → read the **logs**, with `--previous` if it is restarting.
- It never started → read the **events** via `describe`. There are no logs.

Four of the nine failure types below never start a container, so reaching for `kubectl logs`
first fails more often than it works.

## The nine issues the session asks for

| Issue | Covered in | Root cause found |
|---|---|---|
| CrashLoopBackOff | scenario 1 | missing `DATABASE_URL` |
| ImagePullBackOff | scenario 2, mini-project | image does not exist |
| ErrImagePull | scenario 2, mini-project | the state before backoff begins |
| Pending | scenario 3 | request exceeds node capacity |
| ContainerCreating | `01-commands/` | transient; persists on volume or image-pull delays |
| Service connectivity | scenario 4, mini-project | empty endpoint list |
| DNS issues | scenario 4 | wrong Service FQDN |
| Pod networking | scenario 4 | `HTTP 000` from no reachable backend |
| Configuration | scenario 1, 5 | missing env var; limit below actual need |

## Findings worth highlighting

**One broken pod reported `Running` the whole time.** Scenario 4's client resolved a Service
that does not exist, swallowed the error with `|| true`, and sat there healthy. Every signal
Kubernetes exposes said it was fine. Only the logs showed otherwise, and only if you knew
what success should have looked like.

**`HTTP 000` has at least three distinct causes.** A Service whose selector matches nothing
(task 10), every pod terminating during a Recreate rollout (task 9), and a backend that has
not become Ready yet (scenario 4 here). Same symptom, three different places to look, all of
them "the endpoint list is empty".

**Exit code 137 is not the application's choice.** `128 + 9` — SIGKILL from the kernel OOM
killer. Memory limits are enforced by killing, with no signal the process can catch, unlike
CPU limits which merely throttle.

**Empty logs do not mean a silent process.** A fixed pod came up `Running` with no output
because Python buffers stdout when it is not a terminal. `python3 -u` fixed it.

**The scheduler works from requests, not usage.** A node at 5% actual CPU can still reject a
pod, because granted requests are reserved whether or not they are consumed. `kubectl top`
and `kubectl describe node` answer different questions.

## Screenshots

| File | Shows |
|---|---|
| `14-00-all-broken.png` | all five scenarios failing at once |
| `14-01-crashloop.png` | scenario 1, identify through verify |
| `14-02-imagepull.png` | scenario 2, including why `logs` returns nothing |
| `14-03-pending.png` | scenario 3, request vs node capacity side by side |
| `14-04-dns.png` | scenario 4, the one that looked healthy |
| `14-05-oomkilled.png` | scenario 5, exit code 137 |
| `14-06-commands.png` | the command reference in use |
| `14-07-mini-project.png` | the mini-project triaged end to end |

## Cleanup

    kubectl delete pod -l tier=triage-gauntlet
    kubectl delete svc postgres-db --ignore-not-found
    kubectl delete -f mini-project/ --ignore-not-found
