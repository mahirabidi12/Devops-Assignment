#!/bin/bash
# System Information Script
# Shows a few system details on screen, then asks where to store a
# full process listing and writes it there.

# --- system details, kept in variables ---
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

# --- ask the user where the report should go ---
read -p "Enter a directory name to create: " TARGET_DIR
read -p "Enter a file name for the process list: " TARGET_FILE

mkdir -p "$TARGET_DIR"
touch "$TARGET_DIR/$TARGET_FILE"

# --- write the full process list into that file ---
ps aux > "$TARGET_DIR/$TARGET_FILE"

echo ""
echo "Directory created : $TARGET_DIR"
echo "File created      : $TARGET_DIR/$TARGET_FILE"
echo "Lines saved       : $(wc -l < "$TARGET_DIR/$TARGET_FILE")"
echo "Done."
