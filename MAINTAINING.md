# Maintaining this fork

`hyperfocus1337/netbird-helm-chart` is a fork of [`netbirdio/helms`](https://github.com/netbirdio/helms) in GitHub's sense only. `charts/netbird` here is a rewrite for NetBird's combined server (2.x), not a patched copy of upstream's 1.9.0 chart: same path, same chart name, no shared content. Treat that directory as owned code that happens to live in a fork, and the rest of the repo as an upstream mirror we do not edit.

## Do not merge upstream

`git merge upstream/main` is the wrong tool here, and the reason is visible in upstream's history:

- Upstream's `charts/netbird` was last touched functionally on 2025-08-27 (`feat: add annotaions for netbird services`, #12), for netbird 0.46.0. It still deploys the pre-0.62 split management/signal/relay layout with a mandatory external IdP. Every one of its files is either deleted or rewritten here.
- Everything upstream has merged since is the operator mirror: `sync operator charts from upstream (#33, #35, #36, #43, #44, #53)` and `Remove sync operator config Helm chart (#52)`. Those commits touch `charts/kubernetes-operator/` only.
- That mirror does not need upstream either. `.github/workflows/sync-operator-charts.yml` rsyncs straight from [`netbirdio/kubernetes-operator`](https://github.com/netbirdio/kubernetes-operator), the actual source, so routing it through `netbirdio/helms` adds a hop and nothing else.

So a merge from upstream buys the operator chart we already mirror, and risks reviving the 1.x chart the moment upstream touches that path. If upstream ever revives their `netbird` chart, that is not a merge, it is a decision: either retire this fork and use theirs, or keep 2.x and accept the permanent divergence. Do not try to reconcile the two trees.

Upstream stays configured as a read-only remote, for looking:

```sh
git remote add upstream https://github.com/netbirdio/helms.git
git remote set-url --push upstream no_push
git fetch upstream && git log --oneline HEAD..upstream/main -- charts/kubernetes-operator
```

## What actually needs tracking

Neither dependency flows through `netbirdio/helms`. [Renovate](https://docs.renovatebot.com/) watches the two container images and opens PRs; `renovate.json` plus the `# renovate: image=netbirdio/netbird-server` comment on `appVersion` are what it reads.

| Source                                                                                                                                                                                                                           | What it changes here                                                                  | How to notice                                                                                                  |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `netbirdio/netbird-server`                                                                                                                                                                                                       | `appVersion` (the server image tag is empty and follows this)                         | Renovate PR. Tags look like `0.75.0`.                                                                          |
| `netbirdio/dashboard`                                                                                                                                                                                                            | `dashboard.image.tag`                                                                 | Renovate PR. Tags look like `v2.90.7`.                                                                         |
| [`combined/config.yaml.example`](https://github.com/netbirdio/netbird/blob/main/combined/config.yaml.example) and [`getting-started.sh`](https://github.com/netbirdio/netbird/blob/main/infrastructure_files/getting-started.sh) | `server.config` defaults, the dashboard env in `_helpers.tpl`, the Ingress route list | diff them against the chart before merging an `appVersion` PR; they are the reference the chart is modelled on |

Renovate also bumps `Chart.yaml` `version` on those image PRs (patch for a patch tag, minor otherwise) so chart-releaser will publish. Do not automerge: a NetBird release can add `config.yaml` keys or ingress paths that Renovate cannot see.

Before merging an image PR: read the [NetBird release notes](https://github.com/netbirdio/netbird/releases), diff the two upstream files above, adjust `server.config` and the route list if they moved, and update `README.md` and `UPGRADING.md` if anything is breaking. CI already lints, renders every example, and installs into kind.

## Releasing

`.github/workflows/helm.yml` runs [chart-releaser](https://github.com/helm/chart-releaser-action) on a push to `main` that touches `charts/netbird/Chart.yaml`, or on `workflow_dispatch`. It packages the chart, creates a GitHub release named `helm-netbird-v<version>`, and pushes `index.yaml` to `gh-pages`, which GitHub Pages serves at `https://hyperfocus1337.github.io/netbird-helm-chart`.

Four consequences worth remembering:

- **Any template change needs a `Chart.yaml` version bump.** chart-releaser skips versions it has already released, so editing a published version in place changes nothing for consumers: they keep pulling the old package.
- **A commit that changes only templates publishes nothing at all**, since the workflow's path filter is `Chart.yaml`. Bump the version in the same commit, or run the workflow by hand.
- **`gh-pages` has to exist first.** chart-releaser pushes `index.yaml` to that branch and does not create it: `git switch --orphan gh-pages && git commit --allow-empty -m "init" && git push -u origin gh-pages`.
- **Pages has to be enabled once**, in Settings, pointed at `gh-pages`. Until then `helm repo add` against the Pages URL 404s.

Actions is disabled by default in a fork, so none of this runs until it is enabled once on the repo's Actions tab.

There are no tags in this repo yet, so `helm-netbird-v2.0.0` will be the first release, and upstream's 1.x was never published from here.

## Branching

Commit to `main`. One maintainer, one consumer (the k3s node), and no upstream to keep a clean history for, so a branch-and-PR dance buys nothing except for Renovate, whose image PRs need the bump ritual above before merge. Two fork-specific footguns to know about:

- `gh pr create` in a fork defaults its base to the **parent** repo. If you do open a PR, pass `--repo hyperfocus1337/netbird-helm-chart`, or run `gh repo set-default hyperfocus1337/netbird-helm-chart` once in the clone.
- Issues, stars and the fork banner all point at `netbirdio/helms`. If the divergence is permanent, ask GitHub Support to detach the fork; it costs nothing to leave attached, but detaching removes the wrong-base risk entirely.

Consumers pin a chart version, not a branch, so an unreleased `main` never reaches a cluster by accident.

## The operator charts

Deleted. `charts/kubernetes-operator`, `charts/netbird-operator-config`, their sync and test workflows and the root `examples/` values that came with them are gone: nothing consumed them here, and this repo has no business publishing an operator chart nobody audits. The sync workflow was also a liability, since it runs every 6 hours and needs a `CHART_SYNC_TOKEN` secret that **a fork does not inherit**, so it would have failed on cron from the moment Actions was enabled.

Nothing is lost. Upstream publishes the operator chart themselves, from [`netbirdio/kubernetes-operator`](https://github.com/netbirdio/kubernetes-operator), which is where the sync pulled it from anyway.

## Consumer

The chart is consumed by `workloads/netbird/helmchart.yaml` in the `ubuntu-desktop-workloads` repo, through a k3s `HelmChart` resource pointing at the Pages URL. Its `docs/netbird.md` documents the deployment side; this file documents the chart side.
