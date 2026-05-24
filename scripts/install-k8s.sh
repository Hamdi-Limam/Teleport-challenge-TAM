#!/usr/bin/env bash
# 01-install-k8s.sh — install pinned kubelet, kubeadm, kubectl (run on ALL nodes as root)
set -euo pipefail

K8S_MINOR="v1.30"   # pin the minor; patch floats within it then we hold

echo "[1/4] Installing apt prerequisites…"
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg

echo "[2/4] Adding the Kubernetes ${K8S_MINOR} apt repository…"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list

echo "[3/4] Installing kubelet, kubeadm, kubectl…"
apt-get update -y
apt-get install -y kubelet kubeadm kubectl

echo "[4/4] Holding versions so 'apt upgrade' can't skew the cluster…"
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

kubeadm version
echo "OK: tools installed and held. Control plane: run init-control-plane.sh."
