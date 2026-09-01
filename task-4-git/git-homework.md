# Git Homework

Everything below was run in a scratch repository created with `git init`, so the output
and the commit hashes are real and they line up between the two tasks.

## Task 1: git commit -a -m compared with git commit -m

### The short version

`git commit -m` commits whatever is in the staging area and nothing else, so it depends
on a prior `git add`. `git commit -a -m` first stages every tracked file that has been
modified or deleted, then commits, which removes the `git add` step. What neither of them
does is pick up a file git has never seen before.

### Setting up

    git init -b main
    echo "# Git Practice" > notes.txt
    git add notes.txt
    git commit -m "First commit: add notes.txt"

### Test 1: edit a tracked file, then commit without -a

    $ echo "line two" >> notes.txt
    $ git status --short
     M notes.txt

    $ git commit -m "try without -a"
    On branch main
    Changes not staged for commit:
      (use "git add <file>..." to update what will be committed)
      (use "git restore <file>..." to discard changes in working directory)
    	modified:   notes.txt

    no changes added to commit (use "git add" and/or "git commit -a")

    $ echo $?
    1

No commit was made, and the exit status of 1 confirms the command failed rather than
quietly doing nothing. The edit is sitting in the working tree, but it was never staged,
and staging is the only thing `commit -m` looks at. The `M` in `git status --short` is in
the second column, which is the working tree column; a staged change would show its `M`
in the first column instead.

### Test 2: the same edit, this time with -a

    $ git commit -a -m "Add line two using commit -a"
    [main 5f0d51e] Add line two using commit -a
     1 file changed, 1 insertion(+)

    $ git status --short
    (no output, the working tree is clean)

That worked. `-a` staged the modified tracked file and committed it in a single command.

### Test 3: will -a commit a brand new file?

    $ echo "new file" > extra.txt
    $ git status --short
    ?? extra.txt

    $ git commit -a -m "try to commit untracked file with -a"
    On branch main
    Untracked files:
      (use "git add <file>..." to include in what will be committed)
    	extra.txt

    nothing added to commit but untracked files present (use "git add" to track)

    $ echo $?
    1

It will not. `??` means untracked, so the file has no history in this repository at all
and `-a` skips it. A new file has to be introduced with `git add` at least once:

    $ git add extra.txt
    $ git commit -m "Add extra.txt the two step way"
    [main 3748d4c] Add extra.txt the two step way
     1 file changed, 1 insertion(+)
     create mode 100644 extra.txt

The `create mode 100644` line only appears when a file enters the repository for the
first time.

### Where task 1 ended up

    $ git log --oneline
    3748d4c Add extra.txt the two step way
    5f0d51e Add line two using commit -a
    2348e26 First commit: add notes.txt

### What I took from this

`-a` is a convenience, not a different sort of commit; the resulting object is identical
either way. It suits the common case of editing files git already knows about. The reason
to be a bit careful with it is that it is indiscriminate: it sweeps in every modified
tracked file in the repository, including changes in files that have nothing to do with
the commit message you just wrote. When a commit should only contain part of my current
work, I stage those specific files with `git add` and use plain `commit -m`.

Two details worth holding on to. `-a` also stages deletions, so deleting a file and
running `commit -a` records the removal, which is easy to forget. And `git commit -a`
does not skip the staging area, it just fills it for you first, so `git diff --staged`
still shows exactly what is about to be committed.

## Task 2: git cherry-pick

Cherry-pick takes one particular commit from somewhere else and applies it to the current
branch, without dragging along the commits around it.

### Starting point, three commits on main

    $ git log --oneline
    3748d4c Add extra.txt the two step way
    5f0d51e Add line two using commit -a
    2348e26 First commit: add notes.txt

### A branch with three commits, one of which is urgent

    git checkout -b feature

    echo "work in progress feature A" > feature-a.txt
    git add . && git commit -m "Feature: add feature-a.txt"

    echo "fix: correct the typo in the config" > bugfix.txt
    git add . && git commit -m "Bugfix: correct typo in config"

    echo "work in progress feature C" > feature-c.txt
    git add . && git commit -m "Feature: add feature-c.txt"

    $ git log --oneline
    d473b87 Feature: add feature-c.txt
    59b6bb5 Bugfix: correct typo in config
    6f972c4 Feature: add feature-a.txt
    3748d4c Add extra.txt the two step way
    5f0d51e Add line two using commit -a
    2348e26 First commit: add notes.txt

The scenario this sets up: the bug fix in the middle needs to ship on `main` right now,
while the two feature commits around it are half finished and must stay on the branch.
Merging the branch would bring all three, which is exactly what we do not want.

### Finding the commit

    $ git log --oneline --grep="Bugfix"
    59b6bb5 Bugfix: correct typo in config

    $ git show 59b6bb5 --stat
    commit 59b6bb5357524c6e8b2fe8b70136e3a817ed49b1
    Author: mahirabidi12 <abidimahir109@gmail.com>
    Date:   Tue Sep 1 20:32:57 2026 +0530

        Bugfix: correct typo in config

     bugfix.txt | 1 +
     1 file changed, 1 insertion(+)

`--grep` searches commit messages, which is the practical way to find a commit when you
remember the wording but not the hash. `git show --stat` is then worth running before
picking anything, to confirm the commit touches only the files you expect.

### Applying it to main

    $ git checkout main
    Switched to branch 'main'

    $ ls
    extra.txt   notes.txt

    $ git cherry-pick 59b6bb5
    [main f12d5d0] Bugfix: correct typo in config
     Date: Tue Sep 1 20:32:57 2026 +0530
     1 file changed, 1 insertion(+)
     create mode 100644 bugfix.txt

### Checking the result

    $ git log --oneline
    f12d5d0 Bugfix: correct typo in config
    3748d4c Add extra.txt the two step way
    5f0d51e Add line two using commit -a
    2348e26 First commit: add notes.txt

    $ ls
    bugfix.txt  extra.txt   notes.txt

    $ cat bugfix.txt
    fix: correct the typo in the config

`bugfix.txt` is on `main`, while `feature-a.txt` and `feature-c.txt` are not, which is
precisely the outcome the exercise was after.

### The shape of the history afterwards

    $ git log --oneline --graph --all
    * d473b87 Feature: add feature-c.txt
    * 59b6bb5 Bugfix: correct typo in config
    * 6f972c4 Feature: add feature-a.txt
    | * f12d5d0 Bugfix: correct typo in config
    |/
    * 3748d4c Add extra.txt the two step way
    * 5f0d51e Add line two using commit -a
    * 2348e26 First commit: add notes.txt

### What I took from this

The graph is the important part. The same change now appears twice, as `59b6bb5` on
`feature` and as `f12d5d0` on `main`, with two different hashes. So cherry-pick does not
relocate a commit, it replays the diff as a completely new commit. It copies the message,
the author and the original author date, which is why the output printed a `Date:` line,
but the committer and the hash are new.

The consequence to be aware of is duplication. Because the change exists in two places,
merging `feature` into `main` later has to reconcile them. Usually git manages, since the
content matches, but if those same lines are edited again on either side the merge can
conflict, and the history now tells a slightly misleading story about where the fix came
from. That is why cherry-pick is the tool for "this one fix is needed over there
immediately" rather than a general way of moving work between branches. For moving work,
merge or rebase is correct.

Flags I noted while reading up on it:

    git cherry-pick <hash>          one commit
    git cherry-pick <h1> <h2>       several, applied in the order given
    git cherry-pick <h1>..<h2>      a range, exclusive of h1
    git cherry-pick <h1>^..<h2>     a range including h1
    git cherry-pick -n <hash>       stage the change but stop before committing
    git cherry-pick -x <hash>       add a "cherry picked from ..." line to the message
    git cherry-pick --abort         give up and restore the branch
    git cherry-pick --continue      resume once a conflict is resolved
    git cherry-pick --skip          drop the current commit and carry on

`-x` looks like the one worth using by default on a shared branch, since it records where
the commit came from and removes the guesswork later.
