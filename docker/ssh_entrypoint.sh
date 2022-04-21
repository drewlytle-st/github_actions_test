#!/bin/bash
set -e

# export the environment to a file since ssh strips the environment
echo 'Exporting the environment to a file since ssh strips the environment...'
declare -px > /environment

exec /usr/sbin/sshd -D
