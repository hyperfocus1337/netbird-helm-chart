# netbird-helm-chart

Helm chart for a self-hosted [NetBird](https://netbird.io) control plane on Kubernetes.

`charts/netbird` deploys NetBird's combined server: one container running management, signal, relay, STUN and the embedded identity provider, plus the dashboard.

## Documentation

| File                                                       | Contents                                                                  |
| ---------------------------------------------------------- | ------------------------------------------------------------------------- |
| [charts/netbird/README.md](charts/netbird/README.md)       | install, objects deployed, prerequisites, configuration, secrets, routing |
| [charts/netbird/values.yaml](charts/netbird/values.yaml)   | every parameter, annotated                                                |
| [charts/netbird/examples/](charts/netbird/examples)        | ready-made values per ingress controller                                  |
| [charts/netbird/UPGRADING.md](charts/netbird/UPGRADING.md) | 1.x to 2.x migration                                                      |
| [MAINTAINING.md](MAINTAINING.md)                           | how this fork tracks NetBird releases and why upstream is never merged    |

## License

[BSD 3-Clause](LICENSE). Fork of [netbirdio/helms](https://github.com/netbirdio/helms), rewritten for the combined server.
