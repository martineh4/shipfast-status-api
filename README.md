# shipfast-status-api

ShipFast Logistics Technology's internal status-check API. It's a small reference service that shows the platform team's **GitOps delivery workflow**: the app is containerized, published to GitHub Container Registry, and deployed to Kubernetes by **Argo CD**. Every change to what runs in the cluster lands through a pull request. Nobody runs `kubectl` against the workload by hand.

## How a change reaches the cluster

```
 developer PR ──► ci: test · manifests · e2e ──► merge to main
                                                     │
                                                     ▼
                                   release: build + push ghcr.io/…:sha-abc1234
                                                     │
                                                     ▼
                         bot PR "deploy(dev): status-api sha-abc1234"
                         (edits deploy/overlays/dev/kustomization.yaml)
                                                     │  ci runs again
                                                     ▼
                                             review + merge
                                                     │
                                                     ▼
                     Argo CD sees the new commit on main ──► rolling update
```

1. **Code change.** Open a PR. CI runs three required checks (described below). Merge when they're green.
2. **Image build.** When code under `app/` or the `Dockerfile` lands on `main`, `release.yaml` builds the image and pushes it to `ghcr.io/martineh4/shipfast-status-api:sha-<short-sha>`. Deploys always use the immutable `sha-<short-sha>` tag, never `latest`. The image is also tagged `main` (mutable, latest build of `main`) for convenience; never deploy that tag. The version and commit are also stored in the image as OCI labels.
3. **Deploy PR.** The same workflow opens a PR that changes only the `newTag:` line in `deploy/overlays/dev/kustomization.yaml`. This PR is the deployment approval. GitHub may hold CI on bot-opened PRs until a maintainer clicks **Approve and run workflows** on the PR (contributor approval policy). After that, the required checks run as usual.
4. **Sync.** After the deploy PR merges, Argo CD detects the new commit on `main` (it polls every ~3 minutes by default) and rolls the Deployment out with zero downtime (`maxUnavailable: 0`).
5. **Drift control.** The Application has `selfHeal: true` and `prune: true`. Manual `kubectl edit`, `scale`, or `delete` changes are reverted to what git says. Resources removed from git are removed from the cluster.

**Rollback** is `git revert` of the deploy PR's merge commit, merged through another PR. Argo CD then rolls back to the previous tag.

## CI checks (`.github/workflows/ci.yaml`)

| Job | What it proves |
|---|---|
| `test` | API unit tests pass (`python -m unittest`). |
| `manifests` | The dev overlay renders with Kustomize, and every Kubernetes and Argo CD object passes strict `kubeconform` schema validation. |
| `e2e` | Creates a throwaway **kind** cluster, installs **Argo CD** with the same bootstrap script used for real clusters, registers the real `Application` pinned to the PR's commit, waits for **Synced + Healthy**, calls `/status` through the Service, then runs `kubectl scale --replicas=0` and checks that Argo CD **self-heals** it back to 2. |

All three are required status checks on `main`, and direct pushes to `main` are blocked, admins included.

## Repository layout

```
app/                      status_api.py (stdlib-only HTTP service) + unit tests
Dockerfile                multi-stage: tests on python:3.13-slim, runs on distroless Python as UID 10001
deploy/
  base/                   Deployment + Service (probes, limits, restricted securityContext)
  overlays/dev/           namespace, APP_ENV config, and the image tag Argo CD deploys
argocd/
  project.yaml            AppProject: this repo only, status-api-* namespaces only
  status-api-dev.yaml     Application: tracks main:deploy/overlays/dev, auto-sync + self-heal
scripts/
  bootstrap-argocd.sh     one-time cluster bootstrap (install Argo CD, register the app)
.github/workflows/
  ci.yaml                 PR gate: test, manifests, e2e
  release.yaml            build + push image, open deploy PR
```

## API

| Endpoint | Purpose |
|---|---|
| `GET /` | Service banner and list of endpoints |
| `GET /healthz` | Liveness probe |
| `GET /readyz` | Readiness probe |
| `GET /status` | `service`, `status`, `version` (image tag), `commit`, `environment`, `hostname`, `uptime_seconds` |

Configuration comes from environment variables: `PORT` (default `8080`) and `APP_ENV`, which comes from the overlay's ConfigMap. `APP_VERSION` and `GIT_COMMIT` are baked into the image at build time.

## Run locally

```bash
cd app
python -m unittest -v       # tests
python status_api.py        # serves on :8080
curl localhost:8080/status
```

With Docker:

```bash
docker build -t status-api:local .
docker run --rm -p 8080:8080 status-api:local
```

## Connect the cluster (one-time bootstrap)

You need a kubeconfig for the cluster your team provisioned with OpenTofu. For example, take it from that stack's outputs, or use `aws eks update-kubeconfig …` / `az aks get-credentials …` / `gcloud container clusters get-credentials …`. Then run:

```bash
./scripts/bootstrap-argocd.sh
```

The script installs Argo CD (pinned to `v3.5.4`, override with `ARGOCD_VERSION`), applies `argocd/project.yaml` and `argocd/status-api-dev.yaml`, and waits until the app is Synced and Healthy. It also prints the commands to open the Argo CD UI and call the API. **This is the only time `kubectl apply` is used.** After this, every change goes through git.

> Longer term, the Argo CD install itself should move into the cluster's OpenTofu stack (`helm_release` for the `argo-cd` chart, plus the Application as a `kubernetes_manifest`), so new clusters come up already wired to git.

The repo and the GHCR package are public, so the cluster needs no git or registry credentials. If either becomes private, add an Argo CD repository secret and an `imagePullSecret`.

## Demo script for sprint review

1. Show the Argo CD UI: `status-api-dev` is Synced and Healthy, and its tree shows the Deployment, ReplicaSet, Pods, and Service.
2. Open a PR that changes something visible, such as a field in `/status`. Walk through the three CI checks, including the e2e Argo CD sync in kind.
3. Merge. Show the `release` run pushing `sha-…` to GHCR and opening the deploy PR.
4. Merge the deploy PR. In Argo CD, watch the rolling update (click **Refresh** to skip the poll interval). `curl /status` now reports the new `version` and `commit`.
5. Try drift: `kubectl -n status-api-dev scale deploy/status-api --replicas=5`. Argo CD marks it OutOfSync and puts it back to 2.

## Adding an environment

Copy `deploy/overlays/dev` to `deploy/overlays/<env>`, set `namespace`, `APP_ENV`, and `newTag`, then add `argocd/status-api-<env>.yaml` pointing at the new path. Promotion to that environment is a PR that copies the tag from dev to the new overlay.
