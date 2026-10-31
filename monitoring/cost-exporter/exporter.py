#!/usr/bin/env python3
"""Local estimate exporter. No cloud credentials or third-party Python packages."""
import json, os, time
from datetime import datetime
from decimal import Decimal, InvalidOperation
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CLOUDS = ("aws", "azure", "gcp")

def amount(value):
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError("Boolean cost")
    try:
        number = Decimal(str(value))
    except InvalidOperation as exc:
        raise ValueError("Invalid cost") from exc
    if not number.is_finite() or number < 0 or number > Decimal("1e15"):
        raise ValueError("Invalid cost range")
    return number

def parse_report(data, now):
    if data.get("schema_version") != 1 or data.get("currency") != "USD":
        raise ValueError("Require schema_version 1 and USD")
    stamp = datetime.fromisoformat(data["generated_at"].replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        raise ValueError("Timestamp requires a timezone")
    epoch = stamp.timestamp()
    if epoch > now + 300:
        raise ValueError("Future timestamp")
    providers = data["providers"]
    if not isinstance(providers, dict):
        raise ValueError("Invalid providers")
    values = {cloud: amount(providers.get(cloud)) for cloud in CLOUDS}
    return epoch, values

def metrics(path, max_age=86400, now=None):
    now = time.time() if now is None else now
    lines = [
        "# HELP cost_exporter_report_valid Whether the normalized report parses successfully.",
        "# TYPE cost_exporter_report_valid gauge",
        "# HELP cost_exporter_report_stale Whether the report is older than the configured maximum age or unavailable.",
        "# TYPE cost_exporter_report_stale gauge",
        "# HELP cost_exporter_estimate_available Whether a fresh numeric estimate is available for a cloud.",
        "# TYPE cost_exporter_estimate_available gauge",
        "# HELP cloud_estimated_monthly_cost_usd Priced monthly infrastructure estimate, excluding unpriced resources and account-specific billing adjustments.",
        "# TYPE cloud_estimated_monthly_cost_usd gauge",
    ]
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
        epoch, values = parse_report(data, now)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError):
        lines += ["cost_exporter_report_valid 0", "cost_exporter_report_stale 1"]
        for cloud in CLOUDS:
            lines.append(f'cost_exporter_estimate_available{{cloud="{cloud}"}} 0')
        return "\n".join(lines) + "\n"
    age = max(0, now - epoch)
    stale = age > max_age
    lines += [
        "cost_exporter_report_valid 1",
        f"cost_exporter_report_stale {int(stale)}",
        "# TYPE cost_exporter_report_generated_timestamp_seconds gauge",
        f"cost_exporter_report_generated_timestamp_seconds {epoch:.3f}",
        "# TYPE cost_exporter_report_age_seconds gauge",
        f"cost_exporter_report_age_seconds {age:.3f}",
    ]
    for cloud, value in values.items():
        available = value is not None and not stale
        lines.append(f'cost_exporter_estimate_available{{cloud="{cloud}"}} {int(available)}')
        if available:
            lines.append(f'cloud_estimated_monthly_cost_usd{{cloud="{cloud}"}} {value}')
    return "\n".join(lines) + "\n"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            body = metrics(os.environ.get("COST_FILE", "/data/costs.json"),
                           int(os.environ.get("MAX_REPORT_AGE_SECONDS", "86400"))).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        elif self.path == "/healthz":
            body = b"exporter running\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
        else:
            self.send_error(404)
            return
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 9400), Handler).serve_forever()
