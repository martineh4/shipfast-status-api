# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## What this is

A reference GitOps deployment: a stdlib-only Python status API (`app/`), packaged by `Dockerfile`, published to `ghcr.io/martineh4/shipfast-status-api`, and deployed by Argo CD from `deploy/overlays/dev` on `main`. See `README.md` for the end-to-end flow.

## Ground rules

- **Never change the cluster imperatively.** No `kubectl apply/edit/scale/delete` against `status-api-*` namespaces. Argo CD has `selfHeal` on and will revert it. Every change is a git change merged by PR. The only exception is the one-time `scripts/bootstrap-argocd.sh`.
- **`main` is protected.** Work on a branch, open a PR, and wait for the `test`, `manifests`, and `e2e` checks. Don't try to push to `main`. Don't bypass hooks or checks.
- **Don't hand-edit `newTag:`** in `deploy/overlays/*/kustomization.yaml` for normal releases. `release.yaml` sets it via a bot PR. Hand edits are only for a rollback or promotion PR, and must use an existing `sha-<7 chars>` tag from GHCR, never `latest` or a mutable tag.
- **Keep the app dependency-free.** Standard library only, so there's no `requirements.txt`. The runtime image is distroless Python (no shell, no pip), so a dependency would also need a build stage that installs it into the image. If a dependency becomes truly necessary, add pinned requirements and that stage in the same PR.
- **Keep the container hardening intact:** non-root UID 10001, `readOnlyRootFilesystem`, all capabilities dropped, `RuntimeDefault` seccomp. The app must not write to disk. The runtime image is `gcr.io/distroless/python3-debian13` (Python 3.13). Keep the `test` stage, the CI `test` job, and the runtime image on the same Python minor version. There's no shell in the image, so `HEALTHCHECK` and `ENTRYPOINT` must use exec form.
- Image name `ghcr.io/martineh4/shipfast-status-api` and repo URL `https://github.com/martineh4/shipfast-status-api.git` appear in the Dockerfile label, `deploy/base/deployment.yaml`, `deploy/overlays/dev/kustomization.yaml`, `argocd/*.yaml`, and `ci.yaml`. If you rename, update all of them together.

## Commands

```bash
# unit tests (run from app/)
cd app && python -m unittest -v

# run locally
cd app && python status_api.py          # :8080

# render what Argo CD will apply
kubectl kustomize deploy/overlays/dev

# validate like CI does (needs kubeconform)
kubectl kustomize deploy/overlays/dev | kubeconform -strict -summary -
```

## Making changes

- **API change:** edit `app/status_api.py` and add or adjust tests in `app/test_status_api.py`. The `e2e` job asserts `/status` returns `status == "ok"`, `environment == "dev"`, and `commit == <PR head SHA>`. Keep those fields, or update the assertion in `ci.yaml` in the same PR.
- **Manifest change:** edit `deploy/base/` (shared) or `deploy/overlays/<env>/` (per-env). Check the result with `kubectl kustomize`. Label selectors are immutable on Deployments, so don't change the `labels.pairs` in `deploy/base/kustomization.yaml` without planning a replace.
- **Argo CD change:** `argocd/*.yaml` is applied only by the bootstrap script, not by Argo CD itself. Merging a change there doesn't apply it to a running cluster until someone re-applies it. Call this out in the PR description.
- **Workflow change:** the `e2e` job is the real proof that the GitOps path works. Don't weaken it (e.g. skipping the self-heal step) to get a PR green.

## Environment notes

- The local dev machine is Windows. Docker Desktop there currently has no Linux engine (WSL isn't installed), so image builds and kind clusters run in GitHub Actions. Don't assume `docker build` works locally.
- Git Bash is available. Scripts in `scripts/` are bash and target CI runners and Linux/macOS shells.
- In GitHub Codespaces, a stale iptables-legacy firewall drops traffic from kind's Docker network, so kind nodes can't pull images. `.devcontainer/devcontainer.json` runs `scripts/codespace-allow-docker-bridges.sh` on every start to fix this. Run it by hand if image pulls in kind time out with DNS errors.
