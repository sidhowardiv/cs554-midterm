# One service in Compose and Kubernetes

## Deployment design

The workload is a small Node.js HTTP service derived from the instructor's starter. Its root response identifies the service and serving hostname and returns an in-memory request count. Only successful `GET /` requests increment this counter; `/health` and unsuccessful requests do not. A restart creates a fresh counter. Replicas have independent counters, which is intentional. Environment variables configure the port, service name, and message. Standard-output logs expose startup and request status.

One `cs554-service:1.0` image is built on the Apple Silicon host. The exact image is exported and loaded into Docker and imported into K3s containerd inside the dedicated Lima VM. `evidence/image.txt` records image identity; `evidence/compose.txt` and `evidence/kubernetes.txt` contain deployment observations. Docker records the OCI index digest, while Kubernetes reports the underlying image configuration digest. The saved archive and K3s import digest establish that both came from the same build.

The physical Mac supplies CPU, memory, storage, and virtualization. The Linux VM has its own guest kernel. A container isolates the application's processes and filesystem while sharing the guest kernel. Node is the application process inside that container; a container is not a separate VM. Compose manages containers through the VM's Docker Engine. K3s provides a local Kubernetes control plane and controllers that reconcile declared workload state.

## Request paths

```text
Physical Mac host
  curl http://127.0.0.1:8088/
      |
      | Lima host-agent TCP forwarding, loopback 8088 -> VM 8088
      v
  Dedicated Lima Linux VM cs554-vm
  user-mode NAT; guest interface 192.168.5.15; 2 vCPU / 2 GiB
      |
      | Docker published port 8088 -> container TCP 8080
      v
  Compose web container -> Node process listening on 0.0.0.0:8080

Same dedicated Lima Linux VM cs554-vm
  K3s control plane and containerd
    client Pod -> web ClusterIP:80 -> ready web Pod IP:8080
                                     two desired replicas
```

The assignment allows Kubernetes in a suitable local VM; here it shares the Linux guest with Compose but uses its own containerd runtime and Pods. The host reaches Compose through Lima forwarding, avoiding a public or bridged IP. Kubernetes requests originate from a client Pod and traverse the Service, so the tests depend on its selector and ready endpoints. A Service port-forward may stay pinned to one Pod and does not establish balanced traffic or all replicas' eligibility.

## Compose and Kubernetes observations

The Compose evidence records requests inside the VM and from the host, status, logs, and a restart. The initial root requests increase the same process's counter. After `docker compose restart web`, the first root request returns 1 because memory belongs to the former Node process. Compose's restart policy can restart an exited container while Docker is available, but it does not provide Kubernetes-style replica scheduling and Service endpoint management.

Kubernetes declares two replicas. Deleting a web Pod leaves the ReplicaSet below its desired count, so a controller creates a new Pod. The new Pod gets a different identity and starts its own counter; the surviving replica keeps its process. The evidence records names before and after deletion and the return to two ready replicas. This demonstrates reconciliation after Pod deletion within the existing cluster, not tolerance of a physical host failure.

## Service selector investigation

The working Service selector is `app: cs554-web`, matching both application Pods. The controlled change sets it to `app: does-not-exist` without changing the Deployment. Both Pods remain ready, but the Service has no matching backends. A fresh in-cluster request fails. Inspection compares the Service selector with Pod labels and records EndpointSlices. Restoring the selector brings endpoints and successful requests back.

This separates application health from reachability. The process can respond correctly at its own address while discovery and routing configuration prevent clients from reaching it through the Service. Pod readiness alone says nothing about whether a particular Service selects the Pod. The correction is to repair the selector; restarting healthy application processes would not repair this configuration error.

## Graduate resource and readiness interpretation

Each application container requests 50 millicores of CPU and 32 MiB of memory, with limits of 250 millicores and 128 MiB. These are modest starting settings for a dependency-free demonstration service, not capacity measurements under production load. A CPU request of 50m is 0.05 CPU; the scheduler accounts for requests when placing Pods. Two replicas therefore request 100m and 64 MiB in total. CPU limits constrain execution through throttling; exceeding a memory limit can lead to an out-of-memory termination. Requests and limits are not interchangeable, and a memory request is not an upper bound. The client Pod is only an experiment tool. See [Kubernetes resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

The readiness probe checks `/health` every two seconds and marks a replica unready after two consecutive failures. Creating `/tmp/not-ready` in exactly one application container makes its health endpoint return 503 while root requests still work. The evidence compares Pod UID, container ID, and restart count across failure and recovery. The selected Pod stays Running but becomes 0/1 Ready; its EndpointSlice entry has `ready: false`, while the other replica remains eligible. Eight fresh in-cluster Service requests exercise the remaining ready backend. Removing the file restores readiness and eligibility.

Readiness controls participation in Service traffic. It does not itself restart a container; no liveness probe was configured here. EndpointSlice state and an in-cluster client establish eligibility more directly than a Pod port-forward. See [Kubernetes probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/).

## OpenStack deployment plan

I would deploy this service into the instructor's existing project using a supported Ubuntu cloud image and a small flavor with approximately one vCPU, 2 GiB RAM, and 10–20 GiB root disk. This is a proposed starting size for Linux, Docker, and one small Node process; I would verify actual availability and usage before resizing. The administrator would normally supply the project, quota, enabled compute services, permitted flavors, external network, and approved base images. I would select those supplied resources, import my SSH public key as a key pair, and create a project security group. Nova's [instance launch guide](https://docs.openstack.org/nova/latest/user/launch-instances.html) identifies these launch inputs.

Within project permissions, I would create a tenant network and subnet with DHCP, then attach a router interface to that subnet and set its gateway to the administrator's external network. If this topology already exists, I would reuse it after checking ownership and routing. The VM would receive a fixed address on the tenant subnet. I would allocate an available floating IP from the external pool and associate it with the VM's Neutron port. This assumes the external pool is reachable from the instructor's client network; a floating IP need not be globally Internet-routable. [Neutron networking](https://docs.openstack.org/neutron/latest/admin/intro-os-networking.html) provides these network, subnet, port, routing, and NAT functions.

Keystone authenticates my project-scoped user and issues the token used for authorized API requests. Glance supplies the selected guest OS image; Nova creates and schedules the instance using that image, flavor, key pair, and network attachment. Neutron supplies connectivity. These are cloud responsibilities; Docker Compose runs later inside the guest to start and configure the application container. See [Keystone identity](https://docs.openstack.org/security-guide/identity.html) and [Glance images](https://docs.openstack.org/glance/latest/). I would install Docker Engine and Compose, transfer or pull the tested application image, and start the submitted Compose configuration. The image architecture must match the VM; an x86 instance needs an x86 or multi-platform build of the same application version.

Persistent block storage is unnecessary because the service intentionally keeps no durable data. Its request count should reset with the process, and source/configuration belongs in the repository. I would use the VM's ordinary root disk and would not request a separate Cinder data volume. A future durable database would change that choice, but adding one would change this workload.

An external HTTP request would travel to the floating IP on TCP 8088, through the cloud's external routing and floating-IP translation to the fixed-address VM, subject to Neutron port security and its security group. Docker's published 8088 port forwards to container port 8080, where Node listens on all container interfaces. I would allow inbound TCP 8088 from the grader's approved source network. TCP 22 is a separate SSH administration rule restricted to my management source. ICMP is optional for diagnostics; allowing ping neither permits HTTP nor proves that the application is listening. VM firewall rules must also permit the application path.

If the instance is running but HTTP fails, I would first inspect the console and cloud-init completion, then check `docker compose ps`, logs, and an internal container request. Next I would request VM loopback port 8088 and inspect Docker's published mapping, socket listeners, and guest firewall. A working loopback request narrows the fault toward external connectivity. I would then inspect the fixed address, Neutron port status, security-group attachment and rules, floating-IP association, router interfaces, gateway, and client route. I would collect timestamped curl errors, container logs, port mappings, and network-resource output. Packet capture at the guest could distinguish absent inbound traffic from an application response problem.

Operating the cloud also requires coordinating APIs, identity, hypervisors, network backends, databases, and messaging. A broken network agent or external bridge can prevent connectivity before Compose is involved. The course’s [DevStack troubleshooting guidance](https://github.com/UAH-Computer-Science/cs454-Course-Exercises/blob/8c572c153086cc68773c0e5804ccc0104ca34b3e/exercise-05-openstack-iaas/OPTIONAL-LOCAL-DEVSTACK.md#optional-stretch-goal-launch-an-instance) gives a concrete example: reaching the DevStack host’s LAN IP does not make instance floating IPs reachable from a laptop; external routing or NAT may still be missing. That is infrastructure setup, whereas a wrong Compose port mapping is application deployment. Testing first from the DevStack host separates those paths. A VM with Compose is sufficient for this single small service when manual host management is acceptable. Kubernetes additionally demonstrated declared replication, automatic Pod replacement, and readiness-based traffic eligibility.

## References and evidence

The linked official documentation supports the platform explanations. The instructor starter and assignment supply the service behavior and experiment requirements. The course troubleshooting example is cited to its exact repository revision, rather than attributed to an unverified live lecture. Full commands and original results are in `evidence/` and `scripts/experiments.sh`.
