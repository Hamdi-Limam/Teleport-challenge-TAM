Summary for the demo: "A user proves who they are with an x509 client certificate the cluster CA signed, Kubernetes RBAC decides what that identity is allowed to do, ArgoCD syncs the desired state from Git, and everything the user can touch is scoped to a single namespace."

Repository layout

teleport-k8s-challenge/
├── README.md                   <- you are here (install + run steps)
├── DESIGN.md                   <- design doc: approaches, tradeoffs, security
├── scripts/                    <- one-time human-run setup steps 
│   ├── prerequisite.sh         <- OS prep: containerd, kernel, swap, sysctl
│   ├── install-k8s.sh          <- install kubelet/kubeadm/kubectl (pinned)
│   ├── init-control-plane.sh   <- kubeadm init + Calico CNI
│   ├── join-workers.sh         <- regenerate join command if token expired
│   └── create-user-csr.sh      <- generate key + CSR, submit to K8s, approve
└── manifests/                  <- desired cluster state — ArgoCD watches this directory
    ├── namespace.yaml          <- web namespace
    ├── role.yaml               <- least-privilege Role
    ├── rolebinding.yaml        <- binds the cert identity to the Role
    ├── nginx-configmap.yaml    <- the static site content
    ├── nginx-deployment.yaml   <- nginx Deployment (pinned image, hardened pod)
    ├── nginx-service.yaml      <- ClusterIP service
    ├── clusterissuer.yaml      <- cert-manager self-signed ClusterIssuer
    ├── certificate.yaml        <- TLS Certificate for the site
    └── nginx-ingress.yaml      <- Ingress terminating TLS with that cert

Why scripts and manifests are separate: Scripts are one-time human-run bootstrap steps. Manifests are the desired state of the cluster — ArgoCD owns and continuously reconciles this directory. Mixing them would cause ArgoCD to attempt to apply .sh files as Kubernetes resources.

Prerequisites
3 Linux VMs (Ubuntu 22.04 LTS): cp1 (control plane, 2 vCPU / 2 GB min), worker1, worker2 (1 vCPU / 2 GB each). All on the same private network. Free-tier capable — tested on AWS EC2 and Oracle Cloud Always Free (A1 Ampere).

Pinned versions for reproducibility:
- Kubernetes v1.30
- containerd (Ubuntu repo)
- Calico v3.27 (pod CIDR 192.168.0.0/16)
- cert-manager v1.14
- ArgoCD stable
- nginx 1.27-alpine

Step-by-step 

Phase 1 — Cluster bootstrap (all nodes)

Step 1 — OS prep (run on ALL three nodes)
sudo bash scripts/prerequisite.sh -> Disables swap, loads kernel modules, sets sysctls, installs and configures containerd with the systemd cgroup driver.

Step 2 — Install Kubernetes tools (run on ALL three nodes)
sudo bash scripts/install-k8s.sh -> Installs pinned kubelet, kubeadm, kubectl and holds them so apt upgrade cannot silently skew versions.

Step 3 — Initialise the control plane (cp1 only)
sudo bash scripts/init-control-plane.sh -> Runs kubeadm init with --apiserver-advertise-address=<cp1-private-ip>, sets up the admin kubeconfig, and installs Calico CNI. Wait until kubectl get nodes shows cp1 as Ready.

Copy the printed kubeadm join ... command for the next step.

Step 4 — Join the worker nodes (worker1, worker2)
sudo kubeadm join <cp-ip>:6443 --token <...> --discovery-token-ca-cert-hash sha256:<...>

Token expires after 24 hours. Regenerate with sudo bash scripts/join-workers.sh on cp1 if needed.

Confirm all nodes are Ready:
kubectl get nodes -o wide     # cp1, worker1, worker2 all Ready


Phase 2 — User identity via the Kubernetes CSR API

Step 5 — Create the nginx-deployer user
bash scripts/create-user-csr.sh nginx-deployer web

This script:
Generates nginx-deployer.key locally (2048-bit RSA — git-ignored, never shared)
Builds a CSR with CN=nginx-deployer, O=nginx-team
Submits it as a CertificateSigningRequest to the cluster
Approves it: kubectl certificate approve nginx-deployer
Extracts the signed cert and builds nginx-deployer.kubeconfig

Verify the identity:
kubectl --kubeconfig=user-certs/nginx-deployer.kubeconfig auth whoami
# Username: nginx-deployer, Groups: [nginx-team system:authenticated]


Phase 3 — RBAC and application (ArgoCD syncs this automatically)

Step 6 — Install cert-manager (admin, cluster-scoped)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager-webhook

Step 7 — Install ArgoCD
sudo bash scripts/argoCD-install.sh

Phase 4 — Verify end to end
# RBAC: user can act inside web, denied everywhere else

kubectl --kubeconfig=user-certs/nginx-deployer.kubeconfig auth can-i create deployments -n web # yes

kubectl --kubeconfig=user-certs/nginx-deployer.kubeconfig auth can-i get pods -n kube-system # no

# TLS: certificate issued by cert-manager
kubectl get certificate -n web   # READY=True

# Site: served over HTTPS

curl -k --resolve nginx.web.example.com:<HTTPS-NODEPORT>:<any-node-ip> https://nginx.web.example.com:<HTTPS-NODEPORT>/

Phase 6 — Teardown
# on all nodes
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube

# on cp1 — remove user cert material
rm -rf user-certs/



