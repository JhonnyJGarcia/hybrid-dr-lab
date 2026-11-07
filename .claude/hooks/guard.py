#!/usr/bin/env python3
"""PreToolUse guard: blocks tier-3 (destructive) commands, whatever the agent intends.

Permission rules match command prefixes, so `ssh node "pct destroy 100"` would slip
past a `deny: Bash(pct destroy:*)` rule. This hook scans the whole command string,
including what is sent over SSH, and blocks with exit code 2 (the reason goes back
to the agent so it can report it instead of retrying).
"""
import json
import re
import sys

# (pattern, reason) - matched case-insensitively anywhere in the command
BLOCKED = [
    (r"\bterraform\s+(apply|destroy|import|state\s+(rm|mv|push))\b", "Terraform changes are run by the human operator"),
    (r"\baz\s+(\S+\s+)*delete\b", "Deleting Azure resources"),
    (r"\baz\s+(\S+\s+)*(create|update|set)\b(?!.*--help)", "Changing Azure resources outside Terraform"),
    (r"\brbd\s+mirror\s+image\s+(promote|demote|resync|disable)\b", "Changing mirror roles: use the DR runbook with human approval"),
    (r"\brbd\s+(rm|remove|trash|snap\s+(rm|purge))\b", "Deleting RBD images or snapshots"),
    (r"\bceph\s+osd\s+(pool\s+(delete|rm)|purge|destroy|out|crush\s+rm)\b", "Destructive Ceph operation"),
    (r"\bpveceph\s+(purge|pool\s+destroy|osd\s+destroy|mon\s+destroy)\b", "Destructive Ceph operation"),
    (r"\b(pct|qm)\s+(destroy|rollback|delsnapshot)\b", "Deleting or rolling back guests"),
    (r"\bpvecm\s+(delnode|expected)\b", "Changing cluster membership or quorum"),
    (r"\b(wipefs|mkfs(\.\w+)?|sgdisk|zpool\s+destroy)\b", "Wiping disks"),
    (r"\bdd\s+.*\bof=/dev/", "Writing to a block device"),
    (r"\brm\s+(-\w*\s+)*(/etc/pve|/etc/ceph|/var/lib/ceph)\b", "Deleting cluster configuration"),
    (r"\b(shutdown|poweroff|reboot|halt)\b", "Powering off or rebooting a host"),
]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0  # not our business: let the normal permission flow decide

    if payload.get("tool_name") != "Bash":
        return 0

    command = payload.get("tool_input", {}).get("command", "")
    for pattern, reason in BLOCKED:
        if re.search(pattern, command, re.IGNORECASE):
            print(
                f"BLOCKED by lab guardrail (tier 3): {reason}. "
                "Do not retry or work around this. Report to the operator what you wanted "
                "to do and why; the operator runs tier-3 actions by hand.",
                file=sys.stderr,
            )
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
