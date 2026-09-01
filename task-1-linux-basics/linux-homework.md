# Linux Homework

## Task 1: Soft Link and Hard Link

A hard link is a second name pointing at the same inode. The inode is where the file's
data actually lives on disk, so once a hard link exists there is no "original" and no
"copy" any more, just one file reachable by two names. A soft link, also called a
symlink, is a tiny file of its own whose contents are the path of some other file. It
behaves like a shortcut, and because it only stores a path it goes dead the moment the
target is renamed, moved or removed.

    ln  original.txt hard.txt      make a hard link
    ln -s original.txt soft.txt    make a soft link, the s stands for symbolic
    rm soft.txt                    removes the link itself, the target is untouched

### Creating both and looking at them

I made a file, linked it both ways, and compared the inode numbers with `ls -li`:

    $ echo "hello" > original.txt
    $ ln -s original.txt soft.txt
    $ ln original.txt hard.txt
    $ ls -li
    115083269 -rw-r--r--  2 mahirabidi  wheel   6 hard.txt
    115083269 -rw-r--r--  2 mahirabidi  wheel   6 original.txt
    115083270 lrwxr-xr-x  1 mahirabidi  wheel  12 soft.txt -> original.txt

Reading that output:

- `original.txt` and `hard.txt` both show inode 115083269, and the number after the
  permissions is 2. That column is the link count, so the inode knows two names refer
  to it.
- `soft.txt` has a different inode, 115083270. Its permission string begins with `l`
  instead of `-`, and `ls` prints an arrow to the path it holds. Its size is 12, which
  is exactly the length of the string `original.txt`.

### Deleting a soft link

    $ rm soft.txt
    $ ls -li
    115083269 -rw-r--r--  2 mahirabidi  wheel  6 hard.txt
    115083269 -rw-r--r--  2 mahirabidi  wheel  6 original.txt

    $ cat original.txt
    hello

Only the link went. The target is untouched and the link count on the inode is still 2,
because removing a symlink removes one small file whose contents happened to be a path.
The thing it pointed at never knew about it.

### Deleting a hard link

    $ ln -s original.txt soft.txt      # put the soft link back first
    $ rm hard.txt
    $ ls -li
    115083269 -rw-r--r--  1 mahirabidi  wheel   6 original.txt
    115083273 lrwxr-xr-x  1 mahirabidi  wheel  12 soft.txt -> original.txt

This is the interesting one. `original.txt` survives, but its link count has dropped from
2 to 1. So `rm` did not delete a file, it removed one name from the inode and decremented
the counter. The data is only released when that count reaches zero, which is why the
system call behind `rm` is called `unlink`.

Note also that the recreated `soft.txt` got a fresh inode, 115083273 rather than the
115083270 it had before, confirming it is a genuinely new file each time.

### Deleting the target out from under the soft link

    $ rm original.txt
    $ ls -li
    115083273 lrwxr-xr-x  1 mahirabidi  wheel  12 soft.txt -> original.txt

    $ cat soft.txt
    cat: soft.txt: No such file or directory

    $ test -e soft.txt && echo exists || echo broken
    broken

    $ test -L soft.txt && echo "link still present" || echo gone
    link still present

The symlink is now dangling. `ls` still lists it quite happily, because the link file
itself is perfectly intact, but anything that tries to follow it fails. The two `test`
flags show the distinction directly: `-e` follows the link and reports nothing there,
while `-L` looks at the link itself and finds it present. If the hard link had still
existed at this point, `cat hard.txt` would have printed `hello`, because the data stays
alive as long as one name points at the inode.

### Two limits on hard links

A hard link cannot cross a filesystem boundary, because inode numbers are only unique
within one filesystem, and it cannot normally be made to a directory, because that would
allow loops in the directory tree that tools walking it could never escape. A soft link
can do both, since it is only a stored path and is resolved fresh each time.

### If this comes up in an interview

A hard link is an extra directory entry for an existing inode, so the file lives on for
as long as any one of its links exists. A soft link is a separate small file containing
a path, so it breaks when the target disappears. `ln` makes the first, `ln -s` makes the
second.

## Task 2: adduser vs useradd

`useradd` is the low level binary and ships on essentially every distribution. It is
literal: it only performs what the flags ask for, so on its own you get an account with
no home directory, no password set and no interactive questions.

`adduser` on Debian and Ubuntu is not a different binary doing the same job, it is a
Perl script wrapping `useradd`. It asks questions, creates and populates the home
directory from `/etc/skel`, sets up the matching group and prompts you to choose a
password.

Which one to prefer on Ubuntu depends on the situation. For adding a person by hand,
`adduser` is the right choice, because everything a usable account needs is handled and
there are no flags to forget. `useradd` is the one to reach for inside a script, where
interactive prompts would hang the run, and on RHEL family systems, where `adduser` is
frequently just a symlink to `useradd` and so gains you nothing.

### Creating a test user the recommended way

    $ sudo adduser testuser
    Adding user `testuser' ...
    Adding new group `testuser' (1001) ...
    Adding new user `testuser' (1001) with group `testuser' ...
    Creating home directory `/home/testuser' ...
    Copying files from `/etc/skel' ...
    New password:
    Retype new password:

    $ id testuser
    uid=1001(testuser) gid=1001(testuser) groups=1001(testuser)

    $ ls -d /home/testuser
    /home/testuser

The equivalent with `useradd` needs the same work spelled out by hand, and the password
is a separate command:

    sudo useradd -m -s /bin/bash testuser2   # -m creates the home dir, -s sets the shell
    sudo passwd testuser2                    # password has to be set separately

Removing them again:

    sudo deluser --remove-home testuser
    sudo userdel -r testuser2

## Task 3: journalctl

`journalctl` is the reader for the log that `systemd-journald` collects. On a systemd
based Linux almost everything ends up in that one journal instead of in scattered text
files under `/var/log`, so a single command covers kernel messages, the boot sequence
and the stdout and stderr of every service.

    journalctl                         everything, oldest first, in a pager
    journalctl -n 50                   just the last 50 entries
    journalctl -f                      follow new entries live, like tail -f
    journalctl -u nginx                only one unit
    journalctl -u nginx --since today
    journalctl -p err -b               errors and worse, this boot only
    journalctl -b -1                   the previous boot, for looking at a crash
    journalctl -k                      kernel ring buffer only
    journalctl --disk-usage            how much space the journal is taking
    sudo journalctl --vacuum-time=7d   throw away anything older than a week

### Checking the logs of one service

I used `ssh` as the example service:

    $ systemctl status ssh
    * ssh.service - OpenBSD Secure Shell server
         Loaded: loaded (/lib/systemd/system/ssh.service; enabled)
         Active: active (running) since Tue 2026-09-01 09:14:22 IST; 2h 3min ago
       Main PID: 812 (sshd)

    $ journalctl -u ssh -n 20
    Sep 01 09:14:22 host sshd[812]: Server listening on 0.0.0.0 port 22.
    Sep 01 09:14:22 host sshd[812]: Server listening on :: port 22.
    Sep 01 10:47:05 host sshd[2244]: Accepted password for testuser from 192.168.1.6 port 51224 ssh2

    $ journalctl -u ssh --since today -p err     # only today's errors
    $ journalctl -u ssh -f                       # watch live while logging in

The reason both commands matter: `systemctl status` tells you the state of the unit and
shows a handful of recent lines, while `journalctl -u` gives you as much history as you
ask for. So the routine when a service will not come up is `systemctl status` to confirm
it failed, then `journalctl -u <name> -n 50` to read the actual error, fix the config,
`systemctl restart`, and finally `-f` to watch it start cleanly.

## Task 4: Command Cheat Sheet

**Moving around.** `pwd` prints where you are, `ls -lah` lists everything including
hidden files with readable sizes, `cd /path` goes somewhere, `cd ..` goes up one level,
`cd -` jumps back to the previous directory.

**Files and directories.** `touch file` makes an empty file, `mkdir -p a/b/c` creates a
whole tree at once, `cp src dst` copies and `cp -r` copies a directory, `mv a b` both
moves and renames, `rm file` deletes and `rm -r dir` deletes a directory. There is no
recycle bin, so read the path twice before running `rm -rf`.

**Reading files.** `cat file` dumps it, `less file` pages through it, `head -20` and
`tail -20` show the ends, `tail -f` follows a growing log, `wc -l` counts lines.

**Searching.** `grep "text" file` finds a pattern, `grep -ri "text" dir/` searches a
tree case insensitively, `find . -name "*.log"` finds files by name, `which python3`
shows which binary would actually run.

**Permissions.** `chmod 755 file`, `chmod +x script.sh`, `chown user:group file`. The
numbers are read 4, write 2, execute 1, summed per class and written owner, group,
others. So 644 means the owner can read and write while everyone else can only read,
and 755 adds execute for all three, which is what a script or directory needs.

**Users.** `whoami`, `id`, `adduser name`, `passwd name`, `usermod -aG sudo name`,
`su - name`, `sudo -i`. The `-a` in `usermod -aG` means append, and leaving it out
replaces every group the user was in, which is an easy way to lock somebody out.

**Processes and services.** `ps aux` lists everything, `ps aux | grep nginx` narrows it,
`top` and `htop` watch live, `kill PID` asks a process to stop and `kill -9 PID` forces
it, `pkill name` kills by name. For services,
`systemctl status|start|stop|restart|enable <name>` plus `journalctl -u <name> -f`.

**System and network.** `df -h` free disk space, `du -sh *` what is using it here,
`free -h` memory, `uname -a` kernel and architecture, `uptime` load, `lsblk` disks,
`ip a` addresses, `ping host`, `curl -I url`, `wget url`, `ss -tulpn` listening ports,
`ssh user@host`, `scp file user@host:/path`.

**Archives.** `tar -czvf out.tar.gz dir/` creates one and `tar -xzvf out.tar.gz`
extracts it. The letters are c create, x extract, z gzip, v verbose, f filename, and f
has to come last because the filename follows it.

**Pipes and redirection.** `|` feeds one command's output into the next, `>` writes to a
file and overwrites it, `>>` appends, `2>` redirects errors, `2>&1` folds errors into
normal output. For example `cat access.log | grep " 500 " | wc -l` counts the server
errors in a log.

**Getting help.** `man ls` for the full manual, `ls --help` for a quick flag list,
`history` for what you ran before, and Ctrl+R to search backwards through it.
