"""Independent checks of saved inputs, daily returns and calendar boundaries."""
import csv
import hashlib
import json
import math
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT=Path(__file__).resolve().parent
def rows(name):
    with (ROOT/name).open(encoding='utf-8-sig',newline='') as f:
        return list(csv.DictReader(f))
s=json.loads((ROOT/'summary.json').read_text(encoding='utf-8'))
h1={r['time']:r for r in json.loads((ROOT/'raw_h1.json').read_text(encoding='utf-8'))['history']}
audit={r['date']:r for r in rows('calendar_audit.csv')}
daily=rows('holiday_details.csv')+rows('regular_weekdays.csv')+rows('citizen_holiday_sensitivity.csv')
for r in daily:
    # Independent IANA US DST conversion rather than analyze.py's nth-Sunday rule.
    utc=datetime.fromisoformat(r['start_jst']).astimezone(ZoneInfo('UTC'))
    ny_dst=bool(utc.astimezone(ZoneInfo('America/New_York')).dst())
    server=(utc.replace(tzinfo=None)+timedelta(hours=3 if ny_dst else 2)).isoformat()
    end=(datetime.fromisoformat(server)+timedelta(hours=7)).isoformat()
    assert server==r['start_server'] and end==r['end_server']
    a,b=h1[server]['open'],h1[end]['open']
    assert a==float(r['start_price']) and b==float(r['end_price'])
    assert math.isclose((b/a-1)*100,float(r['return_pct']),abs_tol=1e-10)
    assert r['nyse']==r['lse']=='通常営業'
    assert datetime.fromisoformat(r['date']).weekday()<5
for filename,group in [('holiday_details.csv','holiday'),('regular_weekdays.csv','regular')]:
    rr=rows(filename)
    assert len(rr)==s[group]['n']
    assert sum(float(r['end_price'])>float(r['start_price']) for r in rr)==s[group]['up']
    assert sum(float(r['return_pct']) for r in rr)/len(rr)==s[group]['mean_pct'] or math.isclose(sum(float(r['return_pct']) for r in rr)/len(rr),s[group]['mean_pct'],abs_tol=1e-12)
assert audit['2025-01-09']['nyse']=='休場'
assert audit['2024-07-03']['nyse']=='短縮営業'
assert audit['2023-12-22']['lse']=='短縮営業'
assert audit['2023-12-29']['lse']=='短縮営業'
assert audit['2024-05-06']['lse']=='休場'
assert audit['2026-09-22']['group']=='国民の休日'
assert len(daily)==728 and len(audit)==1096
assert not s['missing_analysis_days']
for name,digest in s['sha256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
print(f'PASS: {len(daily)} daily returns, IANA DST, calendar exclusions, summaries and input hashes')
