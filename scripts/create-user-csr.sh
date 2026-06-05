set -euo pipefail

USER="nginx-deployer"
GROUP="nginx-team"
NAMESPACE="web"
WORKDIR="./user-certs"
APISERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "[1/7] Generating a 2048-bit private key for ${USER}..."
openssl genrsa -out "${USER}.key" 2048

echo "[2/7] Creating a CSR with CN=${USER}, O=${GROUP}..."
openssl req -new -key "${USER}.key" -out "${USER}.csr" -subj "/CN=${USER}/O=${GROUP}"

echo "[3/7] Submitting the CSR to the Kubernetes API..."
CSR_B64="$(base64 < "${USER}.csr" | tr -d '\n')"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER}
spec:
  request: ${CSR_B64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800   # 7 days — deliberately short; see DESIGN.md tradeoffs
  usages:
    - client auth
EOF

echo "[4/7] Approving the CSR (this is the privileged admin action)..."
kubectl certificate approve "${USER}"

echo "[5/7] Extracting the signed client certificate..."
kubectl get csr "${USER}" -o jsonpath='{.status.certificate}' | base64 -d > "${USER}.crt"

echo "[6/7] Building a kubeconfig for ${USER}..."
kubectl config set-cluster kubernetes \
  --server="${APISERVER}" \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig="${USER}.kubeconfig"

kubectl config set-credentials "${USER}" \
  --client-certificate="${USER}.crt" \
  --client-key="${USER}.key" \
  --embed-certs=true \
  --kubeconfig="${USER}.kubeconfig"

kubectl config set-context "${USER}@kubernetes" \
  --cluster=kubernetes \
  --namespace="${NAMESPACE}" \
  --user="${USER}" \
  --kubeconfig="${USER}.kubeconfig"

kubectl config use-context "${USER}@kubernetes" --kubeconfig="${USER}.kubeconfig"

echo "[7/7] Done."
echo
echo "Test the new identity (should be DENIED at cluster scope, ALLOWED in '${NAMESPACE}'):"
echo "  kubectl --kubeconfig=${WORKDIR}/${USER}.kubeconfig get nodes          # expect: Forbidden"
echo "  kubectl --kubeconfig=${WORKDIR}/${USER}.kubeconfig get pods -n ${NAMESPACE}   # expect: OK"
echo
echo "Confirm the identity the API server sees:"
echo "  kubectl --kubeconfig=${WORKDIR}/${USER}.kubeconfig auth whoami"
