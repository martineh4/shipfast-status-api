#!/usr/bin/env bash
# One-time cluster bootstrap: install Argo CD and register the status-api app.
# This is the ONLY step that uses kubectl apply directly. After it runs, every
# change to the workload is delivered by merging a pull request.
#
# Usage: KUBECONFIG=path/to/kubeconfig ./scripts/bootstrap-argocd.sh [--install-only]
#   --install-only  install Argo CD but do not register the app (used by CI e2e,
#                   which registers a commit-pinned copy of the Application instead)
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.4}"
cd "$(dirname "$0")/.."

echo "==> Target cluster: $(kubectl config current-context)"
kubectl cluster-info >/dev/null

echo "==> Installing Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side: Argo CD's CRDs exceed the client-side annotation size limit.
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

if [[ "${1:-}" == "--install-only" ]]; then
  echo "==> Argo CD installed (--install-only: skipping app registration)"
  exit 0
fi

echo "==> Registering AppProject and Application"
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/status-api-dev.yaml

echo "==> Waiting for status-api-dev to become Synced + Healthy"
kubectl -n argocd wait application/status-api-dev \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s
kubectl -n argocd wait application/status-api-dev \
  --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s

cat <<MSG

Done. Argo CD UI:
  kubectl -n argocd port-forward svc/argocd-server 8443:443
  https://localhost:8443  (user: admin)
  password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

Status API:
  kubectl -n status-api-dev port-forward svc/status-api 8080:80
  curl http://localhost:8080/status
MSG
