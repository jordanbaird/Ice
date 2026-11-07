#!/usr/bin/env python3
"""Resume os signposts do Trincano (duracao por intervalo: n, p50, p95, max).

Uso: scripts/measure-signposts.py [minutos=10]
"""
import json
import statistics
import subprocess
import sys
from collections import defaultdict

minutes = sys.argv[1] if len(sys.argv) > 1 else "10"
out = subprocess.run(
    ["/usr/bin/log", "show", "--last", f"{minutes}m", "--signpost", "--style", "ndjson",
     "--predicate", 'subsystem == "br.com.pilutech.trincano" AND category == "Performance"'],
    capture_output=True, text=True, check=False).stdout

begins, durations, events = {}, defaultdict(list), defaultdict(int)
threads = defaultdict(set)
for line in out.splitlines():
    try:
        e = json.loads(line)
    except ValueError:
        continue
    kind = e.get("signpostType")
    name = e.get("signpostName")
    sid = e.get("signpostID")
    t = e.get("machTimestamp")
    if kind == "begin":
        begins[(name, sid)] = t
        threads[name].add(e.get("threadID"))
    elif kind == "end" and (name, sid) in begins:
        durations[name].append(t - begins.pop((name, sid)))  # em ticks do timebase
    elif kind == "event":
        events[name] += 1

# machTimestamp esta em ticks do timebase; converte para ns.
import ctypes
class TB(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]
tb = TB()
ctypes.CDLL("/usr/lib/libSystem.dylib").mach_timebase_info(ctypes.byref(tb))
factor = tb.numer / tb.denom

# A thread principal e a que processa os eventos de mouse / abre secoes.
main_threads = threads.get("hid.mouseMoved", set()) | threads.get("hid.mouseDown", set()) | threads.get("section.show", set()) | threads.get("cacheItems", set())
print(f"{'signpost':28} {'n':>6} {'p50 ms':>9} {'p95 ms':>9} {'max ms':>9}  thread")
for name, ds in sorted(durations.items()):
    ms = sorted(d * factor / 1e6 for d in ds)  # ticks * factor = ns; / 1e6 = ms
    p95 = ms[min(len(ms) - 1, int(len(ms) * 0.95))]
    where = "main" if threads[name] and threads[name] <= main_threads else "fora da main"
    print(f"{name:28} {len(ms):6d} {statistics.median(ms):9.3f} {p95:9.3f} {ms[-1]:9.3f}  {where}")
for name, n in sorted(events.items()):
    print(f"{name:28} {n:6d}  (eventos)")
