#!/usr/bin/env python3
"""Parse a watched app's supervisord config to extract the app command."""
import configparser
import os
import sys


def parse_app_command(config_path):
    config = configparser.ConfigParser()
    config.read(config_path)

    for section in config.sections():
        if section.startswith("program:"):
            command = config[section].get("command", "")
            if command:
                return command

    return None


if __name__ == "__main__":
    watched_dir = sys.argv[1] if len(sys.argv) > 1 else "/app/watched"
    config_dir = os.path.join(watched_dir, "keboola-config", "supervisord", "services")

    if not os.path.isdir(config_dir):
        print(f"ERROR: Config directory not found: {config_dir}", file=sys.stderr)
        sys.exit(1)

    for f in sorted(os.listdir(config_dir)):
        if f.endswith(".conf"):
            cmd = parse_app_command(os.path.join(config_dir, f))
            if cmd:
                print(cmd)
                sys.exit(0)

    print("ERROR: No app command found in watched repo's supervisord config", file=sys.stderr)
    sys.exit(1)
