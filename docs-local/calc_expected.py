import json, sys, datetime, pathlib

path = pathlib.Path(sys.argv[1])
d = json.loads(path.read_text())
now = datetime.datetime(2026, 9, 17, 18, 0, 0, tzinfo=datetime.timezone.utc)

def parse(value):
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))

threshold = d["app"]["alertThresholdDays"]
print("version:", d["version"], "items:", len(d["items"]), "threshold:", threshold)
rows = []
for it in d["items"]:
    elapsed = (now - parse(it["lastPurchased"])).total_seconds() / 86400
    rate = it["consumptionRatePerDay"]
    rem_stock = it["currentStock"] - rate * elapsed
    rem_days = rem_stock / rate
    rows.append((it["name"], it["unit"], rate, elapsed, rem_stock, rem_days, rem_days <= threshold))
    print("%-18s unit=%-3s stock=%-8s rate=%.12f elapsed=%.6f rem_stock=%.6f rem_days=%.6f alert=%s"
          % (it["name"], it["unit"], it["currentStock"], rate, elapsed, rem_stock, rem_days, rem_days <= threshold))

print("alerts:", [r[0] for r in rows if r[6]])
print("unitPreferences:", len(d["app"]["unitPreferences"]), "notificationRecords:", len(d["app"]["notificationRecords"]))
print("nonFinite:", any(not (r[2] > 0) for r in rows))
