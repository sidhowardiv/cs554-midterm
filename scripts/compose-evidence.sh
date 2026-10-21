#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_DIR="$PWD"
LIMA=${LIMA:-/opt/homebrew/bin/limactl}
set -x
date -u
"$LIMA" list cs554-vm
"$LIMA" shell cs554-vm uname -a
"$LIMA" shell cs554-vm cat /etc/os-release
"$LIMA" shell cs554-vm ip -4 addr show
"$LIMA" shell cs554-vm ip route
"$LIMA" shell cs554-vm docker version
"$LIMA" shell cs554-vm docker compose version
"$LIMA" shell cs554-vm docker image inspect cs554-service:1.0 --format '{{.Id}}'
"$LIMA" shell cs554-vm bash -lc 'cd "$1" && docker compose up -d' _ "$PROJECT_DIR"
"$LIMA" shell cs554-vm curl --retry 10 --retry-connrefused --retry-delay 1 -fsS http://127.0.0.1:8088/
"$LIMA" shell cs554-vm curl -fsS http://127.0.0.1:8088/health
printf '\nHOST REQUESTS\n'
curl --retry 10 --retry-connrefused --retry-delay 1 -fsS http://127.0.0.1:8088/
curl -fsS http://127.0.0.1:8088/health
"$LIMA" shell cs554-vm bash -lc 'cd "$1" && docker compose ps && docker compose logs --tail=20' _ "$PROJECT_DIR"
printf '\nCOUNTER BEFORE RESTART\n'
"$LIMA" shell cs554-vm curl -fsS http://127.0.0.1:8088/
"$LIMA" shell cs554-vm bash -lc 'cd "$1" && docker compose restart web' _ "$PROJECT_DIR"
printf '\nFIRST ROOT REQUEST AFTER RESTART\n'
"$LIMA" shell cs554-vm curl --retry 10 --retry-connrefused --retry-delay 1 -fsS http://127.0.0.1:8088/
"$LIMA" shell cs554-vm bash -lc 'cd "$1" && docker compose ps && docker compose logs --tail=20' _ "$PROJECT_DIR"
printf '\nHOST AFTER RESTART\n'
curl -fsS http://127.0.0.1:8088/
printf '\n'
