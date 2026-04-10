# Continuous Pull Data App

A Keboola [python-js](https://github.com/keboola/data-app-python-js) data app that acts as a live-reloading wrapper around another python-js app repository. It clones a watched repo, runs it, and continuously pulls new changes every second -- automatically rebuilding and restarting the app when updates are detected.

Built for developing and debugging the continuous deployment flow.

## How It Works

```
                                  every 1s
                               +-----------+
                               |           |
+---------+    +-------+    +--+--+    +---v----+    +---------+
| config  +--->| clone +--->| run |    |  pull  +--->| rebuild |
| .json   |    | repo  |    | app |    | (fetch |    | & restart|
+---------+    +-------+    +-----+    |  reset)|    +---------+
                                       +--------+
```

1. **Setup** -- reads `/data/config.json`, sets up SSH key (if provided), clones the watched repo
2. **Build** -- runs the watched repo's own `keboola-config/setup.sh`
3. **Run** -- starts two supervised processes:
   - **app** -- the watched repo's backend (command auto-discovered from its supervisord config)
   - **pull-loop** -- fetches and hard-resets to the remote branch every second; on changes, re-runs the watched repo's setup and restarts the app

Local changes (e.g. files created at runtime) are always discarded in favor of the remote state.

## Configuration

The app reads its configuration from `/data/config.json`:

```json
{
  "dataApp": {
    "watchedRepo": {
      "url": "https://github.com/org/my-python-js-app.git",
      "branch": "main",
      "#privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----\n..."
    }
  }
}
```

| Field | Required | Description |
|---|---|---|
| `url` | yes | Git clone URL (HTTPS or SSH) |
| `branch` | no | Branch to clone and track. Defaults to the repo's default branch. |
| `#privateKey` | no | SSH private key for accessing private repositories. The `#` prefix means it is encrypted at rest by Keboola. |

## Project Structure

```
keboola-config/
  setup.sh                          # Entrypoint: read config, clone, build
  nginx/sites/default.conf          # Reverse proxy: static files + /api/ -> :8050
  supervisord/services/app.conf     # Process manager: app + pull-loop
scripts/
  run_app.sh                        # Discover and exec the watched app's command
  pull_loop.sh                      # Continuous fetch/reset loop
  rebuild.sh                        # Delegate to the watched repo's setup.sh
  parse_command.py                  # Extract command from supervisord .conf
```

## Assumptions

- The watched repo follows the [keboola/data-app-python-js](https://github.com/keboola/data-app-python-js) conventions:
  - `keboola-config/setup.sh` for building
  - `keboola-config/supervisord/services/*.conf` defining the app command
- The watched app's backend listens on `127.0.0.1:8050`
- The watched app's frontend builds to `frontend/dist/`
