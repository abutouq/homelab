#!/usr/bin/env python3
"""Idempotently upsert or remove a Teleport app_service.apps entry.

Run on the Teleport control-plane host itself (as root) against
/etc/teleport.yaml. Prints CHANGED or UNCHANGED on the first line so the
calling Ansible playbook can decide whether to restart teleport.service.

Note: this re-serializes the whole file via PyYAML, which drops comments
(there's no round-trip-preserving YAML library installed on the host). A
timestamped-free rolling backup is taken by the playbook before this runs,
so that's recoverable, but don't expect the file's existing inline
comments to survive an edit.
"""
import argparse
import sys

import yaml

CONFIG_PATH = "/etc/teleport.yaml"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--name", required=True)
    p.add_argument("--uri", default="")
    p.add_argument("--state", choices=["present", "absent"], default="present")
    args = p.parse_args()

    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)

    apps = config.setdefault("app_service", {}).setdefault("apps", [])
    existing = next((a for a in apps if a.get("name") == args.name), None)

    if args.state == "absent":
        if existing is None:
            print("UNCHANGED: app not present")
            return
        apps.remove(existing)
    else:
        if not args.uri:
            print("ERROR: --uri is required for --state present", file=sys.stderr)
            sys.exit(1)
        desired = {
            "name": args.name,
            "uri": args.uri,
            "public_addr": "",
            "insecure_skip_verify": False,
            "use_any_proxy_public_addr": False,
        }
        if existing == desired:
            print("UNCHANGED: app already up to date")
            return
        if existing is not None:
            apps.remove(existing)
        apps.append(desired)

    with open(CONFIG_PATH, "w") as f:
        yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False)

    print("CHANGED: app_service.apps updated")


if __name__ == "__main__":
    main()
