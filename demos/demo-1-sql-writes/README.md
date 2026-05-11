# Demo 1 — SQL writes through the perimeter

> Proves: the jump VM (inside the subscription) can write to Azure SQL even with `publicNetworkAccess=Enabled`, while NSP **logs** the access. In Enforced mode, the same write from your laptop is **blocked**.

## Pre-req: seed the database (one-time, run from anywhere with `sqlcmd` and the agent SP token)

The agent service principal is the SQL server's Entra admin. From your laptop (where `az login` shows the agent SP):

```bash
cd demos/demo-1-sql-writes
bash seed-from-here.sh
```

This:
1. Pulls outputs from terraform state (`sql_server_fqdn`, `uami_name`)
2. Sed-replaces `__UAMI_NAME__` in `seed.sql`
3. Runs `sqlcmd -G` (Entra auth via your active az login) → creates table + contained user

## Run from the jump VM (should succeed in both modes)

```bash
ssh -i ~/.ssh/nsp_lab_ed25519 labadmin@<jump-ip>
# on the VM:
curl -sLO https://raw.githubusercontent.com/nthewara/nsp-lab/main/demos/demo-1-sql-writes/insert-from-allowed.sh
bash insert-from-allowed.sh
```

You should see `(1 rows affected)`.

## Run from the internet (your laptop)

```bash
bash insert-from-internet.sh
```

- **Learning mode**: succeeds. Look in LAW (`kql/sql-nsp-logs.kql`) — you'll see a `NetworkSecurityPerimeterPublicAccessAttempt` row with `result_s = "Allowed"` and `matchedRule_s = "_NoRuleMatched"` (the "would deny" signal).
- **Enforced mode**: fails with a TDS-level reset or 18456 login error, and LAW shows `result_s = "Denied"`.

Run the KQL after each attempt to see the matching event.
