# Continuous Pull Data App

> **⚠️ DEVELOPMENT / DEBUGGING ONLY -- DO NOT USE IN PRODUCTION.**
>
> This app exists purely to accelerate the inner loop while developing and debugging python-js data apps. It auto-pulls arbitrary code from a remote branch, executes it with no sandboxing, and exposes an unauthenticated HTTP endpoint that triggers a pull on demand. There is no review step, no pinning, and no safety net of any kind. **Use at your own risk.**

A Keboola [python-js](https://github.com/keboola/data-app-python-js) data app that acts as a live-reloading wrapper around another python-js app repository. It clones a watched repo, runs it, and can fetch-and-restart on new commits -- either on a configurable schedule or on demand via a small HTTP API.

Built for developing and debugging the continuous deployment flow.

## How It Works

```
+---------+    +-------+    +-----------+    +---------+    +---------+
| config  +--->| clone +--->|  first    +--->| run app +--->|  pull   |
| .json   |    | repo  |    |  pull     |    |         |    | loop /  |
+---------+    +-------+    | (runs     |    +---------+    | API     |
                            |  setup.sh)|                   +---------+
                            +-----------+
```

1. **Bootstrap** -- wrapper `setup.sh` reads `/data/config.json`, sets up auth, moves our scripts to `/tmp/continuous-pull/`, and clones the watched repo directly into `/app` so its hardcoded paths work naturally. It does **not** run the watched repo's own `setup.sh`.
2. **First pull** -- on its first invocation, `pull_once.sh` runs the watched repo's `keboola-config/setup.sh` (install deps, build, etc.) and restarts the app. A sentinel under `/tmp/continuous-pull/` ensures it only happens once per container lifetime.
3. **Run** -- supervisord manages four processes:
   - **app** -- the watched repo's backend (command auto-discovered from its supervisord config)
   - **pull-loop** -- does the initial pull, then (if `pullPeriod` is set) re-polls on that schedule. Each poll does a fetch + reset if the remote advanced, then restarts the app.
   - **pull-api** -- tiny Python HTTP server exposing `POST /_api/pull` and `POST /_api/re-setup`
   - **nginx** -- `/` proxies to the app, `/_api/` proxies to `pull-api`

Local changes (e.g. files created at runtime) are always discarded in favor of the remote state.

## Configuration

The app reads its configuration from `/data/config.json`:

```json
{
  "dataApp": {
    "watchedRepo": {
      "url": "https://github.com/org/my-python-js-app.git",
      "branch": "main",
      "pullPeriod": 30,
      "#privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
      "autoReSetup": true,
      "username": "git",
      "#password": "ghp_xxxxxxxxxxxx"
    }
  }
}
```

| Field | Required | Description |
|---|---|---|
| `url` | yes | Git clone URL (HTTPS or SSH) |
| `branch` | no | Branch to clone and track. Defaults to the repo's default branch. |
| `pullPeriod` | no | Seconds between automatic pulls. When omitted, automatic pulling is disabled and updates must be triggered explicitly via `POST /_api/pull`. |
| `autoReSetup` | no | When `true`, automatically re-run the watched repo's `setup.sh` after every pull that detects new commits. Useful when dependencies or build steps may change between commits. Defaults to `false`. |
| `#privateKey` | no | SSH private key for accessing private repositories. The `#` prefix means it is encrypted at rest by Keboola. |
| `username` | no | Username for HTTPS auth. Used together with `#password`. |
| `#password` | no | Password or personal access token for HTTPS auth. |

## HTTP API

No auth -- `pull-api` binds to `127.0.0.1` and is only reachable via the nginx `/_api/` proxy.

| Method + path | Effect |
|---|---|
| `POST /_api/pull` | Fetch, fast-forward if the remote advanced, restart the app. Does not re-run setup. |
| `POST /_api/re-setup` | Re-run the watched repo's `keboola-config/setup.sh` and restart the app. Use when dependencies or build output have changed. |

Pulls and re-setups are serialized via a `flock` lock so the scheduled loop and explicit API calls can't collide.

## Project Structure

```
keboola-config/
  setup.sh                          # Wrapper entrypoint: read config, clone into /app, write config.env
  nginx/sites/default.conf          # / -> :3000 (app), /_api/ -> :8051 (pull-api)
  supervisord/services/app.conf     # Process manager: app + pull-loop + pull-api
scripts/                            # Copied to /tmp/continuous-pull/scripts/ at runtime
  run_app.sh                        # Discover and exec the watched app's command
  pull_once.sh                      # One fetch/reset/restart iteration; runs watched setup on first call
  pull_loop.sh                      # Does the initial pull, then pulls every pullPeriod seconds
  re_setup.sh                       # Re-run watched setup + restart (invoked by /_api/re-setup)
  api_server.py                     # HTTP server on :8051 exposing /_api/pull and /_api/re-setup
  parse_command.py                  # Extract command from supervisord .conf
fallback.html                       # Fallback page returned as 200 so health checks pass while the app is down
```

## Assumptions

- The watched repo follows the [keboola/data-app-python-js](https://github.com/keboola/data-app-python-js) conventions:
  - `keboola-config/setup.sh` for building
  - `keboola-config/supervisord/services/*.conf` defining the app command
- The watched app's backend listens on `127.0.0.1:3000`
