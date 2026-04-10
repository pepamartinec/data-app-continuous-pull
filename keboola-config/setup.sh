#!/bin/bash
set -euo pipefail

echo "=== Continuous Pull Data App Setup ==="

# Read config
REPO_URL=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['parameters']['dataApp']['watchedRepo']['url'])
")

BRANCH=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['parameters']['dataApp']['watchedRepo'].get('branch', ''))
" 2>/dev/null || true)

PRIVATE_KEY=$(python3 -c "
import json
c = json.load(open('/data/config.json'))
print(c['parameters']['dataApp']['watchedRepo'].get('#privateKey', ''))
" 2>/dev/null || true)

echo "Watched repo: $REPO_URL"
if [ -n "$BRANCH" ]; then
    echo "Branch: $BRANCH"
fi

# Setup SSH key if provided
if [ -n "$PRIVATE_KEY" ]; then
    echo "Setting up SSH key..."
    mkdir -p ~/.ssh
    printf '%s\n' "$PRIVATE_KEY" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan github.com gitlab.com bitbucket.org >> ~/.ssh/known_hosts 2>/dev/null
    git config --global core.sshCommand "ssh -o StrictHostKeyChecking=no"
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
