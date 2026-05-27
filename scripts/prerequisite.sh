#!/usr/bin/env bash
# prereqs.sh — OS preparation for a kubeadm node (run on ALL nodes as root)
set -euo pipefail

echo "[1/5] Disabling swap (kubelet requires this)…"
swapoff -a
# make it permanent across reboots
sed -i.bak '/\bswap\b/s/^/#/' /etc/fstab || true

echo "[2/5] Loading required kernel modules…"
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "[3/5] Setting sysctl params for Kubernetes networking…"
cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo "[4/5] Installing containerd…"
apt-get update -y
apt-get install -y containerd

echo "[5/5] Configuring containerd to use the systemd cgroup driver…"
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
# kubelet and the runtime MUST agree on the cgroup driver; systemd is correct for Ubuntu
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "OK: node prepped. Run 01-install-k8s.sh next."
