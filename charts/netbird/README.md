# netbird

![Version: 2.0.0](https://img.shields.io/badge/Version-2.0.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.75.0](https://img.shields.io/badge/AppVersion-0.75.0-informational?style=flat-square)

Self-hosted [NetBird](https://netbird.io) control plane for Kubernetes. Fork of [netbirdio/helms](https://github.com/netbirdio/helms), rewritten for the combined server.

Chart 2.x deploys NetBird's **combined server**: one container running management, signal, relay, STUN and the embedded identity provider, configured by a single `config.yaml`. No external identity provider is required, and no coturn. Chart 1.x (netbird 0.46.0, separate management/signal/relay containers, mandatory external IdP) is a different architecture, see [UPGRADING.md](./UPGRADING.md).

Modelled on the upstream compose deployment that [`getting-started.sh`](https://github.com/netbirdio/netbird/blob/main/infrastructure_files/getting-started.sh) generates, so the ports, routes and config keys match what NetBird documents and supports.

This chart is maintained independently of the repository it was forked from: see [MAINTAINING.md](https://github.com/hyperfocus1337/helms/blob/main/MAINTAINING.md) for how it tracks NetBird releases and why upstream is never merged.

## What it deploys

| Object                             | Purpose                                                                   |
| ---------------------------------- | ------------------------------------------------------------------------- |
| `Deployment` `<release>-server`    | `netbirdio/netbird-server`: management, signal, relay, STUN, embedded IdP |
| `Deployment` `<release>-dashboard` | `netbirdio/dashboard`: the web UI                                         |
| `Secret` `<release>-server-config` | the rendered `config.yaml` (or bring your own)                            |
| `Service` `<release>-server`       | HTTP/1.1: `/api`, `/oauth2`, `/relay`, `/ws-proxy/`                       |
| `Service` `<release>-server-h2c`   | same pods over h2c, for the gRPC routes                                   |
| `Service` `<release>-stun`         | UDP 3478, `LoadBalancer` or `NodePort`, never proxied, optional           |
| `PersistentVolumeClaim`            | `store.db`, `events.db`, `idp.db`, GeoLite databases                      |
| `Ingress`                          | all routes on one host, gRPC to the h2c Service                           |
| `Ingress` `<release>-grpc`         | optional, only with `ingress.grpcAnnotations` set                         |
| `ServiceMonitor`                   | optional, scrapes `/metrics` on 9090                                      |

## Prerequisites

- Kubernetes 1.19+, Helm 3.x
- A public hostname resolving to the ingress, e.g. `netbird.example.com`
- TCP 443 reachable, plus **UDP 3478** reachable for STUN. STUN cannot be proxied, and it must see the peer's real source address, so expose it with `server.stun.hostPort` on any cluster whose load balancer masquerades (k3s ServiceLB does) and with `server.stun.service` on one that does not
- A `ReadWriteOnce` StorageClass, unless you point the store at an external database

## Install

```sh
helm repo add netbird https://hyperfocus1337.github.io/helms
helm install netbird netbird/netbird \
  -n netbird --create-namespace \
  --set domain=netbird.example.com \
  --set server.config.authSecret="$(openssl rand -base64 32)" \
  --set server.config.store.encryptionKey="$(openssl rand -base64 32)" \
  --set ingress.enabled=true --set ingress.className=traefik
```

Then open `https://netbird.example.com`, which redirects to `/setup`, and create the owner account. That page stops working once an account exists. Set `server.config.auth.owner.email` and `.password` instead if you want the account created unattended on first start.

Join a peer:

```sh
netbird up --management-url https://netbird.example.com
```

Ready-made values live in [`examples/`](./examples): `traefik-k3s`, `nginx-ingress`, `external-idp`.

## Configuration

Everything under `server.config` is written into `config.yaml` verbatim under `server:`, so any key [upstream documents](https://docs.netbird.io/selfhosted/maintenance/configuration-files) works even when this chart does not name it. Use `server.config.extra` for the rest (`activityStore`, `authStore`, `stuns`, `relays`, `signalUri`, `tls`, `mfaSession*`). The chart fills in the hostname-derived values it can infer:

| Key                                        | Default when empty                                            |
| ------------------------------------------ | ------------------------------------------------------------- |
| `server.config.exposedAddress`             | `https://{domain}:443`                                        |
| `server.config.auth.issuer`                | `https://{domain}/oauth2` (the embedded IdP)                  |
| `server.config.auth.dashboardRedirectURIs` | `https://{domain}/nb-auth`, `https://{domain}/nb-silent-auth` |
| `ingress.host`                             | `{domain}`                                                    |
| dashboard `AUTH_AUTHORITY`                 | follows `server.config.auth.issuer`                           |

See [values.yaml](./values.yaml) for the full list; every parameter is annotated.

`server.ports.*` are what the container ports, Services and probes use, so they have to match `config.listenAddress`, `config.stunPorts`, `config.metricsPort` and `config.healthcheckAddress`, which the defaults do. `config.dataDir` is where the volume is mounted, so it matters even when the config comes from `existingSecret`. The server binds `:80`, a privileged port: the default `server.securityContext` drops every capability and adds back only `NET_BIND_SERVICE`, without which the process exits with `listen tcp :80: bind: permission denied` even though it runs as root.

### Secrets

`config.yaml` has to contain `authSecret` and `store.encryptionKey`: the server parses the file as plain YAML with no environment substitution, so those cannot be moved into env vars. The chart therefore renders it into a **Secret**. To keep them out of your values files entirely, create the Secret yourself and reference it:

```yaml
server:
  config:
    create: false
    existingSecret: netbird-config
    existingSecretKey: config.yaml # default
```

Back up `store.encryptionKey`. Local user records are encrypted with it and cannot be recovered if it is lost or changed.

With `existingSecret`, changes to the Secret do not roll the pod, since the chart cannot checksum content it does not render:

```sh
kubectl -n netbird rollout restart deploy/netbird-server
```

### Routing

The path split is dictated by NetBird, not by this chart ([docs](https://docs.netbird.io/selfhosted/external-reverse-proxy)):

| Path                                                                                             | Backend       | Why                            |
| ------------------------------------------------------------------------------------------------ | ------------- | ------------------------------ |
| `/management.ManagementService/`, `/management.ProxyService/`, `/signalexchange.SignalExchange/` | h2c Service   | gRPC needs HTTP/2 cleartext    |
| `/api`, `/oauth2`, `/relay`, `/ws-proxy/`                                                        | plain Service | websockets break over h2c      |
| `/`                                                                                              | dashboard     | catch-all, longest prefix wins |

`server.serviceH2c.annotations` carries the Traefik annotation by default, which is why one Ingress is enough there: the scheme comes off the Service. Controllers that read the backend protocol off the Ingress instead, ingress-nginx among them, would apply it to the websocket routes too and break them, so set `ingress.grpcAnnotations` and the gRPC paths move to a second Ingress `<release>-grpc` carrying only those annotations (see the `nginx-ingress` example).

The management gRPC stream and the relay websocket stay open indefinitely, so the ingress controller must not time them out. Traefik cuts a request at `readTimeout` (60s) and an idle connection at `idleTimeout` (180s) by default, so set both to 0 on the entrypoint, which is what upstream's compose deployment does:

```sh
--entrypoints.websecure.transport.respondingTimeouts.readTimeout=0
--entrypoints.websecure.transport.respondingTimeouts.idleTimeout=0
```

On ingress-nginx the equivalents are the `proxy-read-timeout` / `proxy-send-timeout` annotations in the `nginx-ingress` example.

### Scaling

`server.replicaCount` stays at 1 unless the store, signal and relay all live outside the pod: sqlite and the embedded relay are single-instance. Point `server.config.store` at postgres/mysql and move signal and relay out with `server.config.extra.signalUri` / `.relays`, as described in [Scaling your self-hosted deployment](https://docs.netbird.io/selfhosted/maintenance/scaling/scaling-your-self-hosted-deployment).

### Admin CLI

The [admin CLI](https://docs.netbird.io/selfhosted/maintenance/admin-cli) (passwords, MFA, proxy tokens) runs inside the server pod:

```sh
kubectl -n netbird exec -it deploy/netbird-server -- \
  /go/bin/netbird-server --config /etc/netbird/config.yaml admin --help
```

## Uninstall

```sh
helm uninstall netbird -n netbird
```

The PVC is left behind by Helm; delete it explicitly to discard peers, users and keys.

## References

- [Self-hosting quickstart](https://docs.netbird.io/selfhosted/selfhosted-quickstart)
- [Configuration file reference](https://docs.netbird.io/selfhosted/maintenance/configuration-files)
- [Environment variables](https://docs.netbird.io/selfhosted/environment-variables)
- [External reverse proxy](https://docs.netbird.io/selfhosted/external-reverse-proxy)
- [Local user management](https://docs.netbird.io/selfhosted/identity-providers/local)
- [Identity providers](https://docs.netbird.io/selfhosted/identity-providers)
- [Observability of the combined server](https://docs.netbird.io/selfhosted/observability/combined)
- [Backup](https://docs.netbird.io/selfhosted/maintenance/backup) and [upgrade](https://docs.netbird.io/selfhosted/maintenance/upgrade)
- [`combined/config.yaml.example`](https://github.com/netbirdio/netbird/blob/main/combined/config.yaml.example)
