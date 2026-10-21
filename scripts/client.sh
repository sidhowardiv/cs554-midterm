#!/bin/sh
set -eu
bash "$(dirname "$0")/kubectl.sh" -n cs554-midterm exec client -- node -e '
fetch("http://web/" + (process.argv[1] || ""), {signal: AbortSignal.timeout(3000)})
.then(async r=>{console.log("HTTP",r.status,await r.text());if(!r.ok)process.exitCode=1})
.catch(e=>{console.error(e.name,e.message);process.exitCode=1})' "${1:-}"
