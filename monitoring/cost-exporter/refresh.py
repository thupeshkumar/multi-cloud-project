#!/usr/bin/env python3
"""Refresh reports using the current Infracost scan/inspect CLI."""
import argparse, json, os, subprocess, tempfile
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from exporter import amount

def run(args):
    p = subprocess.run(["infracost", *args], text=True, capture_output=True)
    if p.returncode:
        raise RuntimeError(f"Infracost {' '.join(args)} failed:\n{p.stderr[-2500:]}")
    try:
        data = json.loads(p.stdout)
    except ValueError as exc:
        raise RuntimeError("Infracost output is not JSON. Check CLI version and authentication.") from exc
    if not isinstance(data, dict):
        raise RuntimeError("Unknown JSON shape; inspect the report before adapting the parser.")
    return data

def summary_cost(data):
    summary = data.get("summary", data)
    if not isinstance(summary, dict) or "monthly_cost" not in summary:
        raise RuntimeError("Expected monthly_cost or summary.monthly_cost; this CLI JSON version needs an adapter. No report was replaced.")
    return amount(summary["monthly_cost"])

def save_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, encoding="utf-8", delete=False) as f:
        json.dump(data, f, indent=2)
        f.write("\n")
        tmp = f.name
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--terraform", default="terraform")
    p.add_argument("--out", default="monitoring/cost-exporter/data/costs.json")
    a = p.parse_args()
    terraform = str(Path(a.terraform).resolve())
    output = Path(a.out).resolve()
    run(["scan", terraform, "--currency", "USD", "--json"])
    # scan returns a different envelope; obtain totals from the cached summary.
    scan = run(["inspect", terraform, "--summary", "--json"])
    if scan.get("currency") != "USD":
        raise RuntimeError("Scan did not explicitly report USD. No conversion or currency assumption was made.")
    scan_total = summary_cost(scan)
    providers, raw = {}, {}
    for cloud, provider in [("aws", "aws"), ("azure", "azurerm"), ("gcp", "google")]:
        raw[cloud] = run(["inspect", terraform, "--provider", provider, "--summary", "--json"])
        if raw[cloud].get("currency", "USD") != "USD":
            raise RuntimeError("Mixed report currencies")
        v = summary_cost(raw[cloud])
        providers[cloud] = None if v is None else str(v)
    values = [amount(v) for v in providers.values()]
    if scan_total is None or any(v is None for v in values):
        raise RuntimeError("Missing provider/total costs. Review unsupported resources and the JSON schema; no published report replaced.")
    if abs(sum(values, Decimal(0)) - scan_total) > Decimal("0.05"):
        raise RuntimeError("Provider subtotals do not reconcile with the scan total. Check provider filters and report schema; no published report replaced.")
    document = {
        "schema_version": 1,
        "currency": "USD",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "Infracost scan plus provider-filtered summaries",
        "coverage": "Priced-resource subtotal. Inspect diagnostics for omitted and unsupported resources.",
        "providers": providers,
    }
    save_atomic(output.parent / "raw-scan.json", scan)
    save_atomic(output.parent / "raw-provider-summaries.json", raw)
    save_atomic(output, document)
    print("Published fresh USD estimates:", output)
    for cloud, value in providers.items():
        print(cloud, value)
    print("Review raw reports and Infracost diagnostics. These are estimates, not actual charges.")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as exc:
        raise SystemExit(str(exc))
