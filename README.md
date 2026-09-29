# discourse-behind-caddy

Run several Discourse sites on one host, behind Caddy, with one command
per site.

The official `discourse-setup` gives you one site per box, with Discourse
terminating TLS itself. For a second site, or a host that already runs
Caddy for other things, the supported shape is different: one **data**
container holding Postgres and Redis for every site, one **web_only**
container per site listening on a localhost port, and Caddy in front
routing by hostname and holding the certificates. `bin/new-site` writes
those pieces and runs the launcher.

## What it does

```
bin/new-site --hostname forum.example.com --port 8081 \
  --smtp-address smtp.example.com --smtp-user u --smtp-password p \
  --developer-email you@example.com \
  --plugin https://github.com/discourse/discourse-solved.git \
  --backup ~/forum-2026-09-28.tar.gz --apply
```

Without `--apply` it prints the plan and writes nothing. With it:

1. If `containers/data.yml` does not exist, writes it (the `postgres` and
   `redis` templates, shared volumes under `shared/data`) and bootstraps
   and starts it. Every later site reuses it.
2. Writes `containers/<name>.yml`: the `web` and `web.ratelimited`
   templates, no Let's Encrypt, `expose 127.0.0.1:<port>:80`, a link to
   the data container, its own database name and the next free Redis
   database number, `DISCOURSE_FORCE_HTTPS` on so links come out right
   behind the proxy, your SMTP settings, and `docker_manager` plus every
   `--plugin` cloned in `after_code`. Bootstraps and starts it.
3. Writes `<caddy-dir>/<name>.caddy`:
   ```
   forum.example.com {
       encode gzip
       reverse_proxy 127.0.0.1:8081
   }
   ```
   and reloads Caddy. Your Caddyfile needs `import sites/*.caddy` (or
   whatever directory you pass as `--caddy-dir`).
4. With `--backup`, copies the file into the site's backups directory and
   runs `discourse enable_restore && discourse restore <file>` inside the
   container. A backup made on any Discourse with the same plugins
   restores cleanly, which is how you move a site here.

The container name defaults to the first label of the hostname.

## Options

| Flag | Default | Meaning |
| --- | --- | --- |
| `--hostname` | required | Public hostname |
| `--name` | first label | Container name and directory under `shared/` |
| `--port` | 8081 | Localhost port Caddy proxies to; use a new one per site |
| `--docker-dir` | `/var/discourse` | Your discourse_docker checkout |
| `--caddy-dir` | `/etc/caddy/sites` | Directory the Caddyfile imports |
| `--data-name` | `data` | Shared data container |
| `--plugin` | none | Plugin git url, repeatable |
| `--version` | `stable` | Discourse branch or tag |
| `--developer-email` | | First admin |
| `--smtp-address`, `--smtp-port`, `--smtp-user`, `--smtp-password` | | Outgoing mail; a site cannot activate accounts without it |
| `--unicorn-workers` | 2 | Per site; two is right for a few hundred users |
| `--db-shared-buffers` | `256MB` | Postgres memory in the data container |
| `--backup` | none | Backup file to restore after bootstrap |
| `--apply` | off | Do it |

## Memory

Each web container is a full Rails app. Budget about 1 GB per site with
two workers, plus the data container. A 4 GB host runs two or three
sites comfortably; give the data container's `--db-shared-buffers` a
quarter of what you can spare for Postgres.

## Things it does not do

- Install themes or theme components; do that from the admin afterwards.
- Set up Caddy itself, or the `import` line in your Caddyfile.
- Upgrades. `./launcher rebuild <name>` per site, as usual, and the data
  container separately and rarely.
- Multisite (many sites in one Rails process). That is a different shape
  with a shared plugin set; this tool keeps sites independent.

## Tests

```
bundle install && bundle exec rspec
```

The specs cover the generated files and the plan; nothing touches docker.
