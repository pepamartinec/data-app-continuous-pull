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
    # Embed credentials into the clone URL (https://user:pass@host/...)
    REPO_URL=$(python3 -c "
from urllib.parse import urlparse, urlunparse, quote
import sys
u = urlparse(sys.argv[1])
user = quote(sys.argv[2], safe='')
pwd = quote(sys.argv[3], safe='')
print(urlunparse(u._replace(netloc=f'{user}:{pwd}@{u.hostname}' + (f':{u.port}' if u.port else ''))))
" "$REPO_URL" "$USERNAME" "$PASSWORD")
fi

# Clone the watched repo
echo "Cloning watched repo..."
if [ -n "$BRANCH" ]; then
    git clone --branch "$BRANCH" "$REPO_URL" /app/watched
else
    git clone "$REPO_URL" /app/watched
fi

# Build the watched app
echo "Building watched app..."
bash /app/scripts/rebuild.sh full

echo "=== Setup complete ==="
