# Deployment evidence

These files contain terminal output from actual runs on the host. The experiments are scoped to this project. Source commands are available in `../scripts/`.

| File | What it establishes |
| --- | --- |
| `tests.txt` | Starter request, configuration, health, counter, and fresh-instance test passed inside the application image |
| `cluster.txt` | Linux VM node, Kubernetes version, guest OS, and container runtime |
| `image-import.txt` | Same exported OCI image imported into K3s containerd |
| `image.txt` | Build identity and architecture; VM and Kubernetes identity observations follow deployment |
| `compose.txt` | Linux guest and Docker versions, VM networking, successful guest/host requests, Compose status and logs, counter before and after restart |
| `kubernetes.txt` | Two ready application replicas; successful Service requests; Pod deletion/replacement; healthy Pods with selector mismatch and no backends; selector recovery; one Running but NotReady replica; EndpointSlice eligibility and recovery |

In `kubernetes.txt`, find these exact section labels:

- `Baseline`: both application Pods Ready and EndpointSlice backends ready.
- `Pod deletion / replacement`: original Pod name, deletion, new name, and restored replicas.
- `Selector failure`: patched selector, healthy Pod labels, missing backends, and failed in-cluster request.
- `Selector recovery`: matching selector and working Service request.
- `Graduate readiness baseline`: healthy replicas and selected Pod identity.
- `One Running but NotReady`: one Pod has 0/1 readiness while phase is Running; EndpointSlice `ready: false`; a direct local root request still succeeds; Service requests reach the remaining eligible Pod.
- `Readiness recovery`: both Pods Ready and eligible; selected Pod UID/container ID/restart count confirm continuity.

EndpointSlice objects may retain an unready endpoint with `ready: false`; exclusion from ready endpoints does not require deleting that entry. Read the conditions alongside its target Pod name.

The direct root request to the NotReady Pod proves process availability only. Traffic eligibility is established separately through the Service and EndpointSlices. No claim of guaranteed round-robin distribution is made. Kubernetes tests demonstrate recovery inside a local cluster, not resilience to losing the physical Mac.

## Recorded results

On October 21, 2026, Compose answered both endpoints from the guest and host. Its root count was 3 before restart and 1 on the first root request afterward. The VM’s Docker inspection and K3s import both identify OCI index digest `50ab79533c9d12bd3a51495a5231118205e5d5975c5fa92f7cdf962ad4cb19e0`.

The Kubernetes Service was `10.43.176.65:80`. Pod `web-ddd46f5c9-58gqk` was deleted and replaced by `web-ddd46f5c9-cxhs2`; `web-ddd46f5c9-fb4cb` survived. With the wrong selector, both replicas stayed Ready while the client request failed. Restoring the selector restored HTTP 200.

For readiness, `web-ddd46f5c9-cxhs2` became Running but NotReady, retaining its UID, container ID, and zero restart count. Its endpoint became `ready: false`. A direct local root request still returned 200. All eight fresh Service requests returned the other hostname, `web-ddd46f5c9-fb4cb`. After removing the file, both endpoints became ready and a Service request again reached `web-ddd46f5c9-cxhs2`.
