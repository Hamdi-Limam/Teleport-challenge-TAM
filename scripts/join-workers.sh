
# kubeadm init already prints a join command (see 02 output). If the token
# expired (they last 24h), regenerate one FROM THE CONTROL PLANE with:
#   kubeadm token create --print-join-command
#
# Then run THAT output on each worker as root. This script just regenerates it.
set -euo pipefail
echo "Run this on the CONTROL PLANE to mint a fresh join command:"
echo
kubeadm token create --print-join-command
