# Dynatrace + Google Cloud Full-Stack Observability Lab

## Purpose

Build a working reference implementation of the Google Cloud → Dynatrace observability architecture.

The lab demonstrates the major Dynatrace integration patterns used to collect metrics, logs, traces, and application telemetry from Google Cloud. The goal is not to reproduce the full production environment, but to prove each major integration path end-to-end in a small, controlled GCP environment.

---

# Integration Paths

The lab will demonstrate four major observability paths:

1. **GKE integration**
   - Metrics Forwarder
   - Log Forwarder
   - Google Cloud Scoping Projects
   - Google Cloud Monitored Projects
   - Pub/Sub log ingestion
2. **GCE / VM integration**
   - OneAgent
   - ActiveGate
   - Infrastructure monitoring
   - Full-stack application monitoring
3. **Google Cloud PaaS integration**
   - ActiveGate
   - Dynatrace Extensions
   - Google Cloud APIs / service-level telemetry
4. **Application / Agent observability**
   - Application traces
   - Application metrics
   - Application logs
   - ADK agent traces
   - Model calls
   - Tool calls

VMware / GCVE integrations are out of scope for the initial implementation.

---

# Target Architecture

```text
                         ┌───────────────────┐
                         │     Dynatrace     │
                         │      Tenant       │
                         └─────────┬─────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
        GKE Integration       ActiveGate           Application
              │                    │               Telemetry
      ┌───────┴────────┐      ┌────┴─────┐              │
      │                │      │          │              │
 Metric Forwarder   Log FWDR  OneAgent  Extensions     ADK
      │                │      │          │              │
 GCP Monitoring      Pub/Sub  GCE      GCP PaaS    Traces/Metrics
      │                │      │        Services        /Logs
 Scoping Project   Log Sinks  VM
      │                │
      ▼                ▼
 Monitored         Folder-level
 Projects          GCP Logging
```

## Enterprise GCP Resource Hierarchy

```text
Organization: enterprise-org.example.com (123456789012)
│
├── [Folder] Observability
│   │
│   ├── [Project] dynatrace-control-prod  <--- CONTROL / DEVOPS PLANE
│   │   ├── GCS State Bucket: gs://dynatrace-control-tfstate
│   │   └── Deployer / CI Service Accounts
│   │
│   ├── [Project] dynatrace-platform-prod <--- INFRASTRUCTURE PLANE
│   │   ├── Dedicated VPC (for GKE Metric & Log Forwarders)
│   │   ├── Cloud Pub/Sub (Topic: dynatrace-gcp-logs, Sub: dynatrace-gcp-logs-sub)
│   │   └── Private GKE Cluster (Workload Identity)
│   │
│   ├── [Folder] Scoping Projects
│   │   ├── [Project] dynatrace-scoping-project-01 (1:375 cap)
│   │   └── [Project] dynatrace-scoping-project-02
│   │
│   └── [Folder] ActiveGate Projects
│       ├── [Project] dynatrace-ag-svc-host-a (Service Project -> Attached to host-vpc-a)
│       │   └── ActiveGate Multi-Zone Cluster (:9999)
│       └── [Project] dynatrace-ag-svc-host-b (Service Project -> Attached to host-vpc-b)
│           └── ActiveGate Multi-Zone Cluster (:9999)
│
├── [Folder] Networking
│   ├── [Project] host-vpc-project-a (Shared VPC Host A)
│   │   └── Shared VPC A (hosts subnets including dynatrace-activegate-subnet-a)
│   └── [Project] host-vpc-project-b (Shared VPC Host B)
│       └── Shared VPC B (hosts subnets including dynatrace-activegate-subnet-b)
│
└── [Folder] Teams / Workloads
    ├── [Project] workload-app-prod (Service Project -> Attached to host-vpc-a)
    │   ├── GCE VMs (OneAgent pointing to local ActiveGate Network Zone in Shared VPC A)
    │   ├── Cloud Run v2 Services (OTel Instrumented)
    │   └── PaaS resources
    └── [Project] observed-project-b (Service Project -> Attached to host-vpc-b)
        └── GCE VMs & PaaS resources
```

> **Shared VPC & ActiveGate Invariant (1:1 Ratio)**: In Google Cloud, a Service Project can only attach to **one** Shared VPC Host Project. Therefore, each Shared VPC Host Project in the enterprise is paired 1:1 with a dedicated Dynatrace ActiveGate Service Project under the `ActiveGate Projects` folder. That Service Project deploys regional ActiveGate Managed Instance Groups (MIGs) fronted by an Internal Passthrough NLB whose interfaces sit directly inside the Host Project's `dynatrace-activegate-subnet`. Workload VMs in any Service Project attached to that Shared VPC communicate directly to their local ActiveGate NLB VIP over private RFC 1918 networking.

---

# 1. GKE Dynatrace Integration

Dynatrace's Google Cloud integration will be deployed into GKE using the Dynatrace Helm chart.

The cluster will run independently scalable:

- Metric Forwarder pods
- Log Forwarder pods

These components demonstrate two different telemetry paths.

## 1.1 Metrics Forwarder

The Metrics Forwarder retrieves Google Cloud metrics through the Google Cloud Monitoring APIs.

### Architecture

```text
Observed Project A ─┐
                    │
Observed Project B ─┼──► Scoping Project
                    │          │
Observed Project C ─┘          │
                               ▼
                       Metric Forwarder
                               │
                               ▼
                           Dynatrace
```

A dedicated Google Cloud **Scoping Project** will be created. The actual workloads exist inside **Monitored Projects**. The monitored projects are attached to the monitoring scope of the Scoping Project with a LIMIT of 375 monitored projects PER 1-scoping project.

The Dynatrace Metrics Forwarder therefore queries the Scoping Project rather than requiring an independent Dynatrace deployment for every Google Cloud project.

### Lab Objectives

- [ ] Create Scoping Project
- [ ] Create at least two Monitored Projects
- [ ] Attach Monitored Projects to the Scoping Project
- [ ] Create Dynatrace integration Service Account
- [ ] Configure required IAM permissions
- [ ] Deploy Metric Forwarder
- [ ] Configure projects/services through Helm `values.yaml`
- [ ] Confirm metrics from both projects appear in Dynatrace

### Telemetry to Validate

- [ ] GCE metrics
- [ ] GKE metrics
- [ ] Pub/Sub metrics
- [ ] Selected PaaS metrics

---

# 2. Google Cloud Log Integration

Google Cloud logs follow a separate ingestion path. Rather than querying individual projects, logs are aggregated using Google Cloud Logging sinks.

### Architecture

```text
                  GCP Folder
                      │
               Aggregate Log Sink
                      │
                      ▼
                Pub/Sub Topic
                      │
                      ▼
               Log Forwarder
                  (GKE)
                      │
                      ▼
                  Dynatrace
```

Folder-level aggregate Log Sinks collect logs from resources beneath the folder. Log Sink filters determine which logs are exported. The logs are published to Pub/Sub and consumed by the Dynatrace Log Forwarder running in GKE.

### Lab Objectives

- [ ] Create Pub/Sub topic
- [ ] Create Pub/Sub subscription
- [ ] Configure folder/project Log Sink
- [ ] Configure log filters
- [ ] Configure Pub/Sub IAM
- [ ] Deploy Log Forwarder
- [ ] Verify logs reach Dynatrace

### Important Test

Determine whether the Log Forwarder can ingest logs for projects that are **not** configured as Monitored Projects for the Metrics Forwarder.

This validates whether metrics scoping and log ingestion can be managed independently.

---

# 3. OneAgent VM Integration

A GCE VM will demonstrate the OneAgent integration.

### Architecture

```text
Application
     │
     ▼
OneAgent
     │
     ▼
ActiveGate
     │
     ▼
Dynatrace
```

OneAgent is installed directly into the VM operating system.

The production architecture uses Puppet for automated OneAgent installation/configuration. The lab may initially install OneAgent manually before automating the deployment.

### Infrastructure Mode

Validate:

- [ ] Host metrics
- [ ] CPU
- [ ] Memory
- [ ] Disk
- [ ] Network
- [ ] Processes

### Full-Stack Mode

Validate deeper application visibility:

- [ ] Processes
- [ ] Services
- [ ] Application requests
- [ ] Dependencies
- [ ] Traces

---

# 4. ActiveGate

ActiveGate provides a controlled Dynatrace presence inside the GCP network.

It serves two separate purposes in this architecture:

1. Proxy telemetry from OneAgents
2. Execute Dynatrace Extensions against technologies and managed services

### Architecture

```text
                ┌── OneAgent
                │
GCP VPC ──► ActiveGate ──► Dynatrace
                │
                └── Dynatrace Extensions
                         │
                         ▼
                    GCP Services
```

### Lab Deployment

Deploy ActiveGate on GCE.

Validate:

- [ ] ActiveGate → Dynatrace connectivity
- [ ] OneAgent → ActiveGate connectivity
- [ ] ActiveGate high-level health
- [ ] Telemetry forwarding

---

# 5. ActiveGate Load Balancing

The production design places ActiveGate nodes behind an internal Passthrough Network Load Balancer.

```text
OneAgents
    │
    ▼
Internal Passthrough NLB
    │
    ├────► ActiveGate 1
    │
    └────► ActiveGate 2
                 │
                 ▼
             Dynatrace
```

The lab should initially validate a single ActiveGate. A second ActiveGate and NLB can then be introduced to demonstrate the production HA pattern.

### Lab Objectives

- [ ] Validate single ActiveGate first
- [ ] Deploy second ActiveGate
- [ ] Configure internal Passthrough NLB
- [ ] Validate OneAgent connectivity through the NLB
- [ ] Validate telemetry continuity during an ActiveGate failure

---

# 6. Dynatrace Extensions for Google Cloud PaaS

Some Google Cloud managed services cannot run OneAgent directly. For these services, ActiveGate executes Dynatrace Extensions which query the relevant service/API.

### Architecture

```text
Google Cloud PaaS
       │
       │ API
       ▼
Dynatrace Extension
       │
       ▼
ActiveGate
       │
       ▼
Dynatrace
```

### Candidate Lab Service

Deploy at least one representative managed service.

Candidate:

- AlloyDB

The ActiveGate Service Account will receive the permissions required by the extension to query the target resource.

### Validate

- [ ] API connectivity
- [ ] Authentication through ActiveGate Service Account
- [ ] Infrastructure/service metrics
- [ ] Database/service-specific telemetry
- [ ] Dynatrace entity creation
- [ ] Dashboards
- [ ] Alerts

### Duplication Test

Determine whether telemetry collected through the Dynatrace Extension duplicates telemetry already collected through:

- Google Cloud Monitoring / Metric Forwarder
- Cloud Logging / Log Forwarder

Document which integration should own each telemetry source.

---

# 7. Full-Stack Application

Deploy a small application into the environment.

The application exists to connect the infrastructure telemetry with application-level observability.

```text
User
 │
 ▼
Application
 │
 ├── GCP PaaS Service
 ├── Pub/Sub
 └── ADK Agent
```

Generate:

- [ ] HTTP traffic
- [ ] Application logs
- [ ] Application metrics
- [ ] Distributed traces
- [ ] Controlled errors
- [ ] Controlled latency

---

# 8. ADK / Agent Observability

The final stage extends the demo from traditional application observability into agent observability.

```text
User Request
     │
     ▼
Application
     │
     ▼
ADK Agent
     │
     ├── Model Call
     ├── Tool Call
     └── Downstream Service
```

## Traces

Capture where supported:

- [ ] Request
- [ ] Agent invocation
- [ ] Model invocation
- [ ] Tool invocation
- [ ] Downstream dependency

## Metrics

Candidate metrics:

- [ ] Agent latency
- [ ] Model latency
- [ ] Tool latency
- [ ] Token usage
- [ ] Invocation count
- [ ] Error count/rate

## Logs

Capture structured logs for:

- [ ] Application events
- [ ] Agent events
- [ ] Tool execution
- [ ] Failures
- [ ] Trace/correlation IDs

---

# 9. End-to-End Demo

The final demo should prove that Dynatrace can follow a problem across the complete stack.

```text
Application latency increases
            │
            ▼
        Dynatrace
            │
            ▼
       Application
            │
            ▼
    Distributed Trace
            │
            ▼
        ADK Agent
            │
            ▼
        Tool Call
            │
            ▼
     PaaS Dependency
            │
            ▼
       GCP Metrics
            │
            ▼
     Infrastructure
```

The operator should be able to correlate:

```text
METRICS + LOGS + TRACES
```

across:

```text
GCP → GKE → APPLICATION → AGENT
```

---

# 10. Failure Scenarios

The final demo should include intentional failure and degradation scenarios rather than only healthy dashboards.

## Scenario 1 — Healthy Request

Demonstrate a successful request across the complete telemetry chain.

## Scenario 2 — Infrastructure Pressure

Introduce resource pressure and observe:

```text
Infrastructure Metrics
        ↓
Workload Degradation
        ↓
Application Latency
```

## Scenario 3 — Slow Agent Tool

Introduce artificial latency into an ADK tool.

```text
User Request
    ↓
Agent
    ↓
Tool Call       ← latency identified here
    ↓
Downstream API
```

## Scenario 4 — Tool Failure

Cause an agent tool to fail and correlate:

```text
Trace
+
Application Logs
+
Agent Logs
+
Error Metrics
```

## Scenario 5 — Model Latency / Token Growth

Generate an agent interaction with increased context or token consumption.

Validate:

- [ ] Increased model latency
- [ ] Increased token usage
- [ ] Increased end-to-end request latency

---

# Implementation Order

## Phase 1 — Lab Foundation

- [ ] Create Dynatrace tenant
- [ ] Create GCP Scoping Project
- [ ] Create two Monitored Projects
- [ ] Configure IAM and Service Accounts
- [ ] Enable required APIs

## Phase 2 — Metrics

- [ ] Deploy GKE cluster
- [ ] Deploy Dynatrace Google Cloud integration
- [ ] Deploy/configure Metric Forwarder
- [ ] Attach Monitored Projects to Scoping Project
- [ ] Validate cross-project metrics

## Phase 3 — Logs

- [ ] Create Pub/Sub topic
- [ ] Create Pub/Sub subscription
- [ ] Configure Log Sink
- [ ] Configure Log Forwarder
- [ ] Validate logs from multiple projects
- [ ] Test log ingestion independent of metric monitoring scope

## Phase 4 — ActiveGate + OneAgent

- [ ] Deploy ActiveGate
- [ ] Validate ActiveGate → Dynatrace
- [ ] Deploy GCE VM
- [ ] Install OneAgent
- [ ] Validate OneAgent → ActiveGate
- [ ] Validate infrastructure mode
- [ ] Validate full-stack mode

## Phase 5 — ActiveGate HA

- [ ] Deploy second ActiveGate
- [ ] Configure internal Passthrough NLB
- [ ] Validate load-balanced connectivity
- [ ] Test ActiveGate failure

## Phase 6 — PaaS Extensions

- [ ] Select representative Google Cloud PaaS service
- [ ] Deploy service
- [ ] Install/configure relevant Dynatrace Extension
- [ ] Configure ActiveGate Service Account permissions
- [ ] Validate extension telemetry
- [ ] Investigate duplicate telemetry with Metric Forwarder

## Phase 7 — Application

- [ ] Deploy demo application
- [ ] Generate HTTP traffic
- [ ] Instrument application metrics
- [ ] Instrument application logs
- [ ] Instrument distributed traces
- [ ] Validate telemetry correlation

## Phase 8 — ADK

- [ ] Deploy ADK agent
- [ ] Instrument agent execution
- [ ] Instrument model calls
- [ ] Instrument tool calls
- [ ] Export agent metrics
- [ ] Export structured agent logs
- [ ] Correlate agent telemetry with application traces

## Phase 9 — Failure Demonstrations

- [ ] Infrastructure pressure
- [ ] Application error
- [ ] Slow downstream dependency
- [ ] Failed tool call
- [ ] High model latency
- [ ] Excessive token consumption

## Phase 10 — Final Demo

- [ ] Build Dynatrace dashboards
- [ ] Demonstrate infrastructure → application correlation
- [ ] Demonstrate application → agent correlation
- [ ] Demonstrate metrics + logs + traces
- [ ] Run controlled failure scenario
- [ ] Identify root cause from Dynatrace

---

# Success Criteria

| Integration | Metrics | Logs | Traces |
|---|:---:|:---:|:---:|
| GCP Scoping Project / Metric Forwarder | ✓ | | |
| Pub/Sub / Log Forwarder | | ✓ | |
| OneAgent | ✓ | ✓ | ✓ |
| ActiveGate PaaS Extensions | ✓ | TBD | TBD |
| Application / ADK | ✓ | ✓ | ✓ |

The final demonstration should allow an engineer to move from a high-level service problem to the underlying application, agent, platform, or infrastructure component responsible for the issue.

```text
SYMPTOM
   ↓
SERVICE
   ↓
TRACE
   ↓
APPLICATION / AGENT
   ↓
DEPENDENCY
   ↓
GCP SERVICE
   ↓
INFRASTRUCTURE
   ↓
ROOT CAUSE
```

---

# Questions to Resolve During Implementation

The lab should be used to answer architectural questions rather than assuming the answers in advance.

- [ ] Can logs from projects outside the Metrics Forwarder monitoring scope be ingested through the centralized Pub/Sub path?
- [ ] Which telemetry overlaps between Google Cloud Monitoring and Dynatrace PaaS Extensions?
- [ ] Which telemetry source should be authoritative where overlap exists?
- [ ] What IAM permissions are actually required by each integration?
- [ ] What network paths must exist between OneAgent, ActiveGate, GKE, Google APIs, and Dynatrace?
- [ ] What telemetry can be correlated automatically across GCP, GKE, application, and agent layers?
- [ ] What additional instrumentation is required for ADK?
- [ ] Can model and tool spans participate naturally in the same distributed trace as the originating HTTP request?
- [ ] Which agent metrics should become operational SLIs?
- [ ] What is the minimum production architecture required after the lab proves the integration paths?

---

# Out of Scope

For the first iteration:

- VMware / GCVE
- VMware Engine integrations
- Aria
- Production-scale Dynatrace tenant sizing
- Enterprise log-retention design
- Cortex integration
- Offline / long-term retention architecture
- Complete enterprise SLO design
- Complete production security hardening

These can be added in later iterations after the core Google Cloud observability paths have been proven.
