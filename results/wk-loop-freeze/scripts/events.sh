#!/bin/sh
awk -F'\t' '{print substr($3,12,12) " " substr($3,26)}' "$1" | sed 's/\x1b\[[0-9;]*m//g' |
  grep -n -E "blocked|stalled|giving up|inspector probe|terminate|reboot|exit code|forced|attempt|recover|relaunch|pass [0-9]/|warm-up|cli: exit|SIGTERM|census y=3000" | cut -c1-230
