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

1. **Bootstrap** -- wrapper `setup.sh` reads `/data/config.json`, sets up auth, moves our scripts to `/tmp/continuous-pull/`, and clones the watched repo directly into `/app` so its hardcoded paths work naturally. It does **not** run the watched repo's own `setup.sh`. After the clone, it installs wrapper-owned configs (`nginx/sites/default.conf`, `supervisord/services/_continuous-pull.conf`, `supervisord/rpc.conf`) alongside the watched repo's configs.
2. **First pull** -- on its first invocation, `pull_once.sh` runs the watched repo's `keboola-config/setup.sh` (install deps, build, etc.) and starts the app. A sentinel under `/tmp/continuous-pull/` ensures it only happens once per container lifetime.
3. **Run** -- supervisord manages:
   - **pull-loop** -- does the initial pull, then (if `pullPeriod` is set) re-polls on that schedule. Each poll does a fetch + reset if the remote advanced, then applies supervisord config changes and (if nginx config changed) reloads nginx.
   - **pull-api** -- tiny Python HTTP server exposing `POST /_api/pull` and `POST /_api/re-setup`.
   - **nginx** -- `/_api/*` proxies to `pull-api`; user-defined routes (from `keboola-config/nginx/conf.d/*.conf`) take precedence; the catch-all `location /` proxies to port 3000.
   - **every `[program:*]` the watched repo defines** -- the wrapper no longer execs only the first one. Users can run a backend + frontend side by side (see "Multi-process apps" below).

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

| Field         | Required | Description                                                                                                                                                                                         |
| ------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `url`         | yes      | Git clone URL (HTTPS or SSH)                                                                                                                                                                        |
| `branch`      | no       | Branch to clone and track. Defaults to the repo's default branch.                                                                                                                                   |
| `pullPeriod`  | no       | Seconds between automatic pulls. When omitted, automatic pulling is disabled and updates must be triggered explicitly via `POST /_api/pull`.                                                        |
| `autoReSetup` | no       | When `true`, automatically re-run the watched repo's `setup.sh` after every pull that detects new commits. Useful when dependencies or build steps may change between commits. Defaults to `false`. |
| `#privateKey` | no       | SSH private key for accessing private repositories. The `#` prefix means it is encrypted at rest by Keboola.                                                                                        |
| `username`    | no       | Username for HTTPS auth. Used together with `#password`.                                                                                                                                            |
| `#password`   | no       | Password or personal access token for HTTPS auth.                                                                                                                                                   |

## Watched repo layout

```
<watched-repo>/
  keboola-config/
    setup.sh                            # Install deps, build; runs on first pull + autoReSetup pulls
    supervisord/services/
      app.conf                          # One or more [program:*] sections -- ALL start
      (optional: extra-service.conf)    # Additional supervisord programs live here
    nginx/
      conf.d/                           # OPTIONAL -- user-defined location snippets, included by the wrapper's server block
        api.conf                        # e.g. location /api/ { proxy_pass http://127.0.0.1:3001; }
  <your source code>
```

### Single-process app (default)

The watched repo defines one program. It must listen on `127.0.0.1:3000`:

```ini
; keboola-config/supervisord/services/app.conf
[program:app]
command=uv run python /app/app.py
directory=/app
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
```

No user nginx config needed -- the wrapper's default `location /` proxies to 3000.

### Multi-process apps

The wrapper loads every `[program:*]` the watched repo defines. To run a frontend + backend side by side:

```ini
; keboola-config/supervisord/services/app.conf
[program:backend]
command=node /app/dist/server.js
directory=/app
autostart=true
autorestart=true

[program:frontend]
command=npx vite preview --host 127.0.0.1 --port 5173
directory=/app
autostart=true
autorestart=true
```

Then tell nginx where each one lives via a user-owned snippet:

```nginx
# keboola-config/nginx/conf.d/routes.conf
location /api/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
}

location / {
    proxy_pass http://127.0.0.1:5173;
    proxy_set_header Host $host;
}
```

User `location` blocks in `conf.d/*.conf` are included **before** the wrapper's catch-all `location /` and take precedence, so adding a `location /` of your own replaces the default port-3000 proxy.

**Single-process remains the default** for production-style apps -- it's simpler, has one thing to fail, and matches the python-js image's assumptions. Multi-process is here for dev flows where a separate dev/build server is valuable.

## Reserved / wrapper-owned

- **`/_api/*`** is routed by the wrapper to an internal supervisor (`127.0.0.1:8051`) that exposes the pull/re-setup endpoints. Defining user routes under `/_api/` will not reach the browser -- the wrapper's location block matches first.
- **`nginx/sites/default.conf`** is installed by the wrapper on every container start. Anything the watched repo writes there is overwritten. Put location blocks in `nginx/conf.d/*.conf` instead.
- **`supervisord/services/_continuous-pull.conf`** (pull-loop + pull-api) is wrapper-owned. Do not write a file with this exact name.
- **`supervisord/rpc.conf`** is wrapper-owned (unix socket for supervisorctl).

## Error handling and the fallback page

The wrapper ships `fallback.html` as a small "Application is starting" page. The bundled nginx config has:

```nginx
error_page 502 504 = /fallback.html;
```

This narrow scope catches only **upstream connection refused** (cold start before the app binds port 3000) and **upstream timeouts**. 4xx/5xx responses produced by the watched app itself are **not** swallowed -- they pass through to the browser so problems are visible. Previous versions used a wider `error_page 500 502 503 504 404 = /fallback.html` with `proxy_intercept_errors on`, which made every upstream error look like a successful HTTP 200 at the browser. That behavior is gone.

## HTTP API

No auth -- `pull-api` binds to `127.0.0.1` and is only reachable via the nginx `/_api/` proxy.

| Method + path         | Effect                                                                                                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /_api/pull`     | Fetch, fast-forward if the remote advanced, apply supervisord config changes (`reread` + `update`), and reload nginx if its config changed. Does not re-run setup. |
| `POST /_api/re-setup` | Re-run the watched repo's `keboola-config/setup.sh`, then apply supervisord changes and reload nginx. Use when dependencies or build output have changed.          |

Pulls and re-setups are serialized via a `flock` lock so the scheduled loop and explicit API calls can't collide.

## Project Structure

```
keboola-config/
  setup.sh                            # Wrapper entrypoint: read config, clone into /app, install wrapper configs
  nginx/sites/default.conf            # server block + /_api/ -> :8051, include user's conf.d/, / -> :3000
  supervisord/rpc.conf                # Supervisor UNIX socket config
  supervisord/services/
    _continuous-pull.conf             # pull-loop + pull-api (wrapper-owned)
scripts/                              # Copied to /tmp/continuous-pull/scripts/ at runtime
  pull_once.sh                        # One fetch/reset iteration; runs watched setup on first call
  pull_loop.sh                        # Does the initial pull, then pulls every pullPeriod seconds
  re_setup.sh                         # Re-run watched setup + apply supervisord/nginx changes
  api_server.py                       # HTTP server on :8051 exposing /_api/pull and /_api/re-setup
fallback.html                         # Shown only during cold start / upstream connect failures
```

## Assumptions

- The watched repo follows the [keboola/data-app-python-js](https://github.com/keboola/data-app-python-js) conventions:
  - `keboola-config/setup.sh` for building
  - `keboola-config/supervisord/services/*.conf` defining one or more `[program:*]` sections
- At least one of the watched app's backends listens on `127.0.0.1:3000` (unless the user's `conf.d/` snippet redefines `location /` to point elsewhere).
