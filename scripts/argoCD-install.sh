# as admin on cp1
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait for it to be ready
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s

kubectl get pods -n argocd    # all should be Running

kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'

kubectl get svc argocd-server -n argocd # note the HTTPS NodePort and use it to access the UI

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-username>/teleport-k8s-challenge.git # replace with your fork
    targetRevision: main
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: web
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "ssh -i "cpl.pem" -L 8080:127.0.0.1:8080 ubuntu@ec2-98-84-27-234.compute-1.amazonaws.com"
echo "kubectl port-forward --address 0.0.0.0 svc/argocd-server -n argocd 8080:443"