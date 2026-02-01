---

🚀 End-to-End DevOps CI/CD Project

Kubernetes · Jenkins · Terraform · Ansible · AWS ALB · Monitoring · Slack Alerts


---

📌 Project Overview

This project demonstrates a real-world DevOps CI/CD pipeline that automates:

Infrastructure provisioning using Terraform

Kubernetes cluster setup using kubeadm + Ansible

Application build & deployment using Jenkins

Traffic management using AWS Application Load Balancer (ALB)

Monitoring & observability using Prometheus, Grafana, Alertmanager

Real-time alerting via Slack integration


The system is built with production best practices, idempotent automation, and clear separation of responsibilities across tools.


---

🧱 High-Level Architecture

GitHub
  ↓ (Webhook)
Jenkins (Docker container)
  ↓
Terraform (AWS Infrastructure)
  ↓
Ansible (Kubernetes Bootstrap)
  ↓
Kubernetes Cluster (kubeadm)
  ↓
AWS ALB (Ingress)
  ↓
Application + Monitoring Stack
  ↓
Slack Alerts (Alertmanager)


---

☁️ Infrastructure – Terraform

AWS Resources Created

EC2 Instances

1 × Master node

2 × Worker nodes


Elastic IPs for all nodes

Security Groups

SSH access

NodePort range

ALB traffic


IAM Role & Instance Profile

Required for AWS Load Balancer Controller


S3 Backend

Remote Terraform state storage



Why This Design?

Worker IAM Role is mandatory for ALB Controller

Elastic IPs enable stable SSH & debugging

NodePort range allows ALB target-type = instance

Remote state enables safe Terraform re-runs



---

⚙️ CI/CD Pipeline – Jenkins

Jenkins runs inside a Docker container on a t2.medium EC2 instance and is connected to GitHub via webhook.

Pipeline Stages (Executed in Order)


---

1️⃣ Code Checkout

Pulls application and infrastructure code from GitHub



---

2️⃣ Parameter Validation

Ensures required runtime inputs (e.g., ALB DNS)

Pipeline fails fast if missing



---

3️⃣ Dependency Installation (Parallel)

Backend: npm install

Frontend: npm install



---

4️⃣ Frontend Build

Builds frontend assets

Copies static files into backend public directory



---

5️⃣ Backend Validation

Syntax validation using node -c



---

6️⃣ Docker Build & Push

Builds Docker image

Pushes to Docker Hub

Image tag = Jenkins build number



---

7️⃣ Infrastructure Provisioning (Terraform)

Creates or updates AWS infrastructure

Controlled via Jenkins parameter to avoid accidental re-provisioning



---

8️⃣ Dynamic Ansible Inventory

Reads Terraform outputs

Generates inventory dynamically for:

Master node

Worker nodes




---

9️⃣ Kubernetes Bootstrap (Ansible)

Common Modules

Disable swap

Kernel module loading

Sysctl tuning

Containerd installation

Kubernetes binaries installation


Master Node

kubeadm init

Flannel CNI

CoreDNS readiness checks

Helm installation

Join token generation


Worker Nodes

Safe join with retry logic



---

🔟 AWS Load Balancer Controller + Cert-Manager

Installed only if missing

Includes strong guard checks

Waits for:

Webhook CA bundle injection

TLS readiness


Prevents random webhook-related pipeline failures



---

📊 Monitoring Stack (Deployed Before Application)

Monitoring is deployed before the application to ensure observability from day one.

Components

Tool	Purpose

Prometheus	Metrics collection
Grafana	Visualization
Alertmanager	Alert routing
Slack	Alert notifications


Deployment Method

Helm: kube-prometheus-stack

Custom monitoring-values.yaml

NodePort services

Path-based routing via ALB



---

🔔 Alerting & Slack Integration

Alert Flow

Prometheus → Alertmanager → Slack

Key Features

Slack Webhook stored securely in Jenkins Credentials

Injected dynamically during deployment

No secrets hardcoded

Alert grouping & repeat intervals configured

Watchdog alert used for verification


Example Alerts

Pod CrashLoopBackOff

Node NotReady

Prometheus target down

Application health check failures



---

🌐 Traffic Management – AWS ALB

Ingress Strategy

Single Application Load Balancer

Shared Ingress Group: main-alb

Path-based routing


Final Routing

Path	Namespace	Service

/app	app	app-service
/grafana	monitoring	grafana
/prometheus	monitoring	prometheus
/alertmanager	monitoring	alertmanager


Why target-type = instance?

Avoids ENI / providerID issues in kubeadm clusters

Works reliably with NodePort

Stable for self-managed Kubernetes


---

🧠 Real-World Debugging & Production Issues Faced

This project was not a one-click deployment.
Multiple failures occurred across infrastructure, Kubernetes, ingress, monitoring, and CI/CD orchestration.
Below are real problems I faced, how I identified them, and how I fixed them.

These issues reflect actual production DevOps work, not tutorial scenarios.


---

❌ 1. Initial EC2 Bootstrap Failure – Python Not Available

Mistake

I initially assumed Python would be available on fresh EC2 instances and directly used Ansible modules during the first run.

Observed Symptoms

Ansible failed immediately on new EC2 nodes

Errors related to missing Python / apt modules

Nodes were unreachable for configuration management


Root Cause

Fresh EC2 instances do not guarantee Python readiness.
Ansible requires Python before it can manage a host, but I violated that assumption.

Fix Applied

Step 1 (Temporary Fix)

Used Ansible raw module to manually install Python


Step 2 (Correct Final Design)

Moved all OS-level bootstrap logic into Terraform user_data

Installed Python during instance creation

Removed raw module usage completely

Switched fully to clean, idempotent Ansible modules in common-modules.yaml


Key Learning

> Terraform should bootstrap the OS baseline.
Ansible should assume a ready system.




---

❌ 2. ALB Target Groups Always Unhealthy (504 Gateway Timeout)

Observed Symptoms

Jenkins pipeline succeeded

ALB was created successfully

Browser returned 504 Gateway Timeout

AWS Target Groups showed all targets Unhealthy


Controller Logs

cannot resolve pod ENI for pods

Root Cause

ALB target-type was set to ip

kubeadm-based clusters do not auto-populate providerID

AWS Load Balancer Controller failed to map pods → EC2 ENIs


Fix Applied

Switched ALB target type to:


alb.ingress.kubernetes.io/target-type: instance

Converted services to NodePort

ALB now targets EC2 instances, not pod IPs


Why This Matters

> This shows understanding of AWS ALB internals vs EKS-managed clusters.




---

❌ 3. Jenkins Re-Runs Causing Resource Conflicts

Observed Symptoms

Re-running pipeline caused:

Duplicate Helm installs

Webhook failures

Namespace conflicts



Root Cause

Pipeline was not idempotent

No guard checks before installs


Fix Applied

Added guards for:

Namespace existence

Deployment existence

Helm release presence

Conditional installs


Key Learning

> A CI/CD pipeline must be re-runnable, not “run once”.




---

❌ 4. AWS Load Balancer Controller Webhook TLS Failures

Observed Symptoms

Ingress creation randomly failed

Pipeline broke during apply stage


Logs

tls: bad certificate
tls: private key does not match public key

Root Cause

Race condition between:

cert-manager

AWS Load Balancer Controller webhook


The CA bundle was not injected yet when ingress was applied.

Fix Applied

Added strong Ansible guard tasks:

Wait for webhook CA bundle size

Verify webhook service exists

Curl webhook /healthz endpoint before proceeding


Key Learning

> Webhooks require strict sequencing in production.




---

❌ 5. Ingress Applied but No Load Balancer Created

Observed Symptoms

Ingress applied successfully

No ALB appeared in AWS console


Root Cause

AWS Load Balancer Controller was not fully ready

Webhook not reachable at apply time


Fix Applied

Explicit rollout checks

TLS readiness verification

Fail-fast guards in Ansible



---

❌ 6. Application UI Loaded Without CSS / JS

Observed Symptoms

HTML loaded correctly

CSS and JS missing

Broken UI in browser


Root Cause

Application was served behind /app, but frontend assets pointed to /.

Fix Applied

Updated frontend paths:

<link rel="stylesheet" href="/app/style.css">
<script src="/app/app.js"></script>

Key Learning

> Frontend routing must align with ingress paths.




---

❌ 7. Monitoring Paths Redirecting to Application

Observed Symptoms

/grafana, /prometheus, /alertmanager returned app UI


Root Cause

Catch-all path /* routed to app

ALB evaluates rules by priority


Fix Applied

Separate ingress files

Correct path specificity

Applied monitoring ingress before app ingress



---

❌ 8. Alertmanager CrashLoopBackOff

Observed Symptoms

Alertmanager pod continuously restarting


Logs

failed to determine external URL
"/alertmanager/": invalid "" scheme

Root Cause

Missing scheme in externalUrl

Misaligned routePrefix


Fix Applied

routePrefix: /alertmanager
externalUrl: http://${ALB_DNS}/alertmanager


---

❌ 9. Grafana Could Not Connect to Prometheus

Observed Symptoms

Grafana UI accessible

Prometheus datasource showed connection failure


Wrong URL

http://monitoring-kube-prometheus-prometheus.monitoring.svc:9090

Correct Fix

http://monitoring-kube-prometheus-prometheus.monitoring.svc:9090/prometheus

Reason

Prometheus was configured with:

routePrefix: /prometheus


---

❌ 10. Prometheus Showing Grafana Target as DOWN

Observed Symptoms

Grafana UI worked

Prometheus targets page showed Grafana DOWN


Root Cause

Grafana exposed via NodePort

Scrape endpoint misalignment


Fix Applied

Corrected service ports

Ensured scrape endpoints matched Grafana service



---

❌ 11. ALB Basic Auth Misconception

Mistake

Tried to apply NGINX-style basic auth annotations on ALB ingress.

Reality

ALB does not support basic auth

Only Cognito / OAuth / WAF supported


Final Decision

Grafana authentication handled at app level

Prometheus & Alertmanager accessed via controlled methods



---

❌ 12. Port Forwarding Confusion

Observed Behavior

UI accessible after kubectl port-forward

Not accessible otherwise


Clarification

kubectl port-forward creates a local API-server tunnel, bypassing:

ALB

Ingress

Security Groups


Used intentionally for secure internal access.


---

❌ 13. Incorrect Assumption: Single Ingress for Multiple Namespaces

Mistake

Assumed one ingress could route to services across namespaces.

Root Cause

Ingress is namespace-scoped and cannot resolve cross-namespace services.

Fix Applied

One ingress per namespace

Shared ALB via ingress group


Key Learning

> Sharing infrastructure ≠ sharing Kubernetes objects.



---

✅ Final Outcome

✔ Fully automated CI/CD pipeline
✔ Kubernetes cluster built from scratch
✔ AWS ALB with shared ingress
✔ Application & monitoring accessible
✔ Slack alerts working in real time
✔ Idempotent, production-safe automation


---

💼 Resume Highlights

Built end-to-end CI/CD pipeline using Jenkins, Terraform, Ansible, Kubernetes

Deployed production-grade monitoring with Prometheus, Grafana, Alertmanager

Integrated Slack alerting with secure secret handling

Implemented AWS ALB ingress with shared routing & health checks

Solved real Kubernetes networking and ingress challenges



---

📎 Notes

This project reflects real production debugging, not a tutorial setup.
All architectural decisions were validated through failures, fixes, and re-runs.


---



## 👨‍💻 About Me

**Name:** Mohan Reddy Boda

**GitHub:** [github.com/mohanreddybodha](https://github.com/mohanreddybodha)

**DockerHub:** [hub.docker.com/u/mohanreddybodha](https://hub.docker.com/u/mohanreddybodha)

**LinkedIn:** [https://www.linkedin.com/in/mohan-reddy-boda-0560722b7/](https://www.linkedin.com/in/mohan-reddy-boda-0560722b7/)

**Email:** [mohanreddybodha05@gmail.com](mailto:mohanreddybodha05@gmail.com)



---


##🧭 END OF GUIDE

This repository is not a tutorial-style project.

It represents the outcome of hundreds of CI/CD pipeline executions, repeated failures, rollbacks, and architectural redesigns.


---

🔁 What Actually Happened During Development

During development:

Many builds failed after running for 20–30 minutes

Several times the system worked partially and then broke after a small change

Multiple issues appeared to be “the last bug” but exposed deeper root problems


There were moments where stopping the project felt easier than continuing.


---

🧠 Decision That Changed the Outcome

Instead of abandoning the project, I followed one rule:

> Treat every failure as the final blocker.
Solve it completely before moving forward.
Never patch symptoms — always fix the root cause.




---

🔍 Why the Debugging Section Matters

Every error documented in this repository:

Actually occurred

Was debugged using logs, metrics, and system behavior

Led to a permanent architectural or automation improvement


Nothing here is hypothetical or copied from documentation.


---

⚙️ How This Project Was Completed

This project was completed by:

Re-running pipelines until they became fully idempotent

Breaking and rebuilding infrastructure safely

Respecting tool boundaries
(Terraform for infrastructure, Ansible for configuration, Kubernetes for orchestration, ALB for traffic)

Identifying wrong assumptions and correcting them properly



---

👀 Guidance for Reviewers

If you are reviewing this project:

Do not skip the “Debugging & Issues Faced” section

That section reflects real DevOps work more than the final success state

The final working system exists because of those failures, not despite them



---

📚 Core Learning From This Project

This project reinforced a critical production lesson:

> Production systems don’t fail once — they fail in layers.
Progress comes from fixing the layer beneath the visible error.



That mindset is what ultimately completed this project.

---