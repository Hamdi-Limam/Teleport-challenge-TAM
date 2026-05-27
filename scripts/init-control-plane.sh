#!/usr/bin/env bash
# init-control-plane.sh — run on the CONTROL PLANE node only, as root.
set -euo pipefail

POD_CIDR="192.168.0.0/16"   # Calico's default
CALICO_VER="v3.27.3"

echo "[1/4] Running kubeadm init (pod CIDR ${POD_CIDR})…"
kubeadm init --pod-network-cidr="${POD_CIDR}" | tee /root/kubeadm-init.log

echo "[2/4] Wiring up kubectl for the invoking sudo user…"
TARGET_HOME=$HOME
mkdir -p "${TARGET_HOME}/.kube"
cp -f /etc/kubernetes/admin.conf "${TARGET_HOME}/.kube/config"
chown "$(id -u "${SUDO_USER:-root}")":"$(id -g "${SUDO_USER:-root}")" "${TARGET_HOME}/.kube/config"
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "[3/4] Installing Calico ${CALICO_VER} CNI…"
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VER}/manifests/calico.yaml"

echo "[4/4] Waiting for the control-plane node to become Ready…"
kubectl wait --for=condition=Ready node --all --timeout=180s || true
kubectl get nodes -o wide

echo
echo ">>> Copy the join command below and run it on each worker (as root): <<<"
grep -A1 "kubeadm join" /root/kubeadm-init.log | tail -n2
