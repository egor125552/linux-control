#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import re, urllib.request, html
url='https://gdc.sonniss.com/'
req=urllib.request.Request(url,headers={
 'User-Agent':'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/141 Safari/537.36',
 'Accept':'text/html,application/xhtml+xml'
})
data=urllib.request.urlopen(req,timeout=30).read().decode('utf-8','ignore')
print('PAGE_BYTES',len(data))
for href,text in re.findall(r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>(.*?)</a>',data,re.I|re.S):
    label=re.sub('<[^>]+>',' ',text)
    label=html.unescape(re.sub(r'\s+',' ',label)).strip()
    h=html.unescape(href)
    if 'GDC2026' in h or 'drive.google' in h or '.torrent' in h or 'GDC2026' in label:
        print(label[:120], '\t', h)
PY
