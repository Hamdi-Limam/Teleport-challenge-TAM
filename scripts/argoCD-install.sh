# as admin on cp1
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait for it to be ready
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s

kubectl get pods -n argocd    # all should be Running

kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'

kubectl get svc argocd-server -n argocd # note the HTTPS NodePort