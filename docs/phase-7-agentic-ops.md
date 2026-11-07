# Phase 7: Agentic operations

The lab is operated through **Claude Code**: one orchestrator that the operator talks to, and four specialised sub-agents. The point of the phase is not the agents themselves but the **control around them**: what an agent may do on its own, what needs a human, and what no agent can do whatever it decides.

```
                        Operator
                           │  asks, approves tier-2 actions, runs tier-3 ones
                           ▼
                ┌─────────────────────┐
                │ Orchestrator        │  CLAUDE.md: roles, tiers, escalation
                │ (main session)      │
                └──┬──────┬──────┬────┘
        ┌──────────┘      │      └───────────┬───────────────┐
        ▼                 ▼                  ▼               ▼
  iac-reviewer     health-checker      cost-watcher     dr-operator
  terraform/       az + SSH (agent)    cost script      pre-flight + procedure
        │                 │                  │               │
        └─────────────────┴──── guardrails ──┴───────────────┘
          settings.json rules · PreToolUse hook · sudoers on the nodes
```

## Agents

| Agent | Model | Can run | Produces |
|---|---|---|---|
| `iac-reviewer` | Sonnet | file reads, `terraform fmt -check`, `terraform validate` | Findings table by severity: security, cost, conventions, correctness, docs drift |
| `health-checker` | Haiku | VM state, VPN state, status commands on both sites over SSH | `OK` / `WARN` / `ACTION NEEDED` with a table per check and the likely cause |
| `cost-watcher` | Haiku | `scripts/cost-report.sh` only | Spend, daily rate, forecast to the trial end, budget, biggest saving |
| `dr-operator` | Sonnet | the same read-only checks + container status/config | Pre-flight, then the exact commands for the operator, then step-by-step verification |

Haiku for the agents that read status and apply fixed thresholds; Sonnet where several outputs have to be reasoned about together. The orchestrator is the main session: in Claude Code sub-agents cannot start other sub-agents, so the "master" is the session the operator talks to.

## Autonomy tiers

| Tier | Examples | Who acts |
|---|---|---|
| 1. Automatic | Reading files, `az ... show/list`, `ceph -s`, mirror status, the cost report | The agent, without asking |
| 2. With approval | Start/deallocate the VM, `terraform plan`, any SSH command not on the read-only list, file edits | The agent, after the operator approves the single call |
| 3. Never an agent | `terraform apply/destroy`, deleting resources, mirror promote/demote/resync, destroying guests, wiping disks, reboots, **failover and failback** | The operator, by hand. Agents may prepare the commands |

Failover stays in tier 3 by choice: it is rare, it has two irreversible points (`promote --force`, `resync`), and a human running it from a prepared, checked procedure is both safer and fast enough.

## Three layers of enforcement

Instructions in a prompt are a request, not a control. Each tier is enforced outside the model, in three independent layers:

1. **Claude Code permission rules** (`.claude/settings.json`): `allow` lists the exact read-only commands, `ask` the reversible ones, `deny` the destructive ones. The agents also cannot edit `.claude/`, `CLAUDE.md` or `scripts/`: an agent must not be able to loosen its own limits.
2. **PreToolUse hook** (`.claude/hooks/guard.py`): permission rules match the start of a command, so `ssh node "pct destroy 100"` would only be checked as `ssh ...`. The hook reads the whole command line, including what is sent over SSH, and blocks tier-3 patterns with a message that tells the agent to report, not retry.
3. **Least privilege on the targets**: SSH goes to a dedicated user `agent` (key only, password locked, not in `sudo`), and `/etc/sudoers.d/agent` on each node allows only a fixed list of status commands. `sudo ceph osd pool ls`, a command not on the list, is refused by the node itself, whatever runs on the operator's machine.

Layer 3 is the real boundary. The hook is a pattern match and can be evaded by a determined process (encoding a command, for example); it exists to stop honest mistakes early and visibly, while the node refuses anything outside the list regardless.

### Narrow interfaces instead of general tools

The cost data needs `az rest --method post` (Cost Management query API). Allow-listing `az rest` would also allow any write to any resource. Instead, a read-only script (`scripts/cost-report.sh`) is allow-listed and protected from edits. The same idea as the sudoers list: expose a specific command, not a general tool.

### Nothing environment-specific in the repo

Agents reach the nodes through SSH aliases (`dr-home`, `dr-azure`) defined on the operator's machine. Addresses, keys and the billing account ID never appear in the repo, which is public: the cost script discovers the billing account at run time.

## What happened in practice

**The health-checker found a real problem on its first run.** The DR node's Ceph was in `HEALTH_WARN` with one undersized placement group. Cause: the `.mgr` pool, created automatically by the manager, used the default CRUSH rule (replicas on different *hosts*), which a single-node cluster can never satisfy. Fixed by the operator with `ceph osd pool set .mgr crush_rule replicated_osd`. The same check also showed that `az network vpn-connection list` returns `None` for the live status; the agent now uses `show`.

**The orchestrator did not invent a cost figure.** Asked about costs before the cost-watcher existed, it stated the agent was missing, stayed within read-only commands, and reported what it could not verify: the Consumption API returns zero for a free trial, and no budget was visible. Investigating that led to two facts the cost-watcher now relies on: the **Cost Management query API** returns real figures on a trial, and the budget lives at **billing-account scope** (the trial is an individual Microsoft Customer Agreement), where subscription-scope queries cannot see it. `CLAUDE.md` now says explicitly what to do when an agent is planned but missing: tier-1 work only.

**The forecast was checked, not trusted.** The first version of the cost script averaged a partial day (the day the VM was created) and forecast 2.15 EUR/day; excluding the first and the current day gives 2.87 EUR/day, about 45% of the credit by the trial end. Arithmetic is done in the script, not by the model.

**The dr-operator prepares a failover without executing it.** Given "planned failover of container 100", it runs the pre-flight (VM, VPN, Ceph, daemon, mirror lag, container state on both sites, SDN vnet name), then writes the procedure with real IDs, IP and bridge filled in, and marks the points of no return.

## Limits and next steps

- **Azure access uses the operator's own login.** The agents' Azure commands are read-only by rule and by hook, but the identity behind them could write. Next step: a dedicated service principal with the **Reader** role (and Cost Management Reader on the billing scope) for agent sessions.
- **On demand only.** Agents run when the operator opens a session; nothing watches the lab at night. A scheduled health check (cron or a CI job running Claude Code headless with the same settings) would close that gap.
- **Usage limits.** Everything runs on a Claude Pro subscription at no extra cost; long sessions are bounded by the plan's usage limits.
