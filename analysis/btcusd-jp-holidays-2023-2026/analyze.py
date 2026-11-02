"""Reproduce the read-only MT5 holiday study. Python standard library only."""
import csv
import hashlib
import json
import math
import statistics as st
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
START, END = date(2023, 11, 3), date(2026, 11, 2)
SOURCES = {
    '日本祝日': 'https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv',
    '祝日法・国民の休日': 'https://www8.cao.go.jp/chosei/shukujitsu/gaiyou.html',
    'NYSE 2023': 'https://www.nyse.com/publicdocs/ICE_NYSE_2023_Yearly_Trading_Calendar.pdf',
    'NYSE 2024–2026': 'https://s2.q4cdn.com/154085107/files/doc_news/NYSE-Group-Announces-2024-2025-and-2026-Holiday-and-Early-Closings-Calendar-2023.pdf',
    'NYSE 臨時休場': 'https://ir.theice.com/press/news-details/2024/The-New-York-Stock-Exchange-Will-Close-Markets-on-January-9-to-Honor-the-Passing-of-Former-President-Jimmy-Carter-on-National-Day-of-Mourning/default.aspx',
    'LSE 営業日規則': 'https://www.londonstockexchange.com/en/resources/markets-products/business-days',
    '英国政府 過去年別祝日': 'https://www.gov.uk/bank-holidays',
    'LSE 2023年末短縮日 補助資料（Morningstar）': 'https://global.morningstar.com/en-gb/markets/is-the-stock-market-open-today-3',
    'LSE 過去年末短縮日 補助資料': 'https://trading.info/england-trading-hours/',
    'ThreeTrader 時刻規則': 'https://media.threetrader.com/threetrader-gmt/',
    'ThreeTrader 2024 DST': 'https://www.threetrader.com/jp/blog/us-daylight-saving-changes-march-2024',
    'ThreeTrader 2025 DST': 'https://www.threetrader.com/blog/us-daylight-saving-2025',
    'ThreeTrader 2026 DST': 'https://www.threetrader.com/jp/blog/2026-us-daylight-saving-time-start',
}

def dates(text):
    return {date.fromisoformat(s) for s in text.split()}

# Manually transcribed from the linked official calendars. Half days are excluded.
US_CLOSED = dates('''2023-11-23 2023-12-25
2024-01-01 2024-01-15 2024-02-19 2024-03-29 2024-05-27 2024-06-19 2024-07-04 2024-09-02 2024-11-28 2024-12-25
2025-01-01 2025-01-09 2025-01-20 2025-02-17 2025-04-18 2025-05-26 2025-06-19 2025-07-04 2025-09-01 2025-11-27 2025-12-25
2026-01-01 2026-01-19 2026-02-16 2026-04-03 2026-05-25 2026-06-19 2026-07-03 2026-09-07 2026-11-26 2026-12-25''')
US_HALF = dates('2023-11-24 2024-07-03 2024-11-29 2024-12-24 2025-07-03 2025-11-28 2025-12-24 2026-11-27 2026-12-24')
UK_CLOSED = dates('''2023-12-25 2023-12-26
2024-01-01 2024-03-29 2024-04-01 2024-05-06 2024-05-27 2024-08-26 2024-12-25 2024-12-26
2025-01-01 2025-04-18 2025-04-21 2025-05-05 2025-05-26 2025-08-25 2025-12-25 2025-12-26
2026-01-01 2026-04-03 2026-04-06 2026-05-04 2026-05-25 2026-08-31 2026-12-25 2026-12-28''')
UK_HALF = dates('2023-12-22 2023-12-29 2024-12-24 2024-12-31 2025-12-24 2025-12-31 2026-12-24 2026-12-31')

def nth_sunday(year, month, n):
    d = date(year, month, 1)
    return d + timedelta(days=(6-d.weekday()) % 7 + 7*(n-1))

def offset(d):
    # Only weekdays enter the study; intraday Sunday transition ambiguity is irrelevant.
    return 3 if nth_sunday(d.year, 3, 2) <= d < nth_sunday(d.year, 11, 1) else 2

def market(d, closed, half):
    return '週末' if d.weekday() >= 5 else '休場' if d in closed else '短縮営業' if d in half else '通常営業'

def write_csv(name, rows, fields=None):
    if fields is None:
        fields = list(rows[0]) if rows else []
    with (ROOT/name).open('w', newline='', encoding='utf-8-sig') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

def wilson(k, n):
    if not n:
        return [None, None]
    z = 1.959963984540054
    p = k/n
    center = (p+z*z/(2*n))/(1+z*z/n)
    half = z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/(1+z*z/n)
    return [100*(center-half), 100*(center+half)]

def stats(rows):
    vals = [r['return_pct'] for r in rows]
    up = [v for v in vals if v > 0]
    down = [v for v in vals if v < 0]
    if not rows:
        return {'n': 0}
    return dict(n=len(vals), up=len(up), down=len(down), flat=vals.count(0),
                up_pct=100*len(up)/len(vals), down_pct=100*len(down)/len(vals), flat_pct=100*vals.count(0)/len(vals),
                mean_pct=st.mean(vals), median_pct=st.median(vals),
                mean_up_pct=st.mean(up) if up else None, mean_down_pct=st.mean(down) if down else None,
                up_ci95=wilson(len(up),len(vals)),
                best=max(rows,key=lambda r:r['return_pct']), worst=min(rows,key=lambda r:r['return_pct']))

def fisher(a,b,c,d):
    n, k, draws = a+b+c+d, a+c, a+b
    def prob(x):
        return math.comb(k,x)*math.comb(n-k,draws-x)/math.comb(n,draws)
    observed=prob(a)
    return min(1., sum(prob(x) for x in range(max(0, draws-(n-k)),min(k,draws)+1) if prob(x)<=observed*(1+1e-12)))

def main():
    with (ROOT/'japan_holidays_official.csv').open(encoding='cp932',newline='') as f:
        jp={datetime.strptime(r[0],'%Y/%m/%d').date():r[1] for r in list(csv.reader(f))[1:]}
    h1=json.loads((ROOT/'raw_h1.json').read_text(encoding='utf-8'))['history']
    h4=json.loads((ROOT/'raw_h4.json').read_text(encoding='utf-8'))['history']
    maps={p:{r['time']:r for r in rows} for p,rows in [('H1',h1),('H4',h4)]}
    assert all(len(maps[p])==len(rows) for p,rows in [('H1',h1),('H4',h4)]), 'Duplicate timestamps'
    assert all(r['low']<=min(r['open'],r['close'])<=max(r['open'],r['close'])<=r['high'] for r in h1+h4)
    audit=[]; exact=[]; approximate=[]; missing=[]
    d=START
    while d<=END:
        us,uk=market(d,US_CLOSED,US_HALF),market(d,UK_CLOSED,UK_HALF)
        holiday=jp.get(d,'')
        # Distinguish the extra statutory citizen holiday from holidays/substitutes.
        citizen=d==date(2026,9,22)
        name=('国民の休日' if citizen else '振替休日' if holiday=='休日' else holiday)
        kind='国民の休日' if citizen else '祝日' if holiday else '通常平日'
        row=dict(date=d.isoformat(),weekday='月火水木金土日'[d.weekday()],holiday_name=name,
                 official_holiday_name=holiday,group=kind,nyse=us,lse=uk,server_utc_offset=offset(d))
        if d.weekday()>=5:
            row['status']='週末除外'
        elif us!='通常営業' or uk!='通常営業':
            row['status']='海外営業条件で除外'
        else:
            base=datetime.combine(d,datetime.min.time())
            # 09:00 JST = 00:00 UTC. 16:00 JST = 07:00 UTC.
            start=base+timedelta(hours=offset(d))
            end=start+timedelta(hours=7)
            keys=[(start+timedelta(hours=i)).isoformat() for i in range(8)]
            absent=[k for k in keys if k not in maps['H1']]
            if absent:
                row['status']='H1欠損除外'
                missing.append(dict(date=d.isoformat(),group=kind,missing_server_times=';'.join(absent)))
            else:
                a,b=maps['H1'][keys[0]]['open'],maps['H1'][keys[-1]]['open']
                ret=(b-a)/a*100
                result={**row,'start_jst':d.isoformat()+'T09:00:00+09:00','end_jst':d.isoformat()+'T16:00:00+09:00',
                        'start_server':keys[0],'end_server':keys[-1],'start_price':a,'end_price':b,
                        'return_pct':ret,'direction':'上昇' if b>a else '下落' if b<a else '横ばい',
                        'method':'H1 open-to-open'}
                exact.append(result)
                row['status']='採用' if not citizen else '国民の休日・別集計'
            # Separate H4 nearest-boundary open-to-open sensitivity, never pooled.
            # At the 09:00 winter tie (07:00/11:00), retain an 8-hour window.
            s=base+timedelta(hours=0 if offset(d)==2 else 4)
            e=base+timedelta(hours=8 if offset(d)==2 else 12)
            sa,ea=maps['H4'].get(s.isoformat()),maps['H4'].get(e.isoformat())
            if sa and ea:
                approximate.append({**row,'start_jst':(s+timedelta(hours=9-offset(d))).isoformat()+'+09:00',
                    'end_jst':(e+timedelta(hours=9-offset(d))).isoformat()+'+09:00',
                    'start_server':s.isoformat(),'end_server':e.isoformat(),
                    'start_price':sa['open'],'end_price':ea['open'],
                    'direction':'上昇' if ea['open']>sa['open'] else '下落' if ea['open']<sa['open'] else '横ばい',
                    'return_pct':(ea['open']-sa['open'])/sa['open']*100,'method':'H4 nearest boundary open-to-open'})
        audit.append(row)
        d+=timedelta(days=1)
    holidays=[r for r in exact if r['group']=='祝日']
    regular=[r for r in exact if r['group']=='通常平日']
    all_holidays=[r for r in exact if r['group']!='通常平日']
    sh,sr=stats(holidays),stats(regular)
    byyear={str(y):stats([r for r in holidays if r['date'].startswith(str(y))]) for y in range(2023,2027)}
    # Newcombe independent Wilson interval for difference in upward probabilities.
    p,q=sh['up_pct'],sr['up_pct']; l1,u1=sh['up_ci95']; l2,u2=sr['up_ci95']
    difference=dict(up_difference_pp=p-q,ci95_pp=[p-q-math.sqrt((p-l1)**2+(u2-q)**2),p-q+math.sqrt((u1-p)**2+(q-l2)**2)],
        fisher_two_sided_p=fisher(sh['up'],sh['n']-sh['up'],sr['up'],sr['n']-sr['up']))
    metadata={}
    for period,rows,step in [('H1',h1,1),('H4',h4,4)]:
        expected=[]; present=maps[period]
        t=datetime(2023,11,3); stop=datetime(2026,11,3)
        while t<stop:
            if t.isoformat() not in present:
                expected.append({'period':period,'server_time':t.isoformat(),'server_weekday':'月火水木金土日'[t.weekday()]})
            t+=timedelta(hours=step)
        write_csv('missing_'+period.lower()+'_bars.csv',expected,['period','server_time','server_weekday'])
        gaps=[]
        for r in expected:
            t=datetime.fromisoformat(r['server_time'])
            if gaps and datetime.fromisoformat(gaps[-1]['last_missing_server'])+timedelta(hours=step)==t:
                gaps[-1]['last_missing_server']=r['server_time']; gaps[-1]['bars']+=1
            else:
                gaps.append(dict(first_missing_server=r['server_time'],last_missing_server=r['server_time'],bars=1))
        write_csv('missing_'+period.lower()+'_intervals.csv',gaps)
        metadata[period]=dict(retrieved=len(rows),in_requested_server_date_range=sum('2023-11-03'<=r['time'][:10]<='2026-11-02' for r in rows),
            first_server=rows[0]['time'],last_server=rows[-1]['time'],missing_grid_bars=len(expected),missing_intervals=len(gaps),
            missing_weekday_bars=sum(datetime.fromisoformat(r['server_time']).weekday()<5 for r in expected),
            duplicates=len(rows)-len(maps[period]),ohlc_valid=True)
        write_csv('raw_'+period.lower()+'.csv',rows,['time','open','high','low','close','tick_volume','spread'])
    for name,rows in [('holiday_details.csv',holidays),('regular_weekdays.csv',regular),('citizen_holiday_sensitivity.csv',[r for r in exact if r['group']=='国民の休日']),('calendar_audit.csv',audit),('h4_approximation_separate.csv',approximate),('missing_analysis_days.csv',missing)]:
        write_csv(name,rows, list(rows[0]) if rows else ['date','group','missing_server_times'])
    write_csv('summary.csv',[{'group':g,**{k:v for k,v in s.items() if k not in ('best','worst','up_ci95')},'up_ci95_low':s.get('up_ci95',[None,None])[0],'up_ci95_high':s.get('up_ci95',[None,None])[1]} for g,s in [('祝日',sh),('通常平日',sr),*byyear.items()]])
    summary=dict(holiday=sh,regular=sr,yearly=byyear,difference=difference,including_citizen_holiday=stats(all_holidays),
        h4_holiday_separate=stats([r for r in approximate if r['group']=='祝日']),data=metadata,
        calendar_counts=dict(Counter(r['status'] for r in audit)),holiday_calendar_counts=dict(Counter(r['status'] for r in audit if r['holiday_name'])),
        missing_analysis_days=missing,sources=SOURCES,
        sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['raw_h1.json','raw_h4.json','japan_holidays_official.csv']})
    (ROOT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k in ('difference','data','calendar_counts','holiday_calendar_counts')},ensure_ascii=True,indent=2))

if __name__=='__main__':
    main()
