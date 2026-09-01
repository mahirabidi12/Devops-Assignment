# System Information Script

A bash script that reports a few facts about the machine, then asks the user where to
put a report and writes the complete process list into that file.

## What the script does

1. Collects the date, the hostname and the current user into variables and prints them.
2. Prints the disk usage with `df -h`.
3. Prints the first ten processes with `ps`.
4. Uses `read -p` to ask for a directory name and then a file name.
5. Creates the directory with `mkdir` and the empty file with `touch`.
6. Redirects the output of `ps aux` into that file with `>`.

## Concepts and commands used

Variables and command substitution with `$(...)`, `echo`, `date`, `hostname`, `whoami`,
`df`, `ps`, interactive input with `read -p`, `mkdir`, `touch`, and output redirection
with `>`.

## The script

    #!/bin/bash
    # System Information Script

    RUN_DATE=$(date)
    MACHINE=$(hostname)
    LOGGED_IN=$(whoami)

    echo "=============================="
    echo "     SYSTEM INFORMATION"
    echo "=============================="
    echo "Date     : $RUN_DATE"
    echo "Hostname : $MACHINE"
    echo "Username : $LOGGED_IN"
    echo ""

    echo "----- Disk Usage -----"
    df -h
    echo ""

    echo "----- Running Processes (first 10) -----"
    ps -eo pid,user,%cpu,%mem,comm | head -10
    echo ""

    read -p "Enter a directory name to create: " TARGET_DIR
    read -p "Enter a file name for the process list: " TARGET_FILE

    mkdir -p "$TARGET_DIR"
    touch "$TARGET_DIR/$TARGET_FILE"

    ps aux > "$TARGET_DIR/$TARGET_FILE"

    echo ""
    echo "Directory created : $TARGET_DIR"
    echo "File created      : $TARGET_DIR/$TARGET_FILE"
    echo "Lines saved       : $(wc -l < "$TARGET_DIR/$TARGET_FILE")"
    echo "Done."

The full file is `sysinfo.sh` in this folder.

## Running it

    chmod +x sysinfo.sh
    ./sysinfo.sh

`chmod +x` is needed once, otherwise the shell refuses with a permission denied. The two
prompts are answered by hand; I used `sysreport` and `processes.txt`.

## Output

    ==============================
         SYSTEM INFORMATION
    ==============================
    Date     : Tue Sep  1 20:30:31 IST 2026
    Hostname : Mahirs-MacBook-Air.local
    Username : mahirabidi

    ----- Disk Usage -----
    Filesystem        Size    Used   Avail Capacity  Mounted on
    /dev/disk3s1s1   228Gi    17Gi   3.0Gi    85%    /
    devfs            206Ki   206Ki     0Bi   100%    /dev
    /dev/disk3s6     228Gi    12Gi   3.0Gi    80%    /System/Volumes/VM
    /dev/disk3s2     228Gi    15Gi   3.0Gi    84%    /System/Volumes/Preboot
    /dev/disk3s4     228Gi   749Mi   3.0Gi    20%    /System/Volumes/Update
    /dev/disk3s5     228Gi   178Gi   3.0Gi    99%    /System/Volumes/Data

    ----- Running Processes (first 10) -----
      PID USER              %CPU %MEM COMM
        1 root               0.0  0.0 /sbin/launchd
      321 root               0.7  0.1 /usr/libexec/logd
      323 root               0.1  0.1 /usr/libexec/UserEventAgent
      325 root               0.5  0.0 .../FSEvents.framework/Versions/A/Support/fseventsd
      326 root               0.0  0.1 .../MediaRemote.framework/Support/mediaremoted
      329 root               0.0  0.0 /usr/sbin/systemstats
      332 root               0.0  0.1 /usr/libexec/configd
      334 root               0.0  0.1 /System/Library/CoreServices/powerd.bundle/powerd
      335 root               0.0  0.0 /usr/libexec/IOMFB_bics_daemon

    Enter a directory name to create: sysreport
    Enter a file name for the process list: processes.txt

    Directory created : sysreport
    File created      : sysreport/processes.txt
    Lines saved       : 549
    Done.

The disk and process blocks above are shortened so they fit on the page. The script
itself prints every line, `df -h` listed twelve filesystems on this machine.

## Checking that the file really was written

    $ ls -l sysreport/
    -rw-r--r--@ 1 mahirabidi  staff  164419  1 Sep 20:30 processes.txt

    $ head -3 sysreport/processes.txt
    USER          PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
    mahirabidi  71199  67.3  3.6 1926458576 302544  ??  R     8:19PM   1:59.26 /Applica...
    root          418  42.6  0.3  426959808  21424  ??  Ss   16Aug26 108:20.69 /usr/lib...

    $ wc -l sysreport/processes.txt
    549 sysreport/processes.txt

549 lines against the 10 shown on screen, which is the point of saving the full listing
to a file rather than printing it. The directory is in `.gitignore`, since it is
generated every time the script runs and is not part of the submission.

## Notes on the details

This was run on macOS, so the volume names like `/dev/disk3s1s1` and the process paths
under `/System/Library` are Apple specific. The script needs no changes on Linux, the
output just looks different there, with filesystems named `/dev/sda1` or similar.

`ps -eo pid,user,%cpu,%mem,comm` is used for the on screen part instead of plain
`ps aux`, because `ps aux` prints very long command lines that wrap and make the ten
lines unreadable. The file still gets the untrimmed `ps aux` output.

`mkdir -p` rather than `mkdir` means running the script a second time with the same
directory name does not fail with "File exists".

Every variable is quoted, including `"$TARGET_DIR/$TARGET_FILE"`, so a directory or file
name containing a space is still handled as one argument instead of being split.

`wc -l < file` is used rather than `wc -l file`, because the redirection form prints only
the number, without repeating the filename after it.
