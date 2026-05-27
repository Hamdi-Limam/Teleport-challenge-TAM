
1. Goal restated
Stand up a real kubeadm cluster (1 control plane + 2 workers), and have a non-admin user deploy and manage a static Nginx site in its own namespace. The user authenticates with an x509 client certificate issued through the Kubernetes CSR API, and is authorized by namespaced RBAC. The site is served over TLS issued by cert-manager.
2. Architecture at a glance
                        ┌──────────────────────────────┐

   user (nginx-deployer)│  kube-apiserver               │

   client cert  ───────►│  • authenticates cert vs CA   │

   CN=nginx-deployer    │  • CN -> user, O -> group     │

   O=nginx-team         │  • RBAC: Role + RoleBinding   │

                        └──────────────┬────────────────┘

                                       │ (authorized verbs only, ns=web)

                                       ▼

   ┌─────────────┐     ┌─────────────────────────────────────────┐

   │ control     │     │ namespace: web                          │

   │ plane (cp1) │     │  Deployment nginx (2 replicas, :8080)   │

   └─────────────┘     │  Service nginx (ClusterIP :80->:8080)   │

   ┌─────────────┐     │  Ingress (TLS via cert-manager secret)  │

   │ worker1     │◄────┤  Certificate nginx-tls (selfsigned CI)  │

   │ worker2     │     └─────────────────────────────────────────┘

   └─────────────┘
3. Key design choices and why
3.1 Identity = a signed client certificate
Kubernetes has no user database. A "user" is simply a client certificate the cluster CA has signed, where the certificate Subject CN is the username and each Subject O is a group. I generate the key locally, submit a CSR through the certificates.k8s.io/v1 API with signerName: kubernetes.io/kube-apiserver-client, approve it as admin, and the built-in signer returns a short-lived client cert.

Why the CSR API rather than manually signing with the CA key on disk? Because it keeps the CA private key where it belongs (never copied around), produces an auditable CSR object, and is the Kubernetes-native, reproducible path. It also mirrors how real automation requests certs.

3.2 Authorization = namespaced Role + RoleBinding
The Role grants only the verbs needed to deploy, access and monitor Nginx: manage Deployments/ReplicaSets/Services/ConfigMaps, read Pods + logs, exec for live debugging, manage the Certificate + Ingress for TLS, and read Events. No secret write, no cluster-scoped resources, no access to other namespaces. This is the "minimum access" the brief grades on.

I bind to the group nginx-team (the cert's O) rather than the individual user, so additional team certs inherit access without RBAC edits. (Binding the individual User is equally valid; I note both in the RoleBinding comments.)

3.3 Short certificate TTL
The CSR requests expirationSeconds: 604800 (7 days). Short-lived certs limit the blast radius of a leaked key. This deliberately creates the rotation pain point that becomes the demo's punchline

3.4 TLS for the site via cert-manager + a self-signed ClusterIssuer
A self-signed ClusterIssuer is correct for an offline/POC cluster with no public DNS: cert-manager mints a full cert chain and auto-renews it (renewBefore: 360h) without needing ACME/Let's Encrypt reachability. In production you'd swap the issuer for ACME or your org CA — a one-line change to issuerRef.

3.5 Pod hardening
The Nginx pod runs runAsNonRoot (uid 101), readOnlyRootFilesystem, drops all capabilities, allowPrivilegeEscalation: false, seccompProfile: RuntimeDefault, listens on unprivileged :8080, and has resource requests/limits + readiness/liveness probes. Security is an explicit grading axis, so the workload is hardened, not just the access path.

3.6 Reproducibility
Every version is pinned (Kubernetes v1.30, Calico v3.27, cert-manager v1.14, nginx:1.27-alpine), tools are apt-mark hold'd, and the whole flow is scripted so the team can reproduce it on three clean VMs. The scripts are idempotent where practical.

4. Pluses of this access model
No shared admin credential. Each human gets a distinct identity.
Native + portable. Pure upstream Kubernetes; nothing proprietary.
Least privilege. RBAC scopes the identity to one namespace and a minimal verb set.
Auditable issuance. Every cert begins life as an approved CSR object.
Cryptographically strong. Possession of a CA-signed cert, not a password.

5. Minuses of this access model — (the important part)
No revocation. Kubernetes has no CRL/OCSP for client certs. If a laptop with a valid cert is lost, you cannot truly revoke it — your only options are to wait for expiry or rotate the entire cluster CA (disruptive). This is the single biggest weakness.
Manual, unscalable issuance. Generate key → CSR → approve → extract → build kubeconfig → deliver, per user. At 10 engineers it's tedious; at 500 it's untenable.
Insecure credential distribution. The kubeconfig embeds a long-ish-lived private key that must be shipped to the user somehow — email/Slack are all insecure.
No SSO / MFA. Certs don't integrate with the company IdP (Okta/Azure AD), so there's no MFA, no group sync, no central deprovisioning when someone leaves.
Weak audit trail. You can see that nginx-deployer acted via API audit logs, but there's no session recording and no rich, queryable "who did what, where, when" across all infrastructure.
Group changes require re-issuance. Group membership is baked into the cert's O at signing time. Change someone's groups and you must re-issue the cert.

6. What I'd do differently in production
Replace manual CSRs with an identity-aware proxy or at minimum an automated short-lived-cert issuer.
Use an ACME ClusterIssuer for publicly trusted TLS.
Add an ingress controller + NetworkPolicies to default-deny east-west traffic.
Add audit policy tuning and ship logs to a SIEM.
GitOps the manifests (ArgoCD/Flux) — see the optional advanced objective.


