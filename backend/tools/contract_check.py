#!/usr/bin/env python3
"""Static contract check between the Flutter app and the real backend.

Direction 1 (server -> app): every JSON key a Dart mapper READS must exist in genuine
server output captured in test/fixtures (nested at any depth).
Direction 2 (app -> server): every JSON key the app SENDS must be a key the SQL
functions actually read (`->` / `->>` in the migrations).

This does not replace running the Dart tests; it catches renamed/misspelt keys
without needing the Flutter SDK. Usage: python3 contract_check.py <project root>
"""
import json, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else '.'
dart = open(os.path.join(root, 'lib/data/supabase/json_mappers.dart'), encoding='utf-8').read()
fx_dir = os.path.join(root, 'test/fixtures')
mig_dir = os.path.join(root, 'backend/supabase/migrations')

def keys_of(v, out):
    if isinstance(v, dict):
        for k, x in v.items(): out.add(k); keys_of(x, out)
    elif isinstance(v, list):
        for x in v: keys_of(x, out)
    return out

def fx(*names):
    out = set()
    for n in names: keys_of(json.load(open(os.path.join(fx_dir, n + '.json'))), out)
    return out

ORDERS = ('order_completed', 'order_cancelled', 'order_online_paid')
MAP = {
    'userFromJson': ('user',), 'customerSummaryFromJson': ('customers',),
    'productFromJson': ('product', 'product_page', 'home'), 'productPageFromJson': ('product_page',),
    'voucherFromJson': ('voucher', 'home'), 'homeFromJson': ('home',),
    'customerDiscountFromJson': ('customer_discount',), 'orderFromJson': ORDERS + ('order_list',),
    'feedbackFromJson': ('feedback_list',), 'suggestionFromJson': ('suggestions',),
    'restockFromJson': ('restocks',), 'notificationFromJson': ('notifications',),
    'measurementsFromJson': (),   # keys are MeasurementField names, checked below
}

# split the Dart file into top-level functions
funcs = {}
for m in re.finditer(r'^(?:[\w<>?, ]+?)\s+(\w+FromJson|\w+ToJson|productPageFromJson)\(', dart, re.M):
    funcs[m.group(1)] = m.start()
names = sorted(funcs, key=funcs.get)
bodies = {n: dart[funcs[n]: (funcs[names[i + 1]] if i + 1 < len(names) else len(dart))] for i, n in enumerate(names)}

problems, checked = [], 0
for fn, fixtures in MAP.items():
    if fn not in bodies or not fixtures: continue
    read = set(re.findall(r"\w+\['(\w+)'\]", bodies[fn]))
    avail = fx(*fixtures)
    # nested mappers called from this one are checked on their own
    for k in sorted(read):
        checked += 1
        if k not in avail: problems.append(f"{fn} reads '{k}' but the server never returns it (fixtures: {fixtures})")

# measurement fields AND their sanity ranges must match what the server validates
mtext = open(os.path.join(root, 'lib/models/measurements.dart'), encoding='utf-8').read()
srv = open(os.path.join(mig_dir, '20261020000002_helpers_pricing.sql'), encoding='utf-8').read()
server_ranges = {n: (int(a), int(b)) for n, a, b in re.findall(r"\('(\w+)',(\d+),(\d+)\)", srv)}
enum_body = re.search(r'enum MeasurementField \{(.*?)\n\}', mtext, re.S).group(1)
dart_fields = set(re.findall(r'^\s+(\w+),', enum_body, re.M))

def getter(name):
    body = re.search(r'double get ' + name + r' \{(.*?)\n  \}', mtext, re.S).group(1)
    out, pending = {}, []
    for line in body.splitlines():
        c = re.search(r'case MeasurementField\.(\w+):', line)
        r = re.search(r'return (\d+);', line)
        if c: pending.append(c.group(1))
        elif r:
            for f in pending: out[f] = int(r.group(1))
            pending = []
    return out
dmin, dmax = getter('minCm'), getter('maxCm')
dart_ranges = {f: (dmin.get(f), dmax.get(f)) for f in dart_fields}
if dart_fields != set(server_ranges):
    problems.append(f"measurement fields differ: dart-only={sorted(dart_fields - set(server_ranges))} server-only={sorted(set(server_ranges) - dart_fields)}")
for f in sorted(dart_fields & set(server_ranges)):
    checked += 1
    if dart_ranges[f] != server_ranges[f]:
        problems.append(f"measurement range differs for {f}: app={dart_ranges[f]} server={server_ranges[f]}")

# app -> server: keys written by the request builders must be read by SQL
sql_text = ''.join(open(os.path.join(mig_dir, f), encoding='utf-8').read() for f in sorted(os.listdir(mig_dir)))
sql_keys = set(re.findall(r"->>?\s*'(\w+)'", sql_text))
for fn in ('productToJson', 'orderRequestToJson'):
    body = bodies[fn]
    written = set(re.findall(r"^\s+(?:if \([^)]*\) )?'(\w+)':", body, re.M)) | set(re.findall(r"\{'(\w+)':", body)) | set(re.findall(r", '(\w+)':", body))
    for k in sorted(written):
        checked += 1
        if k not in sql_keys: problems.append(f"{fn} sends '{k}' but no SQL function reads it")

# RPC parameter names the repositories pass must exist as SQL parameters
repo = open(os.path.join(root, 'lib/data/supabase/supabase_repositories.dart'), encoding='utf-8').read() + \
       open(os.path.join(root, 'lib/data/supabase/aamarpay_gateway.dart'), encoding='utf-8').read()
sig = {}
for m in re.finditer(r"create function public\.(\w+)\((.*?)\)\s*(?:returns|language)", sql_text, re.S):
    params = re.findall(r"\b(p_\w+|p)\s+[a-z\[\]_ ]+", m.group(2))
    sig[m.group(1)] = set(params)
for m in re.finditer(r"_rpc\.call\(\s*'(\w+)'(?:,\s*\{(.*?)\}\s*\))?", repo, re.S):
    fn, body = m.group(1), m.group(2) or ''
    if fn not in sig: problems.append(f"RPC '{fn}' is called by the app but not defined in the migrations"); continue
    for k in re.findall(r"'(p_?\w*)':", body):
        checked += 1
        if k not in sig[fn]: problems.append(f"RPC {fn} called with unknown parameter '{k}' (server has {sorted(sig[fn])})")
for m in re.finditer(r"await _rpc\.call\('(\w+)'\)", repo):
    if m.group(1) not in sig: problems.append(f"RPC '{m.group(1)}' not defined")

print(f"contract check: {checked} keys/parameters verified")
for p in problems: print("PROBLEM:", p)
print("RESULT:", "OK" if not problems else f"{len(problems)} PROBLEM(S)")
sys.exit(1 if problems else 0)
