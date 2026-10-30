"""Python port of SunCalc.swift's elevation(), checked against published sunrise/sunset times."""
import math
from datetime import datetime, timezone

def elevation(dt, lat, lon):
    rad = math.pi / 180
    jd = dt.timestamp() / 86400.0 + 2440587.5
    t = (jd - 2451545.0) / 36525.0
    l0 = math.fmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360)
    if l0 < 0: l0 += 360
    m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
    e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    c = (math.sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
         + math.sin(2 * m * rad) * (0.019993 - 0.000101 * t) + math.sin(3 * m * rad) * 0.000289)
    true_long = l0 + c
    omega = 125.04 - 1934.136 * t
    app = true_long - 0.00569 - 0.00478 * math.sin(omega * rad)
    eps0 = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
    eps = eps0 + 0.00256 * math.cos(omega * rad)
    decl = math.asin(math.sin(eps * rad) * math.sin(app * rad))
    y = math.tan(eps * rad / 2) ** 2
    eot = 4 / rad * (y * math.sin(2 * l0 * rad) - 2 * e * math.sin(m * rad)
                     + 4 * e * y * math.sin(m * rad) * math.cos(2 * l0 * rad)
                     - 0.5 * y * y * math.sin(4 * l0 * rad) - 1.25 * e * e * math.sin(2 * m * rad))
    frac = (jd + 0.5) - math.floor(jd + 0.5)
    tst = math.fmod(frac * 1440 + eot + 4 * lon, 1440)
    if tst < 0: tst += 1440
    ha = tst / 4 - 180
    if ha < -180: ha += 360
    latr = lat * rad
    cz = math.sin(latr) * math.sin(decl) + math.cos(latr) * math.cos(decl) * math.cos(ha * rad)
    zen = math.acos(min(max(cz, -1), 1)) / rad
    return 90 - zen, ha < 0

def light(dt, lat, lon):
    el, morning = elevation(dt, lat, lon)
    side = "morning" if morning else "evening"
    if el < -6: return "Night"
    if el < 0: return f"Blue hour ({side})"
    if el < 6: return f"Golden hour ({side})"
    return "Day"

cases = [
    # place, lat, lon, UTC time, expected: elevation near -0.83 (sunrise/sunset) and morning flag
    ("London sunrise 21 Jun 2024 04:43 BST", 51.5074, -0.1278, datetime(2024, 6, 21, 3, 43, tzinfo=timezone.utc), True),
    ("London sunset 21 Jun 2024 21:21 BST", 51.5074, -0.1278, datetime(2024, 6, 21, 20, 21, tzinfo=timezone.utc), False),
    ("New York sunrise 21 Dec 2024 07:16 EST", 40.7128, -74.0060, datetime(2024, 12, 21, 12, 16, tzinfo=timezone.utc), True),
    ("New York sunset 21 Dec 2024 16:32 EST", 40.7128, -74.0060, datetime(2024, 12, 21, 21, 32, tzinfo=timezone.utc), False),
    ("Sydney sunrise 21 Dec 2024 05:41 AEDT", -33.8688, 151.2093, datetime(2024, 12, 20, 18, 41, tzinfo=timezone.utc), True),
    ("Sydney sunset 21 Dec 2024 20:05 AEDT", -33.8688, 151.2093, datetime(2024, 12, 21, 9, 5, tzinfo=timezone.utc), False),
]
bad = 0
for name, lat, lon, dt, morning_expected in cases:
    el, morning = elevation(dt, lat, lon)
    ok = abs(el - (-0.83)) < 0.6 and morning == morning_expected
    bad += not ok
    print(f"{'ok ' if ok else 'BAD'} {name}: elevation {el:+.2f}°, morning={morning}")
noon, _ = elevation(datetime(2024, 6, 21, 12, 2, tzinfo=timezone.utc), 51.5074, -0.1278)
print(f"{'ok ' if abs(noon - 61.9) < 0.5 else 'BAD'} London solar noon 21 Jun: {noon:.2f}° (expect ~61.9)")
# A Brisbane morning walk-through, AEST = UTC+10
for hh, mm in [(4, 20), (4, 52), (5, 15), (5, 40), (7, 0), (17, 50), (18, 20), (19, 0)]:
    utc_hour = (hh - 10) % 24
    day = 8 if hh >= 10 else 7
    dt = datetime(2026, 11, day, utc_hour, mm, tzinfo=timezone.utc)
    print(f"   Brisbane 8 Nov 2026 {hh:02d}:{mm:02d} -> {light(dt, -27.4698, 153.0251)} ({elevation(dt, -27.4698, 153.0251)[0]:+.1f}°)")
raise SystemExit(bad)
