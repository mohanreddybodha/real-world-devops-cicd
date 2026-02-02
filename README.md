
# 🚀 End-to-End DevOps CI/CD Project
### **Kubernetes · Jenkins · Terraform · Ansible · AWS ALB · Monitoring · Slack Alerts**

---

## 📌 Project Overview
This project demonstrates a real-world DevOps CI/CD pipeline that automates:

* **Infrastructure provisioning** using Terraform
* **Kubernetes cluster setup** using kubeadm + Ansible
* **Application build & deployment** using Jenkins
* **Traffic management** using AWS Application Load Balancer (ALB)
* **Monitoring & observability** using Prometheus, Grafana, Alertmanager
* **Real-time alerting** via Slack integration

The system is built with production best practices, idempotent automation, and clear separation of responsibilities across tools.

---

## 🧱 High-Level Architecture


GitHub
   
  ↓ (Webhook)  
**Jenkins** (Docker container)  
  ↓  
**Terraform** (AWS Infrastructure)  
  ↓  
**Ansible** (Kubernetes Bootstrap)  
  ↓  
**Kubernetes Cluster** (kubeadm)  
  ↓  
**AWS ALB** (Ingress)  
  ↓  
**Application + Monitoring Stack** 
  ↓  
**Slack Alerts** (Alertmanager)

---

## ☁️ Infrastructure – Terraform

### **AWS Resources Created**
* **EC2 Instances**
    * 1 × Master node
    * 2 × Worker nodes
* **Elastic IPs** for all nodes
* **Security Groups**
    * SSH access
    * NodePort range
    * ALB traffic
* **IAM Role & Instance Profile**
    * Required for AWS Load Balancer Controller
* **S3 Backend**
    * Remote Terraform state storage

### **Why This Design?**
* **Worker IAM Role** is mandatory for ALB Controller.
* **Elastic IPs** enable stable SSH & debugging.
* **NodePort range** allows ALB target-type = instance.
* **Remote state** enables safe Terraform re-runs.

---

## ⚙️ CI/CD Pipeline – Jenkins
Jenkins runs inside a Docker container on a **t2.medium** EC2 instance and is connected to GitHub via webhook.

### **Pipeline Stages (Executed in Order)**

#### **1️⃣ Code Checkout**
Pulls application and infrastructure code from GitHub.

#### **2️⃣ Parameter Validation**
Ensures required runtime inputs (e.g., ALB DNS). Pipeline fails fast if missing.

#### **3️⃣ Dependency Installation (Parallel)**
* **Backend:** `npm install`
* **Frontend:** `npm install`

#### **4️⃣ Frontend Build**
Builds frontend assets and copies static files into backend public directory.

#### **5️⃣ Backend Validation**
Syntax validation using `node -c`.

#### **6️⃣ Docker Build & Push**
Builds Docker image and pushes to Docker Hub. **Image tag = Jenkins build number**.

#### **7️⃣ Infrastructure Provisioning (Terraform)**
Creates or updates AWS infrastructure. Controlled via Jenkins parameter to avoid accidental re-provisioning.

#### **8️⃣ Dynamic Ansible Inventory**
Reads Terraform outputs and generates inventory dynamically for Master and Worker nodes.

#### **9️⃣ Kubernetes Bootstrap (Ansible)**
* **Common Modules:** Disable swap, Kernel module loading, Sysctl tuning, Containerd, and Kubernetes binaries.
* **Master Node:** `kubeadm init`, Flannel CNI, CoreDNS checks, Helm installation, and Join token generation.
* **Worker Nodes:** Safe join with retry logic.

#### **🔟 AWS Load Balancer Controller + Cert-Manager**
Installed only if missing. Includes strong guard checks. Waits for Webhook CA bundle injection and TLS readiness to prevent random pipeline failures.

---

## 📊 Monitoring Stack (Deployed Before Application)
Monitoring is deployed before the application to ensure observability from day one.

### **Components**
| Tool | Purpose |
| :--- | :--- |
| **Prometheus** | Metrics collection |
| **Grafana** | Visualization |
| **Alertmanager** | Alert routing |
| **Slack** | Alert notifications |

### **Deployment Method**
* **Helm:** `kube-prometheus-stack`
* **Custom:** `monitoring-values.yaml`
* **Routing:** Path-based routing via ALB

---

## 🔔 Alerting & Slack Integration

### **Alert Flow**
**Prometheus → Alertmanager → Slack**

### **Key Features**
* **Slack Webhook** stored securely in Jenkins Credentials; injected dynamically during deployment.
* **No secrets hardcoded.**
* **Watchdog alert** used for verification.

---

## 🌐 Traffic Management – AWS ALB

### **Ingress Strategy**
* Single Application Load Balancer
* **Shared Ingress Group:** `main-alb`
* Path-based routing

### **Final Routing Table**
| Path | Namespace | Service |
| :--- | :--- | :--- |
| `/app` | `default` | `app-service` |
| `/grafana` | `monitoring` | `grafana` |
| `/prometheus` | `monitoring` | `prometheus` |
| `/alertmanager` | `monitoring` | `alertmanager` |

> **Why target-type = instance?** > Avoids ENI / providerID issues in kubeadm clusters and works reliably with NodePort.

---

## 🧠 Real-World Debugging & Production Issues Faced

This project was not a one-click deployment. Multiple failures occurred across infrastructure, Kubernetes, ingress, monitoring, and CI/CD orchestration. Below are real problems I faced, how I identified them, and how I fixed them.

**These issues reflect actual production DevOps work, not tutorial scenarios.**

---

### ❌ 1. Initial EC2 Bootstrap Failure – Python Not Available

* **Mistake:** I initially assumed Python would be available on fresh EC2 instances and directly used Ansible modules during the first run.
* **Observed Symptoms:** * Ansible failed immediately on new EC2 nodes.
    * Errors related to missing `python` / `apt` modules.
    * Nodes were unreachable for configuration management.
* **Root Cause:** Fresh EC2 instances do not guarantee Python readiness. Ansible requires Python to manage a host.
* **Fix Applied:**
    * **Step 1 (Temporary):** Used Ansible `raw` module to manually install Python.
    * **Step 2 (Final Design):** Moved all OS-level bootstrap logic into **Terraform `user_data`**. Switched fully to clean, idempotent Ansible modules.
* **Key Learning:** > Terraform should bootstrap the OS baseline; Ansible should assume a ready system.

---

### ❌ 2. ALB Target Groups Always Unhealthy (504 Gateway Timeout)

* **Observed Symptoms:** * Jenkins pipeline succeeded and ALB was created.
    * Browser returned **504 Gateway Timeout**.
    * AWS Target Groups showed all targets as `Unhealthy`.
* **Controller Logs:** `cannot resolve pod ENI for pods`
* **Root Cause:** ALB `target-type` was set to `ip`. `kubeadm`-based clusters do not auto-populate `providerID`, so the Controller failed to map pods to EC2 ENIs.
* **Fix Applied:** Switched ALB target type to `instance` and converted services to **NodePort**.
* **Why This Matters:** > This shows a deep understanding of AWS ALB internals vs. self-managed clusters.

---

### ❌ 3. Jenkins Re-Runs Causing Resource Conflicts

* **Observed Symptoms:** Re-running the pipeline caused duplicate Helm installs, webhook failures, and namespace conflicts.
* **Root Cause:** Pipeline was not **idempotent**; it lacked guard checks before installations.
* **Fix Applied:** Added guards for Namespace existence, Deployment status, and Helm release presence.
* **Key Learning:** > A CI/CD pipeline must be re-runnable, not "run once".

---

### ❌ 4. AWS Load Balancer Controller Webhook TLS Failures

* **Observed Symptoms:** Ingress creation randomly failed during the apply stage.
* **Logs:** `tls: bad certificate` | `tls: private key does not match public key`
* **Root Cause:** Race condition between `cert-manager` and the AWS LB Controller webhook. The CA bundle was not injected yet when ingress was applied.
* **Fix Applied:** Added Ansible guard tasks to **wait for webhook CA bundle size** and verify webhook health before proceeding.

---

### ❌ 5. Ingress Applied but No Load Balancer Created

* **Observed Symptoms:** Ingress applied successfully in Kubernetes, but **no ALB appeared** in the AWS console.
* **Root Cause:** The Controller was not fully ready or the webhook was unreachable at apply time.
* **Fix Applied:** Implemented explicit rollout checks and TLS readiness verification in the pipeline.

---

### ❌ 6. Application UI Loaded Without CSS / JS

* **Observed Symptoms:** HTML loaded correctly, but CSS and JS were missing (Broken UI).
* **Root Cause:** Application was served behind `/app`, but frontend assets pointed to `/`.
* **Fix Applied:** Updated frontend paths to align with ingress: `<link rel="stylesheet" href="/app/style.css">`.

---

### ❌ 7. Monitoring Paths Redirecting to Application

* **Observed Symptoms:** `/grafana`, `/prometheus`, and `/alertmanager` returned the main application UI.
* **Root Cause:** A catch-all path `/*` was routing to the app due to ALB rule priority.
* **Fix Applied:** Separated ingress files and ensured specific paths were applied before the catch-all app ingress.

---

### ❌ 8. Alertmanager CrashLoopBackOff

* **Observed Symptoms:** Alertmanager pod continuously restarting.
* **Logs:** `failed to determine external URL` | `"/alertmanager/": invalid "" scheme`
* **Root Cause:** Missing `http://` scheme in `externalUrl`.
* **Fix Applied:** Corrected config to: `externalUrl: http://${ALB_DNS}/alertmanager`.

---

### ❌ 9. Grafana Could Not Connect to Prometheus

* **Observed Symptoms:** Grafana UI was accessible, but the Prometheus datasource failed.
* **Root Cause:** Prometheus was configured with a `routePrefix: /prometheus`, but the Grafana URL omitted it.
* **Fix Applied:** Updated URL to `http://...svc:9090/prometheus`.

---

### ❌ 10. Prometheus Showing Grafana Target as DOWN

* **Observed Symptoms:** Grafana worked, but Prometheus reported the target as `DOWN`.
* **Root Cause:** Scrape endpoint misalignment for the Grafana NodePort service.
* **Fix Applied:** Corrected service ports and ensured scrape endpoints matched the Grafana service.

---

### ❌ 11. ALB Basic Auth Misconception

* **Mistake:** Tried to apply NGINX-style basic auth annotations on an ALB ingress.
* **Reality:** **ALB does not support native basic auth** (requires Cognito/OIDC).
* **Final Decision:** Handled Grafana authentication at the application level.

---

### ❌ 12. Port Forwarding Confusion

* **Observed Behavior:** UI accessible via `kubectl port-forward` but not via the ALB.
* **Clarification:** Port-forwarding bypasses ALBs and Security Groups. It was used intentionally only for secure internal debugging.

---

### ❌ 13. Incorrect Assumption: Single Ingress for Multiple Namespaces

* **Mistake:** Assumed one ingress object could route to services across different namespaces.
* **Root Cause:** Ingress is **namespace-scoped**.
* **Fix Applied:** Created one ingress per namespace and linked them to a shared ALB via an **Ingress Group**.
* **Key Learning:** > Sharing infrastructure (ALB) does not mean sharing Kubernetes objects (Ingress).

---

## ✅ Final Outcome
✔ **Fully automated** CI/CD pipeline  
✔ **Kubernetes cluster** built from scratch  
✔ **AWS ALB** with shared ingress  
✔ **Slack alerts** working in real time  
✔ **Idempotent**, production-safe automation  

---

## 💼 Resume Highlights
* Built end-to-end CI/CD pipeline using **Jenkins, Terraform, Ansible, Kubernetes**.
* Deployed production-grade monitoring with **Prometheus, Grafana, Alertmanager**.
* Integrated **Slack alerting** with secure secret handling.
* Implemented **AWS ALB ingress** with shared routing & health checks.

---

## 📚 Core Learning From This Project
> **"Production systems don’t fail once — they fail in layers. Progress comes from fixing the layer beneath the visible error."**

This project was completed by re-running pipelines until they became fully idempotent and identifying wrong assumptions to correct them properly.



---

##  **👨‍💻 About Me**

**Name:** Mohan Reddy Boda

**GitHub:** [github.com/mohanreddybodha](https://github.com/mohanreddybodha)

**DockerHub:** [hub.docker.com/u/mohanreddybodha](https://hub.docker.com/u/mohanreddybodha)

**LinkedIn:** [https://www.linkedin.com/in/mohan-reddy-boda-0560722b7/](https://www.linkedin.com/in/mohan-reddy-boda-0560722b7/)

**Email:** [mohanreddybodha05@gmail.com](mailto:mohanreddybodha05@gmail.com)




---

## 🧭 END OF GUIDE

This repository is **not** a tutorial-style project. 

It represents the outcome of hundreds of CI/CD pipeline executions, repeated failures, rollbacks, and architectural redesigns.

---

### 🔁 What Actually Happened During Development

During development:
* **Many builds failed** after running for 20–30 minutes.
* Several times the system **worked partially** and then broke after a small change.
* Multiple issues appeared to be “the last bug” but **exposed deeper root problems**.

> *There were moments where stopping the project felt easier than continuing.*

---

### 🧠 Decision That Changed the Outcome

Instead of abandoning the project, I followed one rule:
1. **Treat every failure as the final blocker.**
2. **Solve it completely** before moving forward.
3. **Never patch symptoms** — always fix the root cause.

---

### 🔍 Why the Debugging Section Matters

Every error documented in this repository:
* **Actually occurred.**
* Was debugged using **logs, metrics, and system behavior**.
* Led to a **permanent architectural or automation improvement**.

Nothing here is hypothetical or copied from documentation.

---

### ⚙️ How This Project Was Completed

This project was completed by:
* **Re-running pipelines** until they became fully idempotent.
* **Breaking and rebuilding** infrastructure safely.
* **Respecting tool boundaries:**
    * **Terraform** for infrastructure.
    * **Ansible** for configuration.
    * **Kubernetes** for orchestration.
    * **ALB** for traffic management.
* Identifying **wrong assumptions** and correcting them properly.

---

### 👀 Guidance for Reviewers

If you are reviewing this project:
* **Do not skip the “Debugging & Issues Faced” section.**
* That section reflects **real DevOps work** more than the final success state.
* The final working system exists **because of those failures**, not despite them.

---

### 📚 Core Learning From This Project

This project reinforced a critical production lesson:

> **"Production systems don’t fail once — they fail in layers. Progress comes from fixing the layer beneath the visible error."**

That mindset is what ultimately completed this project.

---
