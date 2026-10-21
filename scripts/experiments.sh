#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
K=(bash scripts/kubectl.sh -n cs554-midterm)
snapshot() {
  "${K[@]}" get deployment,pods,service -o wide
  "${K[@]}" get pods -l app=cs554-web --show-labels
  "${K[@]}" get endpointslice -l kubernetes.io/service-name=web -o yaml
}
restore() {
  "${K[@]}" patch svc web --type=merge -p '{"spec":{"selector":{"app":"cs554-web"}}}' >/dev/null || true
  if [[ -n "${target:-}" ]]; then "${K[@]}" exec "$target" -- rm -f /tmp/not-ready || true; fi
}
trap restore EXIT
printf '
=== Baseline ===
'
"${K[@]}" rollout status deployment/web --timeout=120s
snapshot
bash scripts/client.sh
bash scripts/client.sh health
printf '
=== Pod deletion / replacement ===
'
target=$("${K[@]}" get pod -l app=cs554-web -o jsonpath='{.items[0].metadata.name}')
"${K[@]}" get pod "$target" -o wide
"${K[@]}" delete pod "$target" --wait=true
"${K[@]}" wait pod -l app=cs554-web --for=condition=Ready --timeout=120s
"${K[@]}" rollout status deployment/web --timeout=120s
snapshot
printf '
=== Selector failure: app=cs554-web -> app=does-not-exist ===
'
"${K[@]}" patch svc web --type=merge -p '{"spec":{"selector":{"app":"does-not-exist"}}}'
sleep 5
snapshot
if bash scripts/client.sh; then echo 'ERROR: expected failure'; exit 1; else echo 'Expected client failure observed'; fi
printf '
=== Selector recovery ===
'
"${K[@]}" patch svc web --type=merge -p '{"spec":{"selector":{"app":"cs554-web"}}}'
sleep 5
snapshot
bash scripts/client.sh
printf '
=== Graduate readiness baseline ===
'
snapshot
target=$("${K[@]}" get pod -l app=cs554-web -o jsonpath='{.items[0].metadata.name}')
echo "Selected Pod: $target"
"${K[@]}" get pod "$target" -o jsonpath='{.metadata.uid}{" container="}{.status.containerStatuses[0].containerID}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}'
"${K[@]}" exec "$target" -- touch /tmp/not-ready
"${K[@]}" wait pod/"$target" --for=condition=Ready=false --timeout=60s
sleep 3
printf '
=== One Running but NotReady ===
'
snapshot
"${K[@]}" exec "$target" -- node -e 'fetch("http://127.0.0.1:8080/").then(async r=>console.log(r.status,await r.text()))'
"${K[@]}" get pod "$target" -o jsonpath='{.metadata.uid}{" container="}{.status.containerStatuses[0].containerID}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}'
for i in {1..8}; do bash scripts/client.sh; done
printf '
=== Readiness recovery ===
'
"${K[@]}" exec "$target" -- rm /tmp/not-ready
"${K[@]}" wait pod/"$target" --for=condition=Ready --timeout=60s
sleep 3
snapshot
bash scripts/client.sh
"${K[@]}" get pod "$target" -o jsonpath='{.metadata.uid}{" container="}{.status.containerStatuses[0].containerID}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}'
"${K[@]}" logs "$target" --tail=25
