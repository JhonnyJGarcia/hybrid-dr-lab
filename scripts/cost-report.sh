#!/usr/bin/env bash
# Read-only cost report for the DR lab, used by the cost-watcher agent.
#
# Why a script: the cost data needs `az rest --method post` (Cost Management query),
# and allow-listing `az rest` in general would also allow writes to any resource.
# The agent is allowed to run this script only, and cannot edit it.
#
# Every call below is a GET, or a POST to the Cost Management *query* API (read-only).
set -euo pipefail

# --- Lab parameters (no secrets; check them in the portal) -------------------
TRIAL_START="2026-11-03"     # trial activation date
TRIAL_END="2026-12-03"       # credit expires 30 days after activation
CREDIT_EUR="185"             # 200 USD trial credit, approximate value in EUR
RG="rg-dr-lab-sdc"
VM="vm-pve-dr-lab-sdc-01"
# ------------------------------------------------------------------------------

API="https://management.azure.com"
SUB=$(az account show --query id -o tsv)
TODAY=$(date +%Y-%m-%d)

cost_query() { # $1 = JSON body; prints rows as TSV
  az rest --method post \
    --url "$API/subscriptions/$SUB/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
    --body "$1" --query "properties.rows" -o tsv
}

echo "=== Spend by service, since trial start ($TRIAL_START .. $TODAY) ==="
BY_SERVICE=$(cost_query "{\"type\":\"ActualCost\",\"timeframe\":\"Custom\",
  \"timePeriod\":{\"from\":\"$TRIAL_START\",\"to\":\"$TODAY\"},
  \"dataset\":{\"granularity\":\"None\",
    \"aggregation\":{\"totalCost\":{\"name\":\"Cost\",\"function\":\"Sum\"}},
    \"grouping\":[{\"type\":\"Dimension\",\"name\":\"ServiceName\"}]}}")
echo "$BY_SERVICE" | awk -F'\t' '{printf "  %-20s %8.2f %s\n", $2, $1, $3}'

echo
echo "=== Daily spend ==="
DAILY=$(cost_query "{\"type\":\"ActualCost\",\"timeframe\":\"Custom\",
  \"timePeriod\":{\"from\":\"$TRIAL_START\",\"to\":\"$TODAY\"},
  \"dataset\":{\"granularity\":\"Daily\",
    \"aggregation\":{\"totalCost\":{\"name\":\"Cost\",\"function\":\"Sum\"}}}}")
echo "$DAILY" | awk -F'\t' '{printf "  %s  %6.2f %s\n", $2, $1, $3}'

echo
echo "=== Budgets (billing account scope) ==="
# The trial is an individual Microsoft Customer Agreement: budgets live on the
# billing account, not on the subscription. The account ID is discovered, never stored.
for BA in $(az rest --method get --url "$API/providers/Microsoft.Billing/billingAccounts?api-version=2024-04-01" \
              --query "value[].name" -o tsv); do
  az rest --method get \
    --url "$API/providers/Microsoft.Billing/billingAccounts/$BA/providers/Microsoft.CostManagement/budgets?api-version=2023-11-01" \
    --query "value[].[name, properties.amount, properties.timeGrain, properties.currentSpend.amount, join(',', properties.notifications.*.threshold | map(&to_string(@), @))]" \
    -o tsv | awk -F'\t' '{printf "  %s: %.2f / %.0f EUR (%s), alerts at %s%%\n", $1, $4, $2, $3, $5}'
done

echo
echo "=== Billable resources now ==="
POWER=$(az vm get-instance-view -g "$RG" -n "$VM" --query "instanceView.statuses[1].displayStatus" -o tsv)
echo "  VM $VM: $POWER"
echo "  VPN gateways: $(az network vnet-gateway list -g "$RG" --query "length(@)" -o tsv)"
echo "  Public IPs:   $(az network public-ip list -g "$RG" --query "length(@)" -o tsv)"
echo "  Disks:        $(az disk list -g "$RG" --query "length(@)" -o tsv)"

echo
echo "=== Forecast ==="
# Average of the last 3 complete days. Excluded: today (partial, cost data lags by
# hours) and the first day with costs (resources were created during that day).
echo "$DAILY" | python3 -c '
import sys, datetime as dt
trial_end, credit, today = sys.argv[1], float(sys.argv[2]), dt.date.today()
rows = [l.split("\t") for l in sys.stdin.read().strip().splitlines() if l]
days = sorted((dt.datetime.strptime(r[1], "%Y%m%d").date(), float(r[0])) for r in rows)
spent = sum(c for _, c in days)
full = [c for d, c in days[1:] if d < today][-3:]
rate = sum(full) / len(full) if full else 0.0
left = (dt.date.fromisoformat(trial_end) - today).days
forecast = spent + rate * max(left, 0)
print(f"  Spent so far:          {spent:7.2f} EUR")
print(f"  Daily rate (last 3d):  {rate:7.2f} EUR/day")
print(f"  Days to trial end:     {left:7d}  ({trial_end})")
print(f"  Forecast at trial end: {forecast:7.2f} EUR of ~{credit:.0f} EUR credit ({forecast / credit:.0%})")
print(f"  Credit left (approx):  {credit - spent:7.2f} EUR")
' "$TRIAL_END" "$CREDIT_EUR"
