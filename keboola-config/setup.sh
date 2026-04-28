#!/bin/bash
set -euo pipefail

echo "=== Continuous Pull Data App Setup ==="

# Read config
REPO_URL=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['dataApp']['watchedRepo']['url'])
")

BRANCH=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['dataApp']['watchedRepo'].get('branch', ''))
" 2>/dev/null || true)

PRIVATE_KEY=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['dataApp']['watchedRepo'].get('#privateKey', ''))
" 2>/dev/null || true)

USERNAME=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['dataApp']['watchedRepo'].get('username', ''))
" 2>/dev/null || true)

PASSWORD=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['dataApp']['watchedRepo'].get('#password', ''))
" 2>/dev/null || true)

PULL_PERIOD=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
v = c['dataApp']['watchedRepo'].get('pullPeriod')
print('' if v is None else int(v))
" 2>/dev/null || true)

AUTO_RE_SETUP=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
v = c['dataApp']['watchedRepo'].get('autoReSetup', False)
print('1' if v else '')
" 2>/dev/null || true)

echo "Watched repo: $REPO_URL"
if [ -n "$BRANCH" ]; then
    echo "Branch: $BRANCH"
fi

# Setup authentication
if [ -n "$PRIVATE_KEY" ]; then
    echo "Setting up SSH key..."
    mkdir -p ~/.ssh
    printf '%s\n' "$PRIVATE_KEY" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan github.com gitlab.com bitbucket.org >> ~/.ssh/known_hosts 2>/dev/null
    git config --global core.sshCommand "ssh -o StrictHostKeyChecking=no"
elif [ -n "$PASSWORD" ]; then
    echo "Setting up username/password auth..."
    REPO_URL=$(python3 -c "
from urllib.parse import urlparse, urlunparse, quote
import sys
u = urlparse(sys.argv[1])
user = quote(sys.argv[2], safe='')
pwd = quote(sys.argv[3], safe='')
print(urlunparse(u._replace(netloc=f'{user}:{pwd}@{u.hostname}' + (f':{u.port}' if u.port else ''))))
" "$REPO_URL" "$USERNAME" "$PASSWORD")
fi

# Move our scripts and configs to a safe location outside /app
echo "Saving continuous-pull scripts to /tmp/continuous-pull..."
mkdir -p /tmp/continuous-pull
cp -a /app/scripts /tmp/continuous-pull/scripts
cp -a /app/keboola-config /tmp/continuous-pull/keboola-config
cp -a /app/fallback.html /tmp/continuous-pull/fallback.html

# Persist runtime config for pull_loop.sh
cat > /tmp/continuous-pull/config.env <<EOF
PULL_PERIOD=${PULL_PERIOD}
AUTO_RE_SETUP=${AUTO_RE_SETUP}
EOF

# Clear /app and clone the watched repo directly into it
# so that the watched app's setup.sh /app paths work naturally
echo "Cloning watched repo into /app..."
find /app -mindepth 1 -maxdepth 1 -exec rm -rf {} +

if [ -n "$BRANCH" ]; then
    git clone --branch "$BRANCH" "$REPO_URL" /app
else
    git clone "$REPO_URL" /app
fi

# Watched app's setup.sh is run by the first pull_once, not here.

# Install our keboola-config alongside the watched repo's. The platform reads
# /app/keboola-config/ after this script returns, so after this merge step:
#   - nginx/sites/default.conf   -> wrapper's (owns server block + /_api/)
#   - nginx/conf.d/*.conf        -> user's (included by our server block)
#   - supervisord/services/
#       _continuous-pull.conf    -> wrapper's (pull-loop + pull-api)
#       app.conf + any others    -> user's (all [program:*] sections load)
echo "Installing continuous-pull configs..."
mkdir -p /app/keboola-config/nginx/sites /app/keboola-config/nginx/conf.d
mkdir -p /app/keboola-config/supervisord/services
cp -af /tmp/continuous-pull/keboola-config/nginx/sites/* /app/keboola-config/nginx/sites/
cp -af /tmp/continuous-pull/keboola-config/supervisord/rpc.conf \
    /app/keboola-config/supervisord/
cp -af /tmp/continuous-pull/keboola-config/supervisord/services/_continuous-pull.conf \
    /app/keboola-config/supervisord/services/

echo "=== Setup complete ==="
