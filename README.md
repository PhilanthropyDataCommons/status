# status
Tooling for monitoring and reporting on Philanthropy Data Commons (PDC) service uptime, created in response to [PDC Meta issue 174](https://github.com/PhilanthropyDataCommons/meta/issues/174). As of 2026/09 this is very much WIP. 

This repo defines two environments — `test` and `prod` — each running [Gatus](https://github.com/TwiN/gatus) behind [Caddy](https://caddyserver.com/) on the `pdc-status-test.opentechstrategies.com` and `pdc-status-prod.opentechstrategies.com` servers, deployed via GitHub Actions.

## How it works

Each environment (`environments/test/`, `environments/prod/`) is a self-contained Docker Compose stack with two services:

- **gatus** — polls a list of PDC endpoints on a fixed interval, stores results in a local SQLite database, serves a status page on port 8080, and posts an alert to Zulip whenever an endpoint's status changes.
- **caddy** — reverse-proxies HTTPS traffic (ports 80/443) for the environment's domains to the `gatus` container, handling TLS automatically.

Both services share a private `web` Docker network so Caddy can reach Gatus by container name. Config for each environment lives entirely in its directory:


| File | Purpose |
| ---  | --- |
| `compose.yaml` | Defines `gatus` and `caddy` services, volumes, and network |
| `config.yaml` | Gatus config: storage, alerting webhook, and the list of monitored endpoints |
| `Caddyfile` | Domains this environment's Caddy should terminate TLS for and proxy to Gatus |
| `versions.env` | Pinned `GATUS_VERSION` / `CADDY_VERSION` image tags |
| `.env` (not committed) | Secrets written at deploy time (`ZULIP_BASIC_AUTH`, `SSH_KEY`) |

### What's monitored

Both environments watch the same set of PDC services:

https://philanthropydatacommons.org - "PDC main site"
https://api.philanthropydatacommons.org - "PDC API"
https://app.philanthropydatacommons.org - "PDC App"
https://admin.philanthropydatacommons.org - "PDC Admin"
https://exchange.philanthropydatacommons.org - "PDC Exchange"
https://auth.philanthropydatacommons.org - "PDC Keycloak"
https://auth.test.philanthropydatacommons.org - "PDC Keycloak Test"
pdc-utilities.opentechstrategies.com - "PDC utilities server"

HTTP endpoints expect a `200` status. The `pdc-utilities` server is currently checked for ping/ICMP connectivity instead, since it isn't hosting a web service.

### Alerting

Gatus is configured with a `custom` alert type that POSTs to the OTS Zulip instance (`chat.opentechstrategies.com`) using Basic Auth, sending a message whenever an endpoint's status changes (either up or down). 

### Status pages

Each environment's Caddyfile lists the hostnames Caddy will accept and proxy to Gatus, giving each monitored service (and the environment as a whole) its own status page URL, e.g. `status.philanthropydatacommons.org`, `status.api.philanthropydatacommons.org`, etc (and the `status.test.*` equivalents for `test`). Note that all these status pages are identical, showing uptime for all monitored PDC services, not just the service whose domain it's on. Additionally, the test and prod servers themselves host status pages at pdc-status-test.opentechstrategies.com and pdc-status-prod.opentechstrategies.com, so these domains are included in the test and prod Caddyfiles as appropriate. 

## Deployment (`.github/workflows/deploy.yaml`)

Both `test` and `prod` hosts, SSH credentials, and the Zulip Basic Auth secret are supplied via GitHub Actions secrets/vars.Currently only the host IP of the test and prod servers are scoped to the test/prod environments; the user, ssh key and Zulip Basic Auth info are the same across both servers.

**Validate** (runs on every push and every manual dispatch):
- Fails CI if any `versions.env` uses a floating `:latest` tag — versions must be pinned.
- For both `test` and `prod`, stands up the pinned Gatus image locally with that environment's `config.yaml` mounted, waits 10s, and checks the logs for a fatal error. 

**Deploy to `test`** — triggered automatically on push to `main` that touches `environments/**`, or manually. 
1. Writes `environments/test/.env` from Actions secrets.
2. SCPs `compose.yaml`, `config.yaml`, `Caddyfile`, `versions.env`, and `.env` to `/opt/gatus/` on the target host.
3. Runs `docker compose pull && up -d`, then writes a `DEPLOYED_COMMIT` file with the deployed SHA and UTC timestamp.
4. Reloads Caddy's config and restarts the Gatus container (neither seems to reliably pick up config changes without a restart).
5. Verifies the deploy by curling Gatus's `/health` endpoint from inside its network.

**Deploy to `prod`** — manual only (`workflow_dispatch` with `environment: prod`), gated by the `prod` GitHub Environment's required reviewer. Same steps as `test`, targeting `/opt/gatus/` on the prod host.

**Tag release** — runs after a successful `deploy-prod`; currently only checks out full repo history (`fetch-depth: 0`) and does not yet create/push a tag. A release tag system will be implemented later. 

## Making changes

1. Edit the relevant `environments/{test,prod}/*` files.
2. Push to `main` — CI validates both configs and auto-deploys `test`.
3. Once verified on `test`, manually dispatch the workflow 