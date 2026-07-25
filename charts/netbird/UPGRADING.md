# Upgrading

## 1.x to 2.0.0

Chart 2.0.0 follows NetBird's move to the combined server. It is a different deployment, not a drop-in upgrade.

| 1.x (netbird 0.46.0)                              | 2.0.0 (netbird 0.75.0)               |
| ------------------------------------------------- | ------------------------------------ |
| `management`, `signal`, `relay` Deployments       | one `server` Deployment              |
| `management.json` in a ConfigMap                  | `config.yaml` in a Secret            |
| external IdP required (Zitadel, Keycloak, Auth0…) | embedded IdP; external is optional   |
| coturn/STUN out of scope                          | STUN built in, exposed on UDP 3478   |
| `management.*`, `signal.*`, `relay.*` values      | `server.*`                           |
| three Ingresses                                   | one Ingress with the full route list |

Upstream supports migrating existing data, but only for deployments that already use the embedded IdP: [Migrate to the combined container](https://docs.netbird.io/selfhosted/migration/combined-container). Read that first if you have peers you care about.

Rough path for a 1.x release, with peers preserved:

1. Back up the management PVC and note the `DataStoreEncryptionKey` from `management.json`.
2. Get onto the embedded IdP while still on 1.x if you are on an external provider, or accept that users are recreated: [external to embedded IdP](https://docs.netbird.io/selfhosted/migration/external-to-embedded-idp).
3. Write a `config.yaml` (see [values.yaml](./values.yaml) or the chart README) that reuses the same `store.encryptionKey`, and the same relay secret as `Relay.Secret`.
4. `helm upgrade` to 2.0.0 with `server.persistence.existingClaim` pointing at the old management PVC, so `store.db` is picked up in place.
5. Open UDP 3478 in your firewall, then watch `kubectl logs` and reconnect a peer with `netbird down && netbird up`.

Starting fresh is markedly simpler: install 2.0.0 into a new namespace and re-enrol peers.
