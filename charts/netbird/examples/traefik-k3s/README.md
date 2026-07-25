# Traefik on k3s

```sh
helm install netbird netbird/netbird -n netbird --create-namespace -f values.yaml
```

Assumes k3s' bundled Traefik has an ACME `certResolver` named `letsencrypt` and that UDP 3478 is open in the node's firewall.

STUN uses `hostPort`, not a Service. k3s' ServiceLB masquerades the traffic it forwards, so the server would see the load balancer as the source and reply to every peer with that address, which defeats the point of STUN. `externalTrafficPolicy: Local` does not change this: with it, klipper-lb DNATs to the node's own address and still ends its nat chain with `-j MASQUERADE`.

Long-lived connections also need Traefik's entrypoint timeouts off, or the management gRPC stream and the relay websocket are cut after 60s:

```sh
--entrypoints.websecure.transport.respondingTimeouts.readTimeout=0
--entrypoints.websecure.transport.respondingTimeouts.idleTimeout=0
```

The example brings its own `config.yaml` Secret so that the relay auth secret and the store encryption key never end up in a values file. Render it however you like, for example:

```yaml
server:
  listenAddress: ":80"
  exposedAddress: "https://netbird.example.com:443"
  stunPorts: [3478]
  metricsPort: 9090
  healthcheckAddress: ":9000"
  logLevel: "info"
  logFile: "console"
  authSecret: "<openssl rand -base64 32>"
  dataDir: "/var/lib/netbird"
  auth:
    issuer: "https://netbird.example.com/oauth2"
    localAuthDisabled: false
    signKeyRefreshEnabled: true
    dashboardRedirectURIs:
      - "https://netbird.example.com/nb-auth"
      - "https://netbird.example.com/nb-silent-auth"
    cliRedirectURIs:
      - "http://localhost:53000/"
  reverseProxy:
    trustedHTTPProxies:
      - "10.42.0.0/16"
  store:
    engine: "sqlite"
    encryptionKey: "<openssl rand -base64 32>"
```

Changing that Secret does not restart the server on its own:

```sh
kubectl -n netbird rollout restart deploy/netbird-server
```
