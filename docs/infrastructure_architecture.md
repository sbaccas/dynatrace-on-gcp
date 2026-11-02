# Representative Workload Project Architecture (`workload-app-prod`)

This document renders a representative multi-service cloud workload infrastructure deployed in `workload-app-prod` (`us-central1`) demonstrating GCE VM, Cloud Run v2, and Vertex AI ADK agent telemetry collection.

---

## Architecture Diagram

```mermaid
flowchart TB
    subgraph VPC ["Standalone Workload VPC: workload-vpc (10.10.0.0/16)"]
        subgraph Subnet ["Primary Workload Subnet: workload-vpc-subnet (10.10.0.0/24)"]
            JB["Workload VM / Jumpbox<br/>(e2-standard-4, Ubuntu + Dynatrace OneAgent)"]
            ILB_IP["Internal Gateway Private Static IP<br/>(workload-internal-gateway-ip)"]
        end

        subgraph AGSubnet ["Dedicated ActiveGate Subnet: workload-activegate-subnet (10.10.2.0/24)"]
            AG1["dynatrace-ag-01 (10.10.2.10)<br/>Zone A · TCP :9999"]
            AG2["dynatrace-ag-02 (10.10.2.11)<br/>Zone B · TCP :9999"]
        end

        subgraph ProxySubnet ["Regional Managed Proxy Subnet (10.10.1.0/24)"]
            ILB["Regional Internal Application Load Balancer<br/>(URL Map: workload-internal-url-map)"]
        end

        subgraph DNS ["Cloud DNS Private Managed Zone: app.internal."]
            D1["api.app.internal ➔ ILB_IP"]
            D2["agent1.app.internal ➔ ILB_IP"]
            D3["agent2.app.internal ➔ ILB_IP"]
            D4["mcp.app.internal ➔ ILB_IP"]
        end

        NAT["Cloud Router & Cloud NAT<br/>(Outbound egress for ActiveGate & package pulls)"]
    end

    subgraph CloudRun ["Cloud Run v2 Services (Direct VPC Egress + OTel Instrumentation)"]
        GS["core-api-service<br/>(Port 8000, 2 vCPU, 2GiB RAM)"]
        CA1["adk-agent-1<br/>(Port 8001, 2 vCPU, 2GiB RAM, min=1, max=1)"]
        CA2["adk-agent-2<br/>(Port 8003, 2 vCPU, 2GiB RAM, min=1, max=1)"]
        MCP["mcp-tool-server<br/>(Port 9050, 2 vCPU, 2GiB RAM)"]
    end

    subgraph GAR ["Artifact Registry (Docker)"]
        REPO["workload-repo<br/>(us-central1-docker.pkg.dev/workload-app-prod/workload-repo)"]
    end

    subgraph IAM ["IAM & Vertex AI"]
        CR_SA["Runtime SA: workload-cloudrun-sa<br/>(roles/aiplatform.user for Vertex AI Gemini LLM)"]
        JB_SA["Workload VM SA: workload-vm-sa<br/>(roles/run.invoker, roles/aiplatform.user)"]
    end

    JB -->|"Private DNS: http://mcp.app.internal"| ILB
    JB -->|"OneAgent Telemetry (:9999)"| AG1
    JB -->|"OneAgent Telemetry (:9999)"| AG2
    ILB -->|"Serverless NEG"| MCP
    ILB -->|"Serverless NEG"| GS
    ILB -->|"Serverless NEG"| CA1
    ILB -->|"Serverless NEG"| CA2
```

---

## Component Breakdown

| Layer | Resource Name | Specs & Configuration | Role |
| :--- | :--- | :--- | :--- |
| **VPC** | `workload-vpc` | `10.10.0.0/16` isolated custom VPC | Core network boundary for observable compute & serverless services |
| **Workload Subnet** | `workload-vpc-subnet` | `10.10.0.0/24` with Private Google Access | Hosts GCE VMs (with OneAgent) and Direct VPC Egress from Cloud Run |
| **ActiveGate Subnet** | `workload-activegate-subnet` | `10.10.2.0/24` with Private Google Access | Hosts multi-zone Dynatrace ActiveGate VMs (`10.10.2.10`, `10.10.2.11`) |
| **Proxy Subnet** | `workload-vpc-proxy-subnet` | `10.10.1.0/24` (`REGIONAL_MANAGED_PROXY`) | Envoy proxies for Regional Internal Application Load Balancer |
| **Workload VM** | `workload-vm-01` | `e2-standard-4`, 50GB SSD, Ubuntu 22.04 | Monitored Linux GCE instance running Dynatrace OneAgent in Full-Stack mode |
| **Cloud DNS** | `app.internal.` | Private Managed DNS Zone | Routes internal service subdomains to internal gateway IP |
| **Load Balancer** | `workload-internal-forwarding-rule` | Regional Internal Managed HTTP Load Balancer | URL map host routing to Cloud Run Serverless NEGs on port 80 |
| **Core API Service** | `core-api-service` | Cloud Run v2 (Port 8000, 2 vCPU, 2GiB) | Core application backend instrumented with OpenTelemetry (OTLP) |
| **ADK Agent 1** | `adk-agent-1` | Cloud Run v2 (Port 8001, 2 vCPU, 2GiB) | Google ADK Gemini agent runtime exporting OTel model & tool spans |
| **ADK Agent 2** | `adk-agent-2` | Cloud Run v2 (Port 8003, 2 vCPU, 2GiB) | Secondary ADK agent runtime exporting OTel spans and metrics |
| **MCP Server** | `mcp-tool-server` | Cloud Run v2 (Port 9050, 2 vCPU, 2GiB) | FastMCP Model Context Protocol tool server |
| **Registry** | `workload-repo` | Artifact Registry Docker repository | Stores versioned container images |
| **Runtime Identity** | `workload-cloudrun-sa` | Service Account (`roles/aiplatform.user`) | Grants agents access to Vertex AI Gemini LLMs |

