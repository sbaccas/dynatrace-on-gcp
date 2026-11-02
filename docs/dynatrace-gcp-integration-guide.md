# Dynatrace + Google Cloud Full-Stack Observability: Implementation & Architecture Guide

This guide documents the architecture, configuration steps, and operational insights for deploying the Dynatrace Google Cloud Observability Platform using this repository as an enterprise reference model.

It covers:
- GCP Resource hierarchy (Folders, Scoping Projects, Workload Projects)
- Automated Bootstrap and Terraform Infrastructure-as-Code
- GKE Private Cluster with Workload Identity and Private Google Access (PGA)
- Dynatrace GCP Log and Metric Forwarders (Helm)
- Regional ActiveGate Multi-Zone Cluster & OneAgent Host Monitoring (Phase 2)
- Critical Dynatrace Hub extension requirements and Autodiscovery behavior
- Verification and Troubleshooting Playbook
- **Enterprise Scale, Governance & Automated CI/CD Lifecycle** (375-Project Sharding with Secure Tags, On-Demand ActiveGates, Golden Image Factory)


---

## 1. Enterprise Landing Zone Placement & Stage Ordering

In an enterprise Google Cloud Landing Zone architecture (such as Google Cloud Foundation Fabric or Cloud Foundation Toolkit), the Dynatrace Observability Platform is designed to be a **foundational infrastructure stage** positioned directly under the **Organization Root**:

```text
Organization Root: enterprise-org.example.com
├── [Folder] Observability   <--- Root-level folder deployed in Foundation Stage (Stage 2)
├── [Folder] Networking      <--- Core Shared VPCs & Interconnects (Stage 3)
└── [Folder] Workloads       <--- Application environments & Service Projects (Stage 4+)
```

### Recommended Landing Zone Stage Sequence:
1. **Stage 0 — Bootstrap**:
   - Seed projects, Cloud Storage Terraform state buckets, CI/CD runner identities, and foundational IAM.
2. **Stage 1 — Organization Governance & Security**:
   - Organization Policies, Resource Manager guardrails, and VPC Service Controls (VPC-SC) perimeters.
3. **Stage 2 — Centralized Observability (This Platform)**:
   - Creation of the root `Observability` folder and its `Scoping Projects` subfolder.
   - Provisioning of the isolated Observability VPC, GKE Forwarder Cluster, Pub/Sub pipeline, and Dynatrace forwarder deployments.
4. **Stage 3+ — Core Networking & Application Workloads**:
   - Shared VPC host projects, application service projects, compute clusters, and database workloads.

### Architectural Rationale:
> [!IMPORTANT]
> **Zero-Telemetry-Gap Day 1 Onboarding:**
> Because all subsequent folders, host projects, service projects, and business applications deployed across the enterprise are monitored using the infrastructure built in this stage, the Observability platform must be operational **before** major workloads come online. Deploying this platform in Stage 2 guarantees that as soon as workload projects are stamped out in Stage 3+, their logs immediately stream to the Pub/Sub topic and their metrics are federated to the Scoping Project with zero telemetry gaps.

---

### Enterprise GCP Resource Hierarchy

The organization resource hierarchy separates operational observability tooling from compute workloads and preserves clean blast-radius boundaries:

```text
Organization: enterprise-org.example.com (123456789012)
│
├── [Folder] Observability (folders/111111111111)
│   ├── [Folder] Scoping Projects (folders/222222222222)
│   │   ├── [Project] dynatrace-scope-01-prod (Project Number: 333333333333)
│   │   │   └── Dedicated empty project hosting Cloud Monitoring Metrics Scope (1:375 project cap)
│   │   └── [Project] dynatrace-scope-02-prod (Reserved for future scaling)
│   │
│   ├── [Project] dynatrace-platform-prod (Project Number: 444444444444)
│   │   ├── Dedicated Observability VPC: dynatrace-observability-vpc (10.20.0.0/24)
│   │   ├── Private GKE Cluster: dynatrace-forwarder-gke (Workload Identity)
│   │   │   ├── Log Forwarder Pod (dynatrace-gcp-logs)
│   │   │   └── Metric Forwarder Pod (dynatrace-gcp-metrics)
│   │   └── Cloud Pub/Sub Pipeline: Topic dynatrace-gcp-logs + Subscription dynatrace-gcp-logs-sub
│   │
│   └── [Folder] ActiveGate Projects (Phase 2)
│       ├── [Project] dynatrace-ag-svc-host-a (1:1 Service Project attached to Shared VPC Host A)
│       └── [Project] dynatrace-ag-svc-host-b (1:1 Service Project attached to Shared VPC Host B)
│
└── [Folder] Workloads / Application Teams
    └── [Project] workload-app-prod (Project Number: 555555555555)
        ├── Workload VPC: workload-vpc (10.10.0.0/24)
        ├── GCE VM: workload-vm-01 (10.10.0.3)
        ├── Metrics federated to dynatrace-scope-01-prod
        └── Log Sink routing to dynatrace-gcp-logs Pub/Sub topic
```

### Architectural Invariant: Why an Isolated "Island" VPC for GKE?

A common question when designing the GKE forwarder platform is whether keeping GKE on an isolated VPC without direct VPC peering or Shared VPC access to application networks limits future expansion. 

**Answer: No, an isolated "island" VPC is the recommended enterprise best practice.**
1. **Strictly Egress/Pull-Only Architecture**:
   - **Metric Forwarder**: Makes outbound REST queries to `monitoring.googleapis.com` via Google's internal API backbone (using Private Google Access - PGA) and pushes metrics outbound over HTTPS to Dynatrace SaaS (`POST https://<tenant>.live.dynatrace.com/api/v2/metrics/ingest`).
   - **Log Forwarder**: Pulls messages from `pubsub.googleapis.com` over PGA and streams them outbound over HTTPS to Dynatrace SaaS (`POST https://<tenant>.live.dynatrace.com/api/v2/logs/ingest`).
   - **Zero Ingress**: Neither forwarder ever exposes an inbound network port or service listener to workloads.
2. **Blast Radius & Security Isolation**:
   - Workload clusters, VMs, and application microservices never have network line-of-sight to the GKE control plane or worker nodes.
   - If an application VPC is compromised, the centralized observability pipeline remains completely insulated.
3. **Multi-Tenant Agnostic**:
   - Because metrics aggregate at the Cloud Monitoring Scoping Project and logs aggregate at the Pub/Sub topic via GCP Log Sinks, the forwarders can monitor hundreds of disparate projects across different VPCs without needing complex routing, overlapping IP coordination, or firewall rules.


---

## 2. Repository Layout & Artifact Map

| Path | Purpose |
| :--- | :--- |
| `scripts/` | **Tutorial Shell Pipeline**: `00_bootstrap.sh`, `01_deploy_terraform.sh`, `02_deploy_forwarders.sh`, `03_install_oneagent.sh`, `04_verify_all.sh`. |
| `bootstrap/` | Automated foundation scripts: creates folders, scoping projects, state bucket, and populates `terraform.tfvars` from `bootstrap.env`. |
| `terraform/environments/prod/` | Root Terraform configuration for production observability infrastructure and ActiveGate cluster. |
| `terraform/modules/` | Reusable modules: `networking` (VPC/PGA/NAT), `dynatrace_iam` (GCP SAs & Workload Identity), `pubsub_logging` (Topic & Subs), `gke_cluster` (Private Cluster), `scoping_project` (Metrics Scopes), `activegate` (Multi-Zone cluster). |
| `helm/dynatrace-gcp-monitor/` | Official Dynatrace GCP monitor Helm chart packaged for local deployment. |
| `helm/values/` | Custom Helm values files for `values-logs.yaml` and `values-metrics.yaml`. |
| `k8s/canary/` | Pre-flight diagnostic canary daemonset/deployment testing Private Google Access, DNS, and IAM token exchange before deploying forwarders. |
| `docs/` | Architectural guides, proposal specifications, and operation runbooks. |

---

## 3. Step-by-Step Implementation Flow

### Automated Tutorial Pipeline (Fast Path)

For anyone deploying this reference model against a new or existing GCP organization, the complete deployment lifecycle is encapsulated into 5 sequential, deterministic shell scripts under `scripts/`:

```bash
# Step 0: Foundation & Bootstrap
# Creates folders, scoping projects, GCS state bucket, enables APIs, generates terraform.tfvars
./scripts/00_bootstrap.sh

# Step 1: Terraform Infrastructure Deployment
# Provisions Observability VPC, Private GKE cluster, Pub/Sub pipeline, and ActiveGate cluster
./scripts/01_deploy_terraform.sh

# Step 2: Deploy Dynatrace GKE Forwarders
# Configures GKE secrets and deploys Metric & Log forwarder Helm releases
./scripts/02_deploy_forwarders.sh

# Step 3: Workload VM OneAgent Deployment
# Downloads and installs OneAgent configured with network zone workload-prod
./scripts/03_install_oneagent.sh

# Step 4: End-to-End Automated Verification
# Runs automated health checks against GKE forwarders, ActiveGates, OneAgent, and VPC routing
./scripts/04_verify_all.sh
```

---

### Step 1: Bootstrap & Scoping Project Hierarchy

In Google Cloud Monitoring, metrics from multiple projects are aggregated through **Cloud Monitoring Scoping Projects**.

#### Best Practice Rule: Isolated Empty Scoping Projects
> [!IMPORTANT]
> A production project with real compute resources (such as `dynatrace-platform-prod` or `workload-app-prod`) must **never** be used as a scoping project for other production projects.
> Scoping projects must be **dedicated, empty projects** residing in a separate `Scoping Projects` folder under the `Observability` folder. This guarantees:
> 1. No noisy-neighbor metric crosstalk.
> 2. Clean separation of IAM permissions (granting `roles/monitoring.viewer` at the scoping project without granting access to application resources).
> 3. Zero accidental deletion or pollution of workload infrastructure.

Run the bootstrap script to create the folders, projects, and seed configuration:
```bash
./bootstrap/bootstrap.sh
```

This ensures:
- Observability folder `Observability` (`folders/111111111111`)
- Dedicated subfolder `Scoping Projects` (`folders/222222222222`)
- Dedicated empty scoping project `dynatrace-scope-01-prod` with `monitoring.googleapis.com` enabled.

---

### Step 2: Infrastructure as Code (Terraform)

Navigate to `terraform/environments/prod`:
```bash
cd terraform/environments/prod
terraform init
terraform plan
terraform apply
```

Key resources provisioned:
1. **Isolated Observability VPC**:
   - Private subnet `10.20.0.0/24` with **Private Google Access (PGA)** enabled.
   - Secondary ranges for GKE Pods (`10.24.0.0/14`) and GKE Services (`10.28.0.0/20`).
   - Cloud NAT gateway for outbound HTTPS to Dynatrace SaaS (`*.apps.dynatrace.com` / `*.live.dynatrace.com`).
2. **Private GKE Cluster (`dynatrace-forwarder-gke`)**:
   - Private nodes (no external public IPs).
   - Workload Identity enabled (`<PROJECT_ID>.svc.id.goog`).
3. **IAM & Workload Identity Service Accounts**:
   - `dt-log-forwarder@dynatrace-platform-prod.iam.gserviceaccount.com` bound to K8s SA `dynatrace-gcp-monitor-logs` in namespace `dynatrace`.
   - `dt-metric-forwarder@dynatrace-platform-prod.iam.gserviceaccount.com` bound to K8s SA `dynatrace-gcp-monitor-metrics` in namespace `dynatrace`.
4. **Cloud Pub/Sub Pipeline**:
   - Topic: `dynatrace-gcp-logs`
   - Subscription: `dynatrace-gcp-logs-sub` (Ack deadline: 120s)
   - Sink: `dynatrace-log-sink` routing `severity>=INFO` logs.
5. **Cloud Monitoring Scoping Associations**:
   - Associating `dynatrace-platform-prod` and `workload-app-prod` as monitored projects inside `dynatrace-scope-01-prod`.

---

### Step 3: Canary Connectivity Verification

Before deploying Dynatrace software, verify that private GKE nodes can reach Google APIs privately via PGA:
```bash
kubectl apply -f k8s/canary/canary-deployment.yaml
./k8s/canary/verify-canary.sh
```
Verify HTTP 204 from `https://monitoring.googleapis.com/generate_204` and `https://pubsub.googleapis.com/generate_204`.

---

### Step 4: Dynatrace SaaS Prerequisites (Dynatrace Console Steps)

Before deploying the forwarders, two critical setup actions must be performed inside your Dynatrace Web Console (`https://<TENANT_ID>.apps.dynatrace.com`):

#### 1. Generate Dynatrace API v2 Ingest Token
1. Go to **Manage** $\rightarrow$ **Access Tokens**.
2. Click **Generate new token**.
3. Provide the name: `gcp-observability-forwarder-token`.
4. Select the following required scopes:
   - `metrics.ingest` (**Ingest metrics**)
   - `logs.ingest` (**Ingest logs**)
5. Copy the generated token string (`dt0c01...`).

Create the Kubernetes secret inside the GKE cluster:
```bash
kubectl create namespace dynatrace --dry-run=client -o yaml | kubectl apply -f -

kubectl -n dynatrace create secret generic dynatrace-gcp-monitor-secret \
  --from-literal=api-url="https://<TENANT_ID>.live.dynatrace.com" \
  --from-literal=data-ingest-token="dt0c01.YOUR_TOKEN_HERE" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

#### 2. CRITICAL GOTCHA: Dynatrace Hub Extension Requirement

> [!WARNING]
> **The Dynatrace GCP Metric Forwarder is Extension-Driven.**
> If no Google Cloud extensions are activated in your Dynatrace tenant, the metric forwarder pod will crash-loop with:
> `[EXTENSIONS] Extensions fetch resulted in empty list of services`

Furthermore, **Metric Autodiscovery does NOT work in a vacuum**:
- In `helm/values/values-metrics.yaml`, you configure:
  ```yaml
  autodiscoveryResourcesYaml: |
    autodiscovery_config:
      searched_resources:
        - gce_instance
        - k8s_node
        - k8s_container
        - pubsub_topic
        - pubsub_subscription
        - cloud_run_revision
  ```
- **Why did the pod only poll 7 API metrics initially?**
  In Dynatrace's GCP monitor architecture, *autodiscovery* means:
  > *"For GCP services activated via Dynatrace Hub extensions, automatically discover and poll additional GCP metric descriptors not explicitly listed in the extension schema."*
- If the parent extension is **not activated in Dynatrace Hub**, the forwarder will reject the resource with an error:
  ```text
  [AUTODISCOVERY][ERROR] Resource gce_instance can't be added in searched_resources autodiscovery config.
  You can add this resource to autodiscovery by enabling one of the following:
  In extension: google-compute-engine Service: gce_instance Feature Set: default_metrics
  ```

#### Required Dynatrace Hub Extensions Checklist:
Open the Dynatrace Web Console $\rightarrow$ **Dynatrace Hub** and activate each of the following:

- [x] **Google Cloud APIs** (`com.dynatrace.extension.google-api`) $\rightarrow$ Ingests API request counts, latencies, quotas.
- [ ] **Google Compute Engine** (`google-compute-engine`) $\rightarrow$ Unlocks `gce_instance` metrics and autodiscovery.
- [ ] **Google Kubernetes Engine** (`google-kubernetes-engine`) $\rightarrow$ Unlocks `k8s_node`, `k8s_container` metrics and autodiscovery.
- [ ] **Google Cloud Pub/Sub** (`google-pubsub`) $\rightarrow$ Unlocks `pubsub_topic`, `pubsub_subscription` metrics.
- [ ] **Google Cloud Run** (`google-cloud-run`) $\rightarrow$ Unlocks `cloud_run_revision` metrics.

#### Q&A: Does enabling the extension in the Dynatrace Console automatically start metric collection?

**YES, absolutely.** You do NOT need to modify the Helm values file or restart the pod.

Here is the exact mechanism:
1. **The Intersection Model:**
   The forwarder pod computes the intersection of two configurations:
   $$\text{Active Services to Poll} = (\text{Services configured in Helm } \texttt{gcpServicesYaml}) \cap (\text{Extensions active in Dynatrace Hub})$$
2. **Pre-configured in Helm:**
   The base chart (`helm/dynatrace-gcp-monitor/values.yaml`) already has `default_metrics` enabled for `gce_instance`, `k8s_node`, `pubsub_topic`, `pubsub_subscription`, and `cloud_run_revision`.
3. **The Missing Key Was the Console:**
   Because those services were already enabled in Helm, the ONLY blocker was the absence of the corresponding extension schema in Dynatrace Hub.
4. **Hot-Reloading in Real Time:**
   The forwarder runs a dynamic background refresher:
   ```text
   [MAIN_LOOP] Refreshing services config
   [MAIN_LOOP] Polling finished after 8.8s
   [MAIN_LOOP] Next polling in 51.2s
   ```
   Every 60 seconds, it queries Dynatrace SaaS. The instant you activate an extension (e.g. `google-compute-engine`) in the Dynatrace console:
   - The forwarder detects it and logs: `[EXTENSIONS] Downloading and preparing extension com.dynatrace.extension.google-compute-engine`.
   - It matches it against the pre-enabled `gce_instance` in `gcpServicesYaml`.
   - It immediately issues queries to `monitoring.googleapis.com` for VM metrics across the scoping project (`dynatrace-scope-01-prod`).
   - The Autodiscovery error for `gce_instance` instantly clears.

---

### Step 5: Deploy Log & Metric Forwarders (Helm)

> [!NOTE]
> **Production CI/CD Automation:**
> While the commands below illustrate local/bootstrap execution, in enterprise production these Helm deployments are managed through a **CI/CD GitHub Actions pipeline** upon merged pull requests to `main`. The workflow uses Workload Identity Federation to obtain short-lived credentials for the GKE cluster and applies updates to `values-logs.yaml` and `values-metrics.yaml` automatically.

#### 1. Deploy Log Forwarder
```bash
helm upgrade --install dynatrace-gcp-logs ./helm/dynatrace-gcp-monitor \
  --namespace dynatrace \
  --values ./helm/values/values-logs.yaml
```

#### 2. Deploy Metric Forwarder
```bash
helm upgrade --install dynatrace-gcp-metrics ./helm/dynatrace-gcp-monitor \
  --namespace dynatrace \
  --values ./helm/values/values-metrics.yaml
```

---

## 4. Live Verification & Troubleshooting Playbook

### Checking Forwarder Health
```bash
# Check pod status (both should show 1/1 Running, 0 Restarts)
kubectl -n dynatrace get pods

# View Log Forwarder streaming status
kubectl -n dynatrace logs -l app.kubernetes.io/name=dynatrace-gcp-logs --tail=50

# View Metric Forwarder polling and ingest status
kubectl -n dynatrace logs -l app.kubernetes.io/name=dynatrace-gcp-metrics --tail=50
```

### Healthy Metric Forwarder Log Output
A healthy metric polling cycle prints:
```text
[dynatrace-scope-01-prod] Finished fetching data in 6.47s
[dynatrace-scope-01-prod] Ingest lines count: 36903 lines to push
[dynatrace-scope-01-prod] Pushing 13 batches (36903 lines, batch_size=3000, concurrency=1)
[dynatrace-scope-01-prod] Ingest response: {'linesOk': 3000, 'linesInvalid': 0, 'error': None}
...
[dynatrace-scope-01-prod] Finished uploading metric ingest lines to Dynatrace in 1.77s
[MAIN_LOOP] Next polling in 51.2s
```

### Common Gotchas & Fixes

| Issue | Root Cause | Solution |
| :--- | :--- | :--- |
| `[EXTENSIONS] Extensions fetch resulted in empty list of services` | No Google Cloud extensions activated in Dynatrace tenant. | Open Dynatrace Hub and activate `Google Cloud APIs` (`com.dynatrace.extension.google-api`). |
| `[AUTODISCOVERY][ERROR] Resource <X> can't be added in searched_resources` | Resource listed in `autodiscoveryResourcesYaml` does not have its parent extension activated. | Activate the corresponding extension in Dynatrace Hub (e.g. `google-compute-engine` for `gce_instance`). |
| `Failed to fetch [...]: PERMISSION_DENIED` on monitored project | The GCP SA `dt-metric-forwarder` needs discovery and monitoring permissions. | Ensure `dt-metric-forwarder` has `roles/monitoring.viewer` and `roles/browser` on both the scoping project and monitored projects. |
| Log forwarder receives 0 messages | Pub/Sub subscription is empty or log sink filter is too restrictive. | Verify sink filter (`severity>=INFO`) and ensure Workload Identity can pull from `dynatrace-gcp-logs-sub`. |

---

---

## 5. Phase 2: Regional ActiveGate Cluster & OneAgent Host Monitoring

While Phase 1 provides cloud platform and managed service telemetry (GCP metrics via Cloud Monitoring API and GCP logs via Pub/Sub sinks), **Phase 2 establishes in-VPC full-stack host, container, process, and code-level tracing** using Dynatrace OneAgent routed through a regional, multi-zone ActiveGate cluster.

### Architecture Overview

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ workload-app-prod (Workload Project / VPC: workload-vpc)                               │
│                                                                                        │
│  ┌──────────────────────────────────────────────┐                                      │
│  │ workload-vpc-subnet (10.10.0.0/24)           │                                      │
│  │  ┌────────────────────────────────────────┐  │                                      │
│  │  │ workload-vm-01 (10.10.0.3)             │  │                                      │
│  │  │   • Dynatrace OneAgent (Full-Stack)    │  │                                      │
│  │  │   • Network Zone: workload-prod        │  │                                      │
│  │  └──────────────────┬─────────────────────┘  │                                      │
│  └─────────────────────┼────────────────────────┘                                      │
│                        │ Internal TCP :9999 (Encrypted)                                │
│                        ▼                                                               │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ workload-activegate-subnet (10.10.2.0/24, Private Google Access enabled)         │  │
│  │                                                                                  │  │
│  │   ┌───────────────────────────────┐        ┌───────────────────────────────┐     │  │
│  │   │ dynatrace-ag-01 (10.10.2.10)   │        │ dynatrace-ag-02 (10.10.2.11)   │     │  │
│  │   │ Zone: us-central1-a           │        │ Zone: us-central1-b           │     │  │
│  │   │ Network Zone: workload-prod   │        │ Network Zone: workload-prod   │     │  │
│  │   │ Shielded VM (Secure Boot)     │        │ Shielded VM (Secure Boot)     │     │  │
│  │   └───────────────┬───────────────┘        └───────────────┬───────────────┘     │  │
│  └───────────────────┼────────────────────────────────────────┼─────────────────────┘  │
│                      │                                        │                        │
│                      │ Outbound HTTPS :443 (via Cloud NAT)    │                        │
│                      └───────────────────┬────────────────────┘                        │
└──────────────────────────────────────────┼─────────────────────────────────────────────┘
                                           ▼
                      ┌────────────────────────────────────────┐
                      │ Dynatrace SaaS                         │
                      │ https://<tenant>.live.dynatrace.com    │
                      └────────────────────────────────────────┘
```

### Critical Architecture Design Decisions

1. **Why No Load Balancer (NLB/ILB) is Needed:**
   - **Dynatrace Native Client-Side Load Balancing & Failover:** Dynatrace OneAgent natively queries the Dynatrace cluster/ActiveGate cluster for active endpoints and automatically load balances requests across all healthy ActiveGates in its configured **Network Zone** (`workload-prod`).
   - If an ActiveGate in zone `a` goes down, OneAgent immediately routes all traffic to zone `b` without DNS caching delays or load balancer health-check lags.
   - Introducing an external or internal load balancer (L4/L7) obscures client IP addresses, breaks bidirectional ActiveGate connection affinity, adds unnecessary GCP forwarding-rule costs, and introduces an extra failure domain.

2. **Why Static Multi-Zone VMs Instead of Autoscaling Managed Instance Groups (MIGs):**
   - ActiveGates maintain persistent connection state and register as unique endpoint instances in Dynatrace.
   - Autoscaling MIGs that spin down ActiveGates during off-peak hours generate persistent false-positive "ActiveGate Offline" alerts in the Dynatrace monitoring console.
   - A deterministic, 2-VM static deployment across Availability Zones `a` and `b` (`us-central1-a` and `us-central1-b`) ensures 99.99% regional SLA, zero alerting noise, and predictable capacity.

3. **Subnet & Organization Policy Constraints:**
   - **Proxy-Only Subnet Isolation:** In `workload-vpc`, subnet `10.10.1.0/24` has `purpose = REGIONAL_MANAGED_PROXY` for Envoy L7 ILBs. GCP disallows compute VM instances from attaching to proxy-only subnets. Therefore, ActiveGates reside in their own dedicated subnet: `workload-activegate-subnet` (`10.10.2.0/24`).
   - **GCP Shielded VM Organization Policy:** The GCP organization enforces `constraints/compute.requireShieldedVm`. The ActiveGate Terraform module explicitly enables:
     ```hcl
     shielded_instance_config {
       enable_secure_boot          = true
       enable_vtpm                 = true
       enable_integrity_monitoring = true
     }
     ```

### Reusable & Redeployable ActiveGate Module Architecture

The ActiveGate infrastructure is packaged as an enterprise reusable module at `terraform/modules/activegate/`. It is designed to be **redeployable across any subnet, existing subnet, VPC, or GCP project** with zero code duplication:

#### Key Module Parameters for Redeployment:
* `create_subnet` (`bool`, default `true`): Set to `false` to deploy ActiveGates directly into an **existing application subnet** without attempting to create a new one.
* `subnet_name` (`string`): Name of the subnet (either created or looked up via data source).
* `instance_count` (`number`, default `null`): Easily scale the cluster to deploy a "bunch" of ActiveGates (e.g. 2, 4, 8 nodes). Instances automatically round-robin and alternate across the provided availability zones.
* `instance_prefix` (`string`, default `"dynatrace-ag"`): Unique prefix for VM names, enabling multiple independent ActiveGate clusters in the same project/VPC (e.g. `workload-ag`, `payment-ag`, `dev-ag`).
* `assign_static_ips` (`bool`, default `true`): Deterministically allocates static IPs from `subnet_cidr`. Set to `false` to let GCP assign DHCP internal IPs automatically.
* `create_firewall_rules` (`bool`, default `true`): Can be toggled off if organization-level firewall policies or Shared VPC firewall rules already govern port 9999.
* `firewall_prefix` (`string`, default `""`): Custom prefix for firewall rules to avoid collision when multiple ActiveGate modules share the same VPC.

#### Example 1: Creating a New Dedicated Subnet (Default)
```hcl
module "activegate_dedicated" {
  source                = "../../modules/activegate"
  project_id            = "workload-app-prod"
  region                = "us-central1"
  zones                 = ["us-central1-a", "us-central1-b"]
  vpc_name              = "workload-vpc"
  create_subnet         = true
  subnet_name           = "workload-activegate-subnet"
  subnet_cidr           = "10.10.2.0/24"
  source_workload_cidrs = ["10.10.0.0/24", "10.10.2.0/24"]
  dynatrace_url         = var.dynatrace_url
  dynatrace_api_token   = var.dynatrace_api_token
  network_zone          = "workload-prod"
}
```

#### Example 2: Redeploying a Cluster of 4 ActiveGates into an Existing Subnet
```hcl
module "activegate_existing_subnet" {
  source                = "../../modules/activegate"
  project_id            = "workload-app-prod"
  region                = "us-central1"
  zones                 = ["us-central1-a", "us-central1-b"]
  vpc_name              = "workload-vpc"
  create_subnet         = false                    # Target existing subnet
  subnet_name           = "workload-vpc-subnet"    # Existing subnet
  instance_count        = 4                        # Deploy 4 instances
  instance_prefix       = "app-ag"                 # app-ag-01, app-ag-02...
  assign_static_ips     = false                    # Dynamic DHCP allocation
  create_firewall_rules = false                    # Existing firewalls in place
  dynatrace_url         = var.dynatrace_url
  dynatrace_api_token   = var.dynatrace_api_token
  network_zone          = "workload-prod"
}
```

### OneAgent Host Installation

To deploy OneAgent on workload instances (e.g. `workload-vm-01`):
```bash
# 1. Download installer using API token (with InstallerDownload scope)
curl -s -S -L -o /tmp/Dynatrace-OneAgent-Linux.sh \
  -H "Authorization: Api-Token <DYNATRACE_API_TOKEN>" \
  "https://<tenant>.live.dynatrace.com/api/v1/deployment/installer/agent/unix/default/latest?arch=x86&flavor=default"

# 2. Run installer configuring full-stack mode and the regional network zone
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
  --set-monitoring-mode=fullstack \
  --set-network-zone=workload-prod

# 3. Clean up installer script
rm -f /tmp/Dynatrace-OneAgent-Linux.sh
```

---

## 6. End-to-End Verification Playbook

### Verifying Phase 1 (GKE Forwarders)
```bash
# Connect to GKE cluster
gcloud container clusters get-credentials dynatrace-forwarder-gke \
  --zone=us-central1-a \
  --project=dynatrace-platform-prod

# Verify forwarder pods are running
kubectl -n dynatrace get pods

# Verify Metric Forwarder cycles and ingest response
kubectl -n dynatrace logs -l app=dynatrace-gcp-metrics --tail=50

# Verify Log Forwarder streaming status
kubectl -n dynatrace logs -l app=dynatrace-gcp-logs --tail=50
```

### Verifying Phase 2 (ActiveGates & OneAgent)
```bash
# 1. Check ActiveGate registration via Dynatrace API
curl -s -H "Authorization: Api-Token <DYNATRACE_API_TOKEN>" \
  "https://<tenant>.live.dynatrace.com/api/v2/activeGates" \
  | jq '.activeGates[] | {hostname: .hostname, ip: .networkAddresses, zone: .networkZone, status: .autoUpdateStatus}'

# Expected output:
# - dynatrace-ag-01 (10.10.2.10, Zone: workload-prod, Status: UP2DATE)
# - dynatrace-ag-02 (10.10.2.11, Zone: workload-prod, Status: UP2DATE)

# 2. Verify OneAgent host entity in Dynatrace
curl -s -H "Authorization: Api-Token <DYNATRACE_API_TOKEN>" \
  "https://<tenant>.live.dynatrace.com/api/v2/entities?entitySelector=type(%22HOST%22)" | jq .

# 3. Verify OneAgent configuration and endpoint routing on workload VM
gcloud compute ssh workload-vm-01 --zone=us-central1-a --project=workload-app-prod --tunnel-through-iap \
  --command="sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --get-network-zone && sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --get-server"
```

---

## 7. Enterprise Scale, Governance & Automated CI/CD Lifecycle

When operating across an enterprise GCP footprint with hundreds or thousands of projects, multi-team Shared VPCs, and automated landing zone pipelines, observability cannot depend on manual project registration or ad-hoc agent installations.

This section details the architectural blueprints for three core enterprise scale and governance capabilities:
1. **The 375-Project Metric Scope Sharding Architecture** using GCP Secure Tags, Custom Org Policies, and CI/CD Project Factory automation.
2. **Automated On-Demand ActiveGate Cluster Deployment** driven by Network Landing Zone automation and policy constraints.
3. **Golden Image Factory Pipeline** for baking Dynatrace OneAgent into shared base images with dynamic runtime Network Zone binding.

---

### 7.1 The 375-Project Metric Scope Sharding Architecture

#### The Architectural Constraint
Google Cloud Monitoring imposes a hard, non-negotiable quota: **a single Metrics Scoping Project can monitor a maximum of 375 projects** (`1:375` ratio). In large organizations with 1,000+ projects, attempts to add the 376th project fail with:
`RESOURCE_EXHAUSTED: Scoping project has reached maximum monitored projects limit (375)`.

#### The Architectural Solution: Cryptographic Secure Tags & Sharded Pools
Rather than manually tracking project counts in spreadsheets or relying on editable resource labels, the enterprise pattern utilizes **GCP Resource Manager Secure Tags**:

```text
Organization: enterprise-org.example.com
│
├── [Tag Key] observability.scoping_project (tagKeys/281474976710656)
│   ├── [Tag Value] dynatrace-scope-01 (tagValues/281474976710657) -> Projects 1 to 350
│   ├── [Tag Value] dynatrace-scope-02 (tagValues/281474976710658) -> Projects 351 to 700
│   └── [Tag Value] dynatrace-scope-03 (tagValues/281474976710659) -> Projects 701 to 1050
│
├── [Folder] Observability
│   └── [Folder] Scoping Projects
│       ├── [Project] dynatrace-scope-01-prod (Scope Pool 1: 350 projects)
│       ├── [Project] dynatrace-scope-02-prod (Scope Pool 2: 350 projects)
│       └── [Project] dynatrace-scope-03-prod (Scope Pool 3: 350 projects)
│
└── [GKE Private Cluster: dynatrace-forwarder-gke]
    ├── [Pod] dynatrace-gcp-metrics-scope-01 (Polls dynatrace-scope-01-prod)
    ├── [Pod] dynatrace-gcp-metrics-scope-02 (Polls dynatrace-scope-02-prod)
    └── [Pod] dynatrace-gcp-metrics-scope-03 (Polls dynatrace-scope-03-prod)
```

#### Why Secure Tags Instead of Standard Labels?
* **Tamper-Proof Governance**: Standard GCP resource labels (`labels = { ... }`) can be edited or deleted by project owners and developers with `roles/resourcemanager.projectModifier`.
* **Centralized IAM Authority**: **Secure Tags** are organization-level objects governed strictly by `roles/resourcemanager.tagAdmin` and `roles/resourcemanager.tagUser`. Workload project teams cannot modify, delete, or reassign tags.
* **Hierarchical Enforcement**: Tags can be evaluated by GCP Organization Policy constraints at project creation time.

#### 1. Defining Secure Tags in Terraform
```hcl
# Organization-level Tag Key for Observability Scoping
resource "google_tags_tag_key" "scoping_project" {
  parent      = "organizations/${var.org_id}"
  short_name  = "scoping_project"
  description = "Centralized Observability Scoping Project Pool Tag"
}

# Tag Values representing individual 375-project shards
resource "google_tags_tag_value" "scope_shards" {
  for_each    = toset(["dynatrace-scope-01", "dynatrace-scope-02", "dynatrace-scope-03"])
  parent      = google_tags_tag_key.scoping_project.id
  short_name  = each.key
  description = "Assigned to metrics scope shard ${each.key}"
}
```

#### 2. Custom Organization Policy Guardrail
To ensure zero projects bypass monitoring, deploy a GCP Custom Organization Policy constraint that rejects project creation unless the tag key `scoping_project` is attached:

```yaml
name: organizations/123456789012/customConstraints/custom.requireObservabilityScopingTag
resourceTypes:
  - cloudresourcemanager.googleapis.com/Project
actionType: ALLOW
condition: "resource.tags.exists(k, k.startsWith('organizations/123456789012/tagKeys/')) && resource.tags.exists(k, resource.tags[k] in ['dynatrace-scope-01', 'dynatrace-scope-02', 'dynatrace-scope-03'])"
methodTypes:
  - CREATE
displayName: "Require Observability Scoping Project Tag on All Projects"
description: "Prevents creation of unmonitored projects without an assigned Dynatrace scoping shard."
```

#### 3. Project Factory CI/CD Automation Flow
In the Landing Zone's **Project Factory** pipeline (GitHub Actions / Cloud Build):
1. **Capacity Evaluation**:
   Before stamping out a new workload project, the pipeline queries Cloud Monitoring for the project count in the active scoping project:
   ```bash
   ACTIVE_COUNT=$(gcloud monitoring metrics-scopes list \
     --project="dynatrace-scope-01-prod" \
     --format="value(monitoredProjects)" | tr ';' '\n' | wc -l)
   ```
2. **Automated Shard Transition**:
   * If `ACTIVE_COUNT < 350`: Assign to `dynatrace-scope-01`.
   * If `ACTIVE_COUNT >= 350`: Pipeline automatically provisions `dynatrace-scope-02-prod` in the `Scoping Projects` folder (`folders/222222222222`), creates the tag value, and routes all subsequent project requests to shard 02.
   * *Safety Buffer*: Setting the threshold to 350 provides a 25-project buffer preventing pipeline lockups during concurrent burst deployments.
3. **Automated Forwarder Horizontal Scaling**:
   When a new scoping project shard is provisioned, the pipeline automatically deploys a corresponding Dynatrace Metric Forwarder release in the GKE cluster:
   ```bash
   helm upgrade --install dynatrace-gcp-metrics-scope-02 ./helm/dynatrace-gcp-monitor \
     --namespace dynatrace \
     --values ./helm/values/values-metrics.yaml \
     --set gcpProjectId="dynatrace-scope-02-prod"
   ```

---

### 7.2 Automated On-Demand ActiveGate Cluster Deployment in Workload VPCs

#### The Requirement
In an enterprise Shared VPC or multi-VPC architecture, every VPC hosting observable compute workloads (GCE instances, GKE nodes, private GCE MIGs) must have an in-VPC ActiveGate cluster to provide:
1. Private, in-VPC telemetry routing without public egress.
2. Cross-zone high availability (multi-zone failover).
3. Low-latency, localized network zone connectivity.

#### Automated Network Factory Architecture
ActiveGate clusters are not deployed manually. They are an intrinsic component of the **Stage 3 Network Factory**:

```text
Landing Zone CI/CD Pipeline (Network Factory)
│
├── Step 1: Create Workload VPC (e.g., workload-vpc or finance-vpc)
│
├── Step 2: Policy Compliance Check
│   └── Enforces: Subnet /24 allocated for ActiveGate + PGA enabled
│
├── Step 3: Invoke Reusable ActiveGate Module
│   └── terraform/modules/activegate/
│       ├── create_subnet         = true
│       ├── subnet_cidr           = "10.10.2.0/24"
│       ├── vpc_name              = "workload-vpc"
│       ├── network_zone          = "workload-prod"
│       └── zones                 = ["us-central1-a", "us-central1-b"]
│
└── Step 4: ActiveGates Auto-Register in Dynatrace SaaS
    └── Network Zone "workload-prod" is dynamically ready for OneAgent traffic
```

#### Event-Driven Triggers & Policy Guardrails
* **Custom Org Policy**: Enforces that any subnet labeled `tier=workload` must reside in a VPC with an associated `dynatrace-activegate` subnet tag.
* **Network Zone Naming Standard**: Deterministically mapped to VPC identity:
  `network_zone = "${var.vpc_name}-${var.environment}"` (e.g. `workload-prod`, `payments-prod`, `analytics-stage`).
* **Zero Egress Drift**: All ActiveGate VMs are stamped out with zero external public IPs, routing to Dynatrace SaaS strictly through the VPC's Cloud NAT gateway.

---

### 7.3 Golden Image Factory Pipeline (OneAgent Baking & Network Zones)

#### The Problem with Boot-Time OneAgent Downloads
Downloading the 276MB OneAgent installer at VM startup time creates critical enterprise operational hazards:
1. **Startup Latency**: Adds 60–120 seconds of boot overhead to every auto-scaling VM or compute instance.
2. **External Dependency Risk**: If outbound NAT or the Dynatrace API rate-limits downloads during a traffic surge, newly scaled VMs fail to initialize.
3. **Secret Sprawl**: Requires every VM startup script to possess a Dynatrace API token.

#### The Enterprise Pattern: Pre-Baking OneAgent in Centralized Image Factory
In an enterprise Image Factory (using HashiCorp Packer, Cloud Build, or GitHub Actions running in a central `shared-images-prod` project), Dynatrace OneAgent is pre-installed in **staged golden image template mode**:

```text
Shared Image Factory (shared-images-prod)
│
├── Packer / Cloud Build Weekly Pipeline
│   ├── Base OS (Ubuntu 22.04 LTS / Debian 12 / RHEL 9)
│   ├── Security Hardening & CIS Benchmarks
│   └── Bake Dynatrace OneAgent (Staged Mode):
│       ├── Install OneAgent binaries
│       ├── Disable auto-start on template
│       └── Wipe instance-specific machine IDs & runtime tokens
│
└── Publish to Shared Image Family (e.g., projects/shared-images-prod/images/family/gold-ubuntu-2204)
```

#### 1. Packer / Image Factory Build Script (`install_oneagent_golden.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "==> Downloading Dynatrace OneAgent installer..."
curl -sS -L -o /tmp/Dynatrace-OneAgent-Linux.sh \
  -H "Authorization: Api-Token ${DYNATRACE_INSTALLER_TOKEN}" \
  "${DYNATRACE_TENANT_URL}/api/v1/deployment/installer/agent/unix/default/latest?arch=x86&flavor=default"

echo "==> Installing OneAgent in non-configured staging mode..."
sudo /bin/sh /tmp/Dynatrace-OneAgent-Linux.sh \
  --set-monitoring-mode=fullstack \
  --set-network-zone=DEFAULT \
  --set-host-group=gcp-workloads \
  PRESERVE_INSTALLER=0

echo "==> Stopping OneAgent service before disk capture..."
sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --shutdown
sudo systemctl stop oneagent

echo "==> Clearing instance-specific IDs to prevent duplicate host reporting..."
sudo rm -f /var/lib/dynatrace/oneagent/agent/config/runtime.conf
sudo rm -f /var/lib/dynatrace/oneagent/agent/config/original_endpoints.conf
sudo rm -rf /var/log/dynatrace/oneagent/*

echo "==> Golden image preparation complete."
```

#### 2. Zero-Touch Runtime Network Zone Binding
When any workload team launches a VM from the golden image, they provide a standard GCE instance metadata attribute: `network-zone = <ZONE_NAME>` (e.g. `workload-prod`).

A lightweight first-boot Cloud-Init or systemd unit executes:
```bash
#!/usr/bin/env bash
# /etc/systemd/system/dynatrace-zone-init.service (One-shot boot hook)
set -euo pipefail

# Read network zone from GCP Instance Metadata
NETWORK_ZONE=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/network-zone" || echo "workload-prod")

echo "==> Configuring OneAgent network zone to: ${NETWORK_ZONE}"
sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --set-network-zone="${NETWORK_ZONE}"
sudo /opt/dynatrace/oneagent/agent/tools/oneagentctl --restart-service

echo "==> OneAgent operational and connected to local ActiveGate cluster."
```

#### Summary of Image Factory Benefits
* **Boot Time Acceleration**: OneAgent is already installed on the filesystem; initialization takes **< 1.5 seconds**.
* **Zero Secret Sprawl**: Workload VMs never handle or store Dynatrace API tokens.
* **Deterministic Failover**: The agent immediately reads `network-zone = workload-prod` and targets the internal ActiveGate IPs (`10.10.2.10:9999` and `10.10.2.11:9999`) without external internet access.

---

### 7.4 Architectural Trade-Off Analysis: Pre-Baking vs. Post-Deployment Configuration

A foundational engineering decision in Google Cloud Landing Zones is choosing between **baking agents into the base image (Immutable Infrastructure)** versus **installing and configuring them post-deployment (Dynamic Bootstrap)**.

#### Comparison Matrix

| Evaluation Dimension | Option A: Pre-Baked in Golden Image | Option B: Post-Deployment Bootstrap (Startup Script / Ansible) |
| :--- | :--- | :--- |
| **VM Startup Latency** | **< 1.5 seconds** (Agent binaries already unpacked in `/opt/dynatrace/`). | **60 – 180 seconds** (Downloads 276MB bundle, verifies dependencies, unpacks, compiles kernel hooks). |
| **MIG Autoscaling Viability** | **Excellent**: VMs scale out almost instantaneously during load spikes. | **Poor / High Risk**: Scale-out delays mean incoming traffic hits struggling nodes before new instances finish agent install. |
| **Secret & Token Security** | **Zero Token Sprawl**: API token is only used once in the isolated Image Factory CI/CD runner. Workload instances never see or store the token. | **High Exposure**: Startup scripts must retrieve the Dynatrace API token (via Secret Manager, metadata, or env vars), exposing credentials across projects. |
| **Network Egress & Quotas** | **Zero Outbound Bandwidth at Boot**: Telemetry routes straight to local ActiveGate over internal VPC port 9999. | **Heavy Outbound Bandwidth**: 100 autoscaling VMs simultaneously download 27.6 GB over Cloud NAT or internet gateways, risking rate-limits. |
| **Air-Gapped / Private VPCs** | **Fully Supported**: Works in completely isolated subnets without Cloud NAT or public internet access. | **Requires NAT / Proxies**: Fails if the subnet has no outbound route to Dynatrace SaaS during boot. |
| **Version Drift & Upgrades** | **Coupled to Image Release Cycle**: Agent updates occur when new base images are rolled out across the fleet (or via ActiveGate AutoUpdater). | **Always Latest**: Every new VM automatically pulls the newest OneAgent version from Dynatrace SaaS. |
| **Pipeline Complexity** | **Higher Initial Overhead**: Requires maintaining Packer / Cloud Build image pipelines and shared image registries. | **Lower Initial Overhead**: Just a shell snippet inside Terraform `metadata_startup_script` or Cloud-Init. |
| **Failure Blast Radius** | **Isolated to Build Time**: If OneAgent installer fails, the image build fails in CI/CD without impacting running production workloads. | **Runtime Production Impact**: If Dynatrace SaaS has an API hiccup or network packet drops, production VM startup scripts crash. |

#### Detailed Pros and Cons

##### Option A: Pre-Baked Golden Image (Recommended Enterprise Pattern)
* **Pros**:
  1. *Sub-Second Boot Time*: Ideal for Managed Instance Groups (MIGs), GKE node auto-provisioning, and bursty compute workloads.
  2. *Zero Secret Sprawl*: Centralizes token exposure strictly to the Image Factory CI/CD pipeline (`shared-images-prod`).
  3. *Immunity to Network Outages*: Workload VMs never fail to initialize due to transient external network or API issues.
  4. *Security Compliance*: Pre-baked images undergo static vulnerability analysis (CVE scanning) before promotion to production image families.
* **Cons**:
  1. *Version Lag*: Running VMs remain on the baked version until instances are recycled or ActiveGate Auto-Update is enabled.
  2. *Image Maintenance Burden*: Requires an automated weekly or bi-weekly Image Factory pipeline to refresh base OS patches.

##### Option B: Post-Deployment Bootstrap (Startup Script / Ansible / Puppet)
* **Pros**:
  1. *Simplicity*: Fast to prototype and test in development environments without building image pipelines.
  2. *Zero Image Pipeline Dependencies*: Works with standard public Google-provided images (`debian-cloud/debian-12`, `ubuntu-os-cloud/ubuntu-2204-lts`).
  3. *Always Current*: Instances always boot with the latest OneAgent version.
* **Cons**:
  1. *Severe Boot Penalty*: 276MB download and installation adds 1–3 minutes per VM.
  2. *External Dependency at Launch*: If Cloud NAT exhausts ports, or Dynatrace SaaS rate-limits concurrent downloads during a storm, VM provisioning fails.
  3. *Credential Proliferation*: Requires giving every workload project service account `roles/secretmanager.secretAccessor` to fetch the installer token.

---

#### The Enterprise Hybrid Verdict: Golden Image Base + Dynamic Runtime Network Zone Hook

The optimal enterprise architecture combines the best of both worlds:
1. **Pre-bake the OneAgent binaries into the Golden Image** in staging template mode (eliminating download latency, secret sprawl, and external network failure modes).
2. **Execute a lightweight 3-line first-boot hook** (`dynatrace-zone-init.sh`) that dynamically reads the GCP instance metadata attribute `network-zone` and binds the agent to the local VPC's regional ActiveGate cluster (`oneagentctl --set-network-zone="${ZONE}"`).
3. **Enable Dynatrace ActiveGate Auto-Updater**: Once connected to the local ActiveGate cluster, OneAgent can automatically receive non-disruptive minor updates pushed locally through the ActiveGate without requiring a full VM redeployment or internet access.



