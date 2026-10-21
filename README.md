# CS554 service deployment project

This project deploys one HTTP image using Compose inside a dedicated Lima Linux VM and a two-replica Kubernetes Deployment. The report, original terminal evidence, and graduate readiness experiment are included.

**Recording:** [Watch or download the narrated walkthrough](video/walkthrough.mp4) — 4 minutes 27 seconds. If GitHub does not play it inline, choose **View raw** or **Download**.

**Repository:** https://github.com/sidhowardiv/cs554-midterm

**Before submission:** verify grader access to the repository and video, then submit the links in Canvas. See `SUBMISSION.md`.

## Prerequisites and tools

The recorded environment uses an Apple Silicon macOS host, Docker Desktop for the image build, Lima with Apple's Virtualization.framework (`vz`), and a single-node K3s v1.31.5 Kubernetes cluster. Both deployment environments run inside the dedicated Ubuntu 26.04 ARM64 VM `cs554-vm` (2 vCPU / 2 GiB): Compose uses rootless Docker Engine 29.9.2, while K3s uses its separate containerd runtime. Compose and Kubernetes have separate containers, networks, and process-local counters. Kubernetes is not running on the Mac or in Docker Desktop for the recorded experiment.

Install Docker Desktop and Lima; on this Mac Lima was installed with `brew install lima`. Start Docker Desktop before building the image. The K3s setup below installs Kubernetes inside the VM. On this 8 GB Mac, Docker Desktop was temporarily stopped after the image archive was exported to give the Linux VM enough host memory during Kubernetes tests, then restored afterward. The Compose daemon inside Lima stays running independently. No npm install is needed. Node 22 is supplied by the application image. All project Kubernetes resources use namespace `cs554-midterm`.

Commands below run from this directory on the host unless prefixed with `limactl shell`. Put Homebrew tools on PATH, for example `export PATH=/opt/homebrew/bin:$PATH` on this Mac.

## Application and image

The instructor's starter at [cs454-midterm-starter](https://github.com/UAH-Computer-Science/cs454-Course-Exercises/tree/main/cs454-midterm-starter), commit `8c572c153086cc68773c0e5804ccc0104ca34b3e`, supplies the Node service and tests. The project adds its own Dockerfile, Compose configuration, Kubernetes manifests, and a small health toggle for the graduate experiment.

`GET /` returns service, message, hostname, and a process-local requestCount. Only successful root GET requests increment the count; health checks do not. `GET /health` normally returns 200. A file `/tmp/not-ready` makes that one process's health response 503 without disabling `/` or exiting. Other routes return 404. PORT, SERVICE_NAME, and MESSAGE are configurable. Each request and startup are logged to standard output. No database or shared counter is used.

```bash
docker build -t cs554-service:1.0 .
docker run --rm cs554-service:1.0 npm test
docker image inspect cs554-service:1.0 --format '{{.Id}}'
```

The build creates a native ARM64 image on this Mac. For an x86 cloud, build for that architecture or publish a multi-platform image; the OpenStack plan discusses that separate deployment choice.

## Linux VM and Compose

Create and start the VM once. Initial provisioning downloads Linux and installs Docker, which can take several minutes. If the Lima start command times out while provisioning, check `limactl list` and wait until `limactl shell cs554-vm docker info` succeeds before continuing:

```bash
limactl start --name=cs554-vm --cpus=2 --memory=2 --disk=12 --vm-type=vz --tty=false template:docker
# On subsequent starts:
# limactl start cs554-vm
limactl shell cs554-vm docker version
limactl shell cs554-vm docker compose version
```

Lima uses its default user-mode NAT network. Its host agent automatically forwards the VM's published TCP port 8088 onto the host loopback port 8088. Neither a bridged address nor a public IP is needed. Keep port 8088 free on the host. Project files under `/Users` are visible inside the VM through Lima's host mount. Run these on the host to import the **same built image**, then start Compose inside the VM:

```bash
PROJECT_DIR="$PWD"
mkdir -p ../../work
docker save -o ../../work/cs554-service.tar cs554-service:1.0
limactl shell cs554-vm docker load -i "$PROJECT_DIR/../../work/cs554-service.tar"
limactl shell cs554-vm bash -lc 'cd "$1" && docker compose up -d' _ "$PROJECT_DIR"
limactl shell cs554-vm curl -fsS http://127.0.0.1:8088/
limactl shell cs554-vm curl -fsS http://127.0.0.1:8088/health
curl -fsS http://127.0.0.1:8088/
curl -fsS http://127.0.0.1:8088/health
limactl shell cs554-vm bash -lc 'cd "$1" && docker compose ps && docker compose logs --tail=20' _ "$PROJECT_DIR"
```

The `../../work` image archive is temporary and must not be submitted. If you move this project, pick another temporary directory that Lima mounts and adjust the import path.

Restart and observe the first root request return count 1:

```bash
limactl shell cs554-vm bash -lc 'cd "$1" && docker compose restart web' _ "$PWD"
limactl shell cs554-vm curl --retry 10 --retry-connrefused --retry-delay 1 -fsS http://127.0.0.1:8088/
```

## Kubernetes setup and image loading

Install K3s **inside the VM**, following the [official installation method](https://docs.k3s.io/quick-start). The version is pinned for this experiment. Traefik and metrics-server are disabled because this project uses a ClusterIP Service and an in-cluster client.

```bash
limactl shell cs554-vm bash -lc 'curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh && sudo env INSTALL_K3S_VERSION=v1.31.5+k3s1 sh /tmp/install-k3s.sh server --disable=traefik --disable=metrics-server'
bash scripts/kubectl.sh get nodes -o wide
# Same archive already imported into Docker for Compose:
limactl shell cs554-vm sudo k3s ctr images import "$PWD/../../work/cs554-service.tar"
bash scripts/kubectl.sh apply -f "$PWD/k8s/app.yaml"
bash scripts/kubectl.sh apply -f "$PWD/k8s/client.yaml"
bash scripts/kubectl.sh -n cs554-midterm rollout status deployment/web --timeout=120s
bash scripts/kubectl.sh -n cs554-midterm wait pod/client --for=condition=Ready --timeout=120s
bash scripts/kubectl.sh -n cs554-midterm get deployment,pods,service -o wide
bash scripts/client.sh
bash scripts/client.sh health
```

`scripts/kubectl.sh` executes `limactl shell cs554-vm sudo k3s kubectl`. It keeps cluster credentials inside the VM and avoids changing the host's Kubernetes context. Manifest paths supplied to it must be absolute paths visible through the Lima mount. Inside the VM you can use `sudo k3s kubectl` directly instead.

K3s containerd and Docker have separate image stores. Importing the archive into both makes the **same application image** available in both environments. The Deployment uses `imagePullPolicy: Never`, so Kubernetes cannot silently pull a different version. Import again after rebuilding; restart the Deployment to run that new build.

The client helper runs Node fetch in the client Pod against `http://web:80`; the Service routes to eligible application Pods on 8080. Each invocation makes a fresh connection. This access path depends on Service selection and endpoint readiness. It does not establish guaranteed round-robin distribution. For an optional browser demo, run `bash scripts/kubectl.sh -n cs554-midterm port-forward svc/web 8090:80 --address 0.0.0.0` and open `http://localhost:8090` through Lima forwarding. That session may pin one Pod and should not be used to establish readiness traffic eligibility.

## Reproduce all Kubernetes experiments

```bash
set -o pipefail
bash scripts/experiments.sh 2>&1 | tee evidence/kubernetes.txt
```

The script records baseline, Pod replacement, selector failure/recovery, and one-Pod readiness failure/recovery, including EndpointSlices, labels, application responses, and restart counts. It restores the selector and readiness file on exit. During the readiness failure, a direct root request **only** proves that the selected process is still running; the separate in-cluster requests and EndpointSlices establish Service eligibility. No Deployment template change or container crash is involved.

The selector failure patches `app: cs554-web` to `app: does-not-exist`. The readiness failure uses `kubectl exec <one-pod> -- touch /tmp/not-ready`; remove that file to recover. All exact commands are in the script.

## Evidence and report

Read `REPORT.md`, `evidence/README.md`, `evidence/cluster.txt`, `evidence/image-import.txt`, `evidence/compose.txt`, `evidence/kubernetes.txt`, `evidence/image.txt`, and `evidence/tests.txt`. Evidence is saved text, so grading does not depend on live access to this computer.

## Cleanup

Run after recording:

```bash
limactl shell cs554-vm bash -lc 'cd "$1" && docker compose down' _ "$PWD"
bash scripts/kubectl.sh delete namespace cs554-midterm
limactl stop cs554-vm
# Optional, permanently discard only this assignment VM:
# limactl delete cs554-vm
# Remove the temporary transfer archive after loading:
rm -f ../../work/cs554-service.tar
```

Deleting the dedicated Lima VM also removes this project’s K3s installation. Keep unrelated Docker applications and clusters running. No VM disks, image archives, credentials, or dependencies belong in the submission.
