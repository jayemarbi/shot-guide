"""A Python model of Shot Guide's creative coverage (1.19), with tests.

There's no Swift compiler here, so this ports the rules in Models/Coverage.swift and checks them against
scenarios. The tables (roles, targets, tiers, light-day takes, trip-type tuning, the day's order) are read from
the Swift source, so the model can't drift from them. The logic is a port: keep it in step with Coverage.swift.
It checks the rules, not the Swift code itself; the app's build and a phone test do that.

usage: python3 tools/test_coverage.py [repo folder]
"""
import re
import sys
from dataclasses import dataclass, field, replace
from datetime import datetime, timedelta
from math import asin, cos, radians, sin, sqrt
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
MODELS = ROOT / "ShotGuide" / "Models"
SHOT_SRC = (MODELS / "ShotType.swift").read_text(encoding="utf-8")
COVERAGE_SRC = (MODELS / "Coverage.swift").read_text(encoding="utf-8")
TYPE_SRC = (MODELS / "TripType.swift").read_text(encoding="utf-8")
PHASE_SRC = (MODELS / "TripPhase.swift").read_text(encoding="utf-8")

# ---------------------------------------------------------------- tables, read from the Swift source

RAW = dict(re.findall(r'case (\w+) = "(\w+)"', SHOT_SRC.split("enum ShotType")[1].split("}")[0]))


def switch_values(src, header, default):
    """`var x: T { switch self { case .a, .b: return V ... default: return D } }` → {case: V}."""
    body = src.split(header, 1)[1].split("\n    }\n", 1)[0]
    values = {}
    for cases, value in re.findall(r"case ([.\w, \n]+?):\s*return ([.\w]+)", body):
        for case in re.findall(r"\.(\w+)", cases):
            values[case] = value.lstrip(".")
    return {shot: values.get(shot, default) for shot in RAW}


TARGET = {k: int(v) for k, v in switch_values(SHOT_SRC, "var targetTakes: Int {", "1").items()}
TIER = switch_values(COVERAGE_SRC, "var tier: ShotTier {", "extra")
LIGHT = {k: int(v) for k, v in switch_values(COVERAGE_SRC, "var lightDayTakes: Int {", "0").items()}


@dataclass(frozen=True)
class Role:
    id: str
    title: str
    in_shot: object = None
    optional: bool = False
    substitute: bool = False


def read_roles():
    body = COVERAGE_SRC.split("var roles: [CoverageRole] {", 1)[1].split("default:\n            return []", 1)[0]
    roles = {}
    for case, chunk in re.findall(r"case \.(\w+):(.*?)(?=\n        case \.|\Z)", body, re.S):
        found = []
        for call in chunk.split("CoverageRole(")[1:]:
            ident, title = re.match(r'id: "([^"]+)", title: "([^"]+)"', call).groups()
            in_shot = re.search(r"inShot: (true|false)", call)
            found.append(Role(ident, title, None if not in_shot else in_shot.group(1) == "true",
                              "isOptional: true" in call, "isSubstitute: true" in call))
        roles[case] = found
    return roles


ROLES = read_roles()


def read_tuning():
    tuning = {}
    for name, body in re.findall(r"static let (\w+)Tuning: \[ShotType: ShotTuning\] = \[(.*?)\n    \]", TYPE_SRC, re.S):
        entries = {}
        for shot, args in re.findall(r"\.(\w+): ShotTuning\((.*?)\)(?:,|\n)", body):
            target = re.search(r"target: (\d+)", args)
            tier = re.search(r"tier: \.(\w+)", args)
            entries[shot] = (int(target.group(1)) if target else None, tier.group(1) if tier else None)
        tuning[name] = entries
    tuning["general"] = {}
    return tuning


TUNING = read_tuning()


def read_slots():
    body = PHASE_SRC.split("var slots: [ShotSlot] {", 1)[1].split("\n    }\n", 1)[0]
    slots = []
    for phase, chunk in re.findall(r"case \.(\w+):(.*?)(?=\n        case \.|\Z)", body, re.S):
        if "shots.map" in chunk:
            for shot in re.findall(r"\.(\w+)", chunk.split("[ShotType] = [")[1].split("]")[0]):
                slots.append((shot, None))
        else:
            for shot, half in re.findall(r"ShotSlot\(shot: \.(\w+), half: (\w+)\)", chunk):
                slots.append((shot, None if half == "nil" else int(half)))
    return slots


SLOTS = read_slots()
VARIANTS = {"reveal": ["Auto zoom", "Walk reveal", "Tilt up"], "whip": ["Out", "In"], "home": ["Before", "After"],
            "talk": ["Tripod", "Walking"]}


def target(shot, trip_type):
    tuned = TUNING[trip_type].get(shot)
    return tuned[0] if tuned and tuned[0] is not None else TARGET[shot]


def tier(shot, trip_type):
    tuned = TUNING[trip_type].get(shot)
    return tuned[1] if tuned and tuned[1] is not None else TIER[shot]


def slot_target(slot, trip_type):
    shot, half = slot
    return 1 if half is not None else target(shot, trip_type)


def light_target(slot, trip_type):
    shot, half = slot
    return 0 if half is not None or tier(shot, trip_type) != "core" else min(LIGHT[shot], target(shot, trip_type))


def goal(slot, level, trip_type):
    t = tier(slot[0], trip_type)
    if t == "core":
        return light_target(slot, trip_type) if level == "light" else slot_target(slot, trip_type)
    if t == "fullDay":
        return slot_target(slot, trip_type) if level == "full" else 0
    return 0

# ---------------------------------------------------------------- clips and the rules (Coverage.swift)


@dataclass
class Clip:
    id: str
    shot: str                 # raw value, like "WIDE"
    take: int
    at: datetime
    day: int = 1
    role: str = None
    variant: str = None
    in_shot: bool = False
    check_passed: object = None
    duration: float = 20
    planned: object = None
    usable: object = None
    favourite: bool = False
    added: bool = False
    lat: object = None
    lon: object = None
    scene: object = None
    scene_confirmed: object = None
    name: object = None

    @property
    def case(self):
        return next((k for k, v in RAW.items() if v == self.shot), None)

    @property
    def role_id(self):
        case = self.case
        ids = [r.id for r in ROLES.get(case, [])]
        if self.role is not None:
            return self.role if self.role in ids else None
        if self.added:
            return None
        if case == "reveal":
            names = VARIANTS["reveal"]
            return ids[names.index(self.variant)] if self.variant in names else None
        if case == "walkaway":
            return "new-spot" if self.take % 2 == 0 else "into-view"
        if case == "wide":
            if self.in_shot:
                return "human-scale"
            return "alternative" if self.take % 2 == 0 else "establishing"
        return None

    @property
    def stopped_short(self):
        if self.added:
            return False
        if self.planned:
            return self.duration < self.planned * 0.6
        return self.duration < 3

    @property
    def technically_ok(self):
        return self.check_passed is not False and not self.stopped_short

    @property
    def counts(self):
        return self.usable if self.usable is not None else self.technically_ok

    @property
    def confirmed(self):
        return self.usable if self.usable is not None else (self.favourite and self.technically_ok)


def coverage(clips, slot, day, trip_type):
    shot, half = slot
    want = slot_target(slot, trip_type)
    takes = [c for c in clips if c.shot == RAW[shot] and c.day == day]
    if half is not None:
        takes = [c for c in takes if c.variant == VARIANTS[shot][half]]
    takes.sort(key=lambda c: (not c.confirmed, c.at))
    statuses = {}
    for c in takes:
        if not c.counts:
            statuses[c.id] = "rejected" if c.usable is False else ("retake" if c.check_passed is False else "short")
    usable = [c for c in takes if c.counts]
    roles = ROLES.get(shot, []) if half is None else []
    done = 0
    lines = {}

    def fill(c):
        nonlocal done
        statuses[c.id] = "confirmed" if c.confirmed else "provisional"
        done += 1

    if not roles:
        for c in usable:
            if done < want:
                fill(c)
            else:
                statuses[c.id] = "extra"
    else:
        by_role, unsorted = {}, []
        for c in usable:
            (by_role.setdefault(c.role_id, []) if c.role_id else unsorted).append(c)
        ordered = [r for r in roles if not r.optional and not r.substitute] + [r for r in roles if r.substitute]
        for r in ordered:
            if done < want and by_role.get(r.id):
                fill(by_role[r.id][0])
        for c in unsorted:
            if done < want:
                fill(c)
        for c in usable:
            statuses.setdefault(c.id, "extra")
        for r in roles:
            filmed = [c for c in takes if c.role_id == r.id]
            lines[r.id] = sum(1 for c in filmed if c.counts)
    open_roles = set() if done >= want else {r.id for r in roles if not r.optional and not lines.get(r.id)}
    return {"target": want, "done": done, "statuses": statuses, "lines": lines, "open": open_roles,
            "complete": done >= want}


def next_role(shot, current, open_ids):
    usual = [r for r in ROLES.get(shot, []) if not r.optional and not r.substitute]
    ids = [r.id for r in usual]
    start = ids.index(current) + 1 if current in ids else 0
    for r in usual[start:] + usual[:start]:
        if r.id in open_ids:
            return r.id
    return next((r.id for r in ROLES.get(shot, []) if r.substitute and r.id in open_ids), None)


def day_coverage(clips, day, trip_type):
    result = {level: [0, 0] for level in ("light", "everyday", "full")}
    for slot in SLOTS:
        if goal(slot, "full", trip_type) == 0:
            continue
        cov = coverage(clips, slot, day, trip_type)
        for level in result:
            g = goal(slot, level, trip_type)
            result[level][0] += min(cov["done"], g)
            result[level][1] += g
    return result


def missing(clips, level, day, trip_type):
    out = []
    for slot in SLOTS:
        g = goal(slot, level, trip_type)
        if g == 0:
            continue
        cov = coverage(clips, slot, day, trip_type)
        need = g - min(cov["done"], g)
        if need > 0:
            out.append((slot, need, sorted(cov["open"])))
    return out

# ---------------------------------------------------------------- scenes


def distance(lat1, lon1, lat2, lon2):
    p1, p2 = radians(lat1), radians(lat2)
    a = sin((p2 - p1) / 2) ** 2 + cos(p1) * cos(p2) * sin(radians(lon2 - lon1) / 2) ** 2
    return 2 * 6_371_000 * asin(sqrt(a))


def is_new_scene(prev, lat, lon, at):
    if None not in (prev.lat, prev.lon, lat, lon):
        return distance(prev.lat, prev.lon, lat, lon) > 1000
    return (at - prev.at).total_seconds() > 45 * 60


def scene_numbers(clips, day):
    day_clips = sorted((c for c in clips if c.day == day), key=lambda c: c.at)
    nxt = max([c.scene for c in day_clips if c.scene] or [0]) + 1
    result, prev, current = {}, None, None
    for c in day_clips:
        if c.scene:
            current = c.scene
        elif prev is not None and current is not None and not is_new_scene(prev, c.lat, c.lon, c.at):
            pass
        else:
            current, nxt = nxt, nxt + 1
        result[c.id] = current
        prev = c
    return result


def scene_for_new_clip(clips, day, lat, lon, at, choice=None):
    numbers = scene_numbers(clips, day)
    highest = max(numbers.values() or [0])
    day_clips = [c for c in clips if c.day == day]
    if not day_clips:
        return highest + 1, choice is not None
    last = max(day_clips, key=lambda c: c.at)
    if choice is not None:
        return (highest + 1 if choice else numbers[last.id]), True
    if is_new_scene(last, lat, lon, at):
        return highest + 1, False
    return numbers[last.id], False


def fix_scenes(clips, day):
    numbers = scene_numbers(clips, day)
    for c in clips:
        if c.day == day and not c.scene:
            c.scene = numbers[c.id]


def merge_scene(clips, scene, day):
    fix_scenes(clips, day)
    order = []
    for c in sorted((c for c in clips if c.day == day), key=lambda c: c.at):
        if c.scene not in order:
            order.append(c.scene)
    position = order.index(scene)
    if position == 0:
        return
    for c in clips:
        if c.day == day and c.scene == scene:
            c.scene, c.scene_confirmed = order[position - 1], True


def split_scene(clips, clip_id):
    clip = next(c for c in clips if c.id == clip_id)
    fix_scenes(clips, clip.day)
    current = clip.scene
    new = max(c.scene for c in clips if c.day == clip.day) + 1
    for c in clips:
        if c.day == clip.day and c.scene == current and c.at >= clip.at:
            c.scene, c.scene_confirmed = new, True

# ---------------------------------------------------------------- tests

results = []


def check(name, condition, detail=""):
    results.append((name, bool(condition), detail))


T0 = datetime(2026, 11, 8, 9, 0)
counter = [0]


def clip(shot, role=None, **kw):
    counter[0] += 1
    same = [c for c in kw.pop("existing", []) if c.shot == shot and c.day == kw.get("day", 1)]
    take = kw.pop("take", max([c.take for c in same] or [0]) + 1)
    at = kw.pop("at", T0 + timedelta(minutes=counter[0]))
    return Clip(id=f"c{counter[0]}", shot=shot, take=take, at=at, role=role, **kw)


WIDE = ("wide", None)
BROLL = ("bRoll", None)
DETAIL = ("detail", None)

# 1. Roles read from the source
check("WIDE has 3 required roles and an optional vertical hero",
      [r.id for r in ROLES["wide"]] == ["establishing", "human-scale", "alternative", "vertical-hero"]
      and ROLES["wide"][3].optional, [r.id for r in ROLES["wide"]])
check("B-ROLL has 6 usual kinds and 2 swap-ins",
      sum(not r.substitute for r in ROLES["bRoll"]) == 6 and sum(r.substitute for r in ROLES["bRoll"]) == 2)
check("DETAIL has 5 usual kinds and 1 swap-in",
      sum(not r.substitute for r in ROLES["detail"]) == 5 and sum(r.substitute for r in ROLES["detail"]) == 1)
check("Every role id is unique within its shot", all(len({r.id for r in v}) == len(v) for v in ROLES.values()))

# 2. Distinct plans per WIDE role, and their camera settings (from ShotType.swift)
wide_block = SHOT_SRC.split("        case .wide:\n            switch roleID {", 1)[1].split("\n        case .walkaway:", 1)[0]
plans = re.findall(r'(?:case "([\w-]+)":|default:)(.*?)(?=\n            case "|\n            default:|\Z)', wide_block, re.S)
found = {}
for role, body in plans:
    role = role or "establishing"
    first = body.split("return ShotPlan(", 1)[1]
    if "if inShot" in body:
        first = body.split("if inShot {", 1)[1].split("}\n                return ShotPlan(", 1)[1]
    lens = re.search(r"lens: \.(\w+)", first).group(1)
    fps = re.search(r"fps: (\d+)", first).group(1)
    stab = re.search(r"stabilisation: \.(\w+)", first).group(1)
    stop = re.search(r"autoStop: ([\d.]+)", first).group(1)
    group = re.search(r"group: \.(\w+)", first).group(1)
    steps = tuple(re.findall(r'text: "(.*?)"', first))
    filming = "portrait" if "filming: .portrait" in first else "landscape"
    found[role] = (group, lens, fps, stab, stop, filming, steps)
expected = {
    "establishing": ("inHand", "ultraWide", "30", "cinematic", "20", "landscape"),
    "human-scale": ("inShot", "ultraWide", "30", "off", "30", "landscape"),
    "alternative": ("inHand", "wide", "30", "cinematic", "25", "landscape"),
    "vertical-hero": ("inHand", "ultraWide", "30", "cinematic", "20", "portrait"),
}
for role, want in expected.items():
    check(f"WIDE {role}: group, lens, fps, stabilisation, stop, orientation", found.get(role, ())[:6] == want,
          found.get(role, ())[:6])
check("The three WIDE roles have three different walkthroughs",
      len({found[r][6] for r in ("establishing", "human-scale", "alternative")}) == 3)

# 3. Role-specific timing keys (a port of TimingStore.key): separate per role, falling back to the old key
def timing_keys(shot, in_shot, variant_name=None, role=None):
    base = f"timing.{RAW[shot]}.{'inShot' if in_shot else 'inHand'}"
    if shot in VARIANTS and variant_name:
        base += "." + variant_name
        return [base, base]
    return [base + ".role." + role if role else base, base]

keys = {r: timing_keys("wide", r == "human-scale", role=r)[0] for r in ("establishing", "alternative", "vertical-hero")}
check("Each WIDE role saves its timing under its own key", len(set(keys.values())) == 3, keys)
check("A role with no timing of its own starts from the pre-1.19 WIDE setting",
      timing_keys("wide", False, role="establishing")[1] == "timing.WIDE.inHand")
check("REVEAL keeps its pre-1.19 keys (its roles are its versions)",
      timing_keys("reveal", False, "Tilt up")[0] == "timing.REVEAL.inHand.Tilt up")

# 4. The same role twice doesn't complete another; extras don't add obligations
clips = []
clips.append(clip("WIDE", "establishing", existing=clips))
clips.append(clip("WIDE", "establishing", existing=clips))
cov = coverage(clips, WIDE, 1, "general")
check("Two Establishing takes count once: WIDE 1/3", cov["done"] == 1 and cov["target"] == 3, cov["done"])
check("The repeat is an extra", sorted(cov["statuses"].values()) == ["extra", "provisional"], cov["statuses"])
check("Open roles after it: Me in the view, Another angle", cov["open"] == {"human-scale", "alternative"}, cov["open"])
check("Next role after Establishing is Me in the view", next_role("wide", "establishing", cov["open"]) == "human-scale")
for role in ("human-scale", "alternative"):
    clips.append(clip("WIDE", role, existing=clips, in_shot=role == "human-scale"))
cov = coverage(clips, WIDE, 1, "general")
check("All three roles: WIDE 3/3, complete", cov["complete"] and cov["done"] == 3)
for _ in range(7):
    clips.append(clip("WIDE", "alternative", existing=clips))
cov2 = coverage(clips, WIDE, 1, "general")
check("Ten WIDE takes at an exceptional place: still 3/3, target unchanged, the rest extras",
      cov2["done"] == 3 and cov2["target"] == 3 and list(cov2["statuses"].values()).count("extra") == 8)
clips.append(clip("WIDE", "vertical-hero", existing=clips))
cov3 = coverage(clips, WIDE, 1, "general")
check("The optional vertical hero never changes the target", cov3["target"] == 3 and cov3["done"] == 3)

# 5. Technical checks, overrides and confirmation
clips = [clip("WIDE", "establishing", check_passed=False)]
check("A failed take check doesn't count", coverage(clips, WIDE, 1, "general")["done"] == 0)
clips[0].favourite = True
check("A star alone doesn't override a failed check", coverage(clips, WIDE, 1, "general")["done"] == 0)
clips[0].usable = True
cov = coverage(clips, WIDE, 1, "general")
check("Use anyway counts it, as confirmed", cov["done"] == 1 and list(cov["statuses"].values()) == ["confirmed"])
clips = [clip("WIDE", "establishing", check_passed=True, usable=False)]
check("Not usable stops a passing take counting", coverage(clips, WIDE, 1, "general")["statuses"]["c" + str(counter[0])] == "rejected")
clips = [clip("POV", "approach", check_passed=None, duration=17, planned=17)]
cov = coverage(clips, ("pov", None), 1, "general")
check("A shot with no take check (POV) counts provisionally", cov["done"] == 1 and "provisional" in cov["statuses"].values())
clips[0].favourite = True
check("Starring a passing take confirms it", "confirmed" in coverage(clips, ("pov", None), 1, "general")["statuses"].values())

# 6. Stopped early, interrupted, exited before recording
clips = [clip("WIDE", "establishing", duration=6, planned=22)]
check("Stopped at 6 of 22 s: short, doesn't count", coverage(clips, WIDE, 1, "general")["statuses"][clips[0].id] == "short")
clips = [clip("WIDE", "establishing", duration=14, planned=22)]
check("Stopped at 14 of 22 s (64%): counts", coverage(clips, WIDE, 1, "general")["done"] == 1)
clips = [clip("REACTION", duration=2, planned=None)]
check("A 2-second take you stopped yourself: short", coverage(clips, ("reaction", None), 1, "general")["done"] == 0)
check("Leaving the camera before recording saves nothing, so nothing changes",
      coverage([], WIDE, 1, "general")["done"] == 0)

# 7. Swap-ins: a lookout with no people
clips = []
for role in ("atmosphere", "movement", "local", "lens-angle", "transition", "nature"):
    clips.append(clip("BROLL", role, existing=clips))
cov = coverage(clips, BROLL, 1, "general")
check("No People: Nature swaps in, B-ROLL 6/6", cov["complete"] and cov["done"] == 6)
clips = [clip("BROLL", "atmosphere") for _ in range(6)]
check("Six takes of the same kind count once: B-ROLL 1/6", coverage(clips, BROLL, 1, "general")["done"] == 1)
check("Next suggestion skips to the next usual kind, then swap-ins",
      next_role("bRoll", "people", {"people", "nature"}) == "people"
      and next_role("bRoll", "transition", {"nature", "into-light"}) == "nature")
clips = [clip("DETAIL", r) for r in ("texture", "texture", "texture", "texture")]
check("Four near-identical close-ups: DETAIL 1/4", coverage(clips, DETAIL, 1, "general")["done"] == 1)

# 8. Older clips (before 1.19) and imports
old = [clip("WIDE", None, take=1), clip("WIDE", None, take=2), clip("WIDE", None, take=3, in_shot=True),
       clip("WALKAWAY", None, take=1, in_shot=True), clip("WALKAWAY", None, take=2, in_shot=True),
       clip("REVEAL", None, take=1, variant="Tilt up"), clip("BROLL", None, take=1),
       clip("WIDE", None, take=4, added=True)]
check("Older WIDE takes get roles from how they were filmed",
      [c.role_id for c in old[:3]] == ["establishing", "alternative", "human-scale"])
check("Older WALKAWAY takes: odd into the view, even new spot", [c.role_id for c in old[3:5]] == ["into-view", "new-spot"])
check("Older REVEAL takes: their version", old[5].role_id == "tilt-up")
check("Older B-ROLL and imports have no role", old[6].role_id is None and old[7].role_id is None)
cov = coverage(old, BROLL, 1, "general")
check("An older B-ROLL take still counts, as an unsorted take", cov["done"] == 1)

# 9. Levels build on each other; totals per trip type
expected_totals = {"general": (10, 22, 30), "mountain": (10, 22, 30), "falls": (10, 24, 34), "beach": (10, 22, 31),
                   "city": (10, 24, 33), "road": (10, 26, 34), "snow": (10, 22, 31)}
for trip_type, want in expected_totals.items():
    totals = day_coverage([], 1, trip_type)
    got = tuple(totals[level][1] for level in ("light", "everyday", "full"))
    check(f"{trip_type}: light, everyday and full targets", got == want, got)
clips = []
for shot, role in [("WIDE", "establishing"), ("WIDE", "human-scale"), ("BROLL", "atmosphere"), ("BROLL", "people"),
                   ("BROLL", "movement"), ("DETAIL", "texture"), ("DETAIL", "hands"), ("POV", "approach"),
                   ("REVEAL", None), ("MOMENT", "with-place")]:
    clips.append(clip(shot, role, existing=clips, variant="Auto zoom" if shot == "REVEAL" else None,
                      in_shot=role in ("human-scale", "with-place")))
totals = day_coverage(clips, 1, "general")
check("A light day's ten clips: light 10/10, everyday 10/22, full 10/30",
      totals["light"] == [10, 10] and totals["everyday"] == [10, 22] and totals["full"] == [10, 30], totals)
check("Light counts towards everyday, everyday towards full",
      totals["light"][0] <= totals["everyday"][0] <= totals["full"][0])
light_missing = missing(clips, "light", 1, "general")
every_missing = missing(clips, "everyday", 1, "general")
check("Nothing missing for a light day", light_missing == [])
check("Everyday lists what's still open, role by role",
      dict((s[0], (n, o)) for s, n, o in every_missing).get("wide") == (1, ["alternative"]), every_missing[:3])
clips.append(clip("TALK", None, existing=clips))
totals2 = day_coverage(clips, 1, "general")
check("A full-day shot counts towards full only", totals2["everyday"][0] == 10 and totals2["full"][0] == 11)
clips.append(clip("ORBIT", None, existing=clips))
totals3 = day_coverage(clips, 1, "general")
check("An extra (ORBIT) changes no level and no target", totals3 == totals2)

# 10. Changing the trip type after filming
clips = [clip("DETAIL", r) for r in ("texture", "object", "hands", "foreground")]
general = coverage(clips, DETAIL, 1, "general")
falls = coverage(clips, DETAIL, 1, "falls")
check("Four DETAIL roles: 4/4 on a general day, 4/5 after changing to falls",
      general["complete"] and falls["done"] == 4 and falls["target"] == 5 and not falls["complete"])

# 11. Scenes: suggested, chosen, merged, split
lake = (50.9, -116.0)
clips = []
clips.append(clip("WIDE", "establishing", lat=lake[0], lon=lake[1]))
clips.append(clip("BROLL", "atmosphere", lat=lake[0] + 0.002, lon=lake[1]))         # ~220 m away
town = (lake[0] + 0.05, lake[1])                                                       # ~5.6 km away
scene, confirmed = scene_for_new_clip(clips, 1, town[0], town[1], T0 + timedelta(hours=2))
check("5 km away: a new scene is suggested, not confirmed", scene == 2 and not confirmed)
scene, confirmed = scene_for_new_clip(clips, 1, town[0], town[1], T0 + timedelta(hours=2), choice=False)
check("Keep it in the last scene: scene 1, confirmed", scene == 1 and confirmed)
scene, confirmed = scene_for_new_clip(clips, 1, lake[0], lake[1] + 0.001, T0 + timedelta(hours=3), choice=True)
check("New scene within 500 m (three attractions close together): scene 2, confirmed", scene == 2 and confirmed)
scene, _ = scene_for_new_clip(clips, 1, lake[0], lake[1], T0 + timedelta(hours=2))
check("Two hours at one spot (same place): still scene 1", scene == 1)
scene, _ = scene_for_new_clip(clips, 1, None, None, T0 + timedelta(hours=2))
check("No location and two hours later: a new scene is suggested", scene == 2)
clips.append(clip("WIDE", "alternative", lat=town[0], lon=town[1], at=T0 + timedelta(hours=2)))
clips.append(clip("DETAIL", "object", lat=town[0], lon=town[1], at=T0 + timedelta(hours=2, minutes=5)))
numbers = scene_numbers(clips, 1)
check("Clips group into two scenes by place", [numbers[c.id] for c in clips] == [1, 1, 2, 2], numbers)
merge_scene(clips, 2, 1)
check("Merge: scene 2 joins scene 1, confirmed", {c.scene for c in clips} == {1} and clips[3].scene_confirmed)
split_scene(clips, clips[2].id)
check("Split at a clip: it and later clips start a new scene",
      [c.scene for c in clips] == [1, 1, 2, 2] and clips[2].scene_confirmed and clips[0].scene_confirmed is None)
day_total_before = day_coverage(clips, 1, "general")
merge_scene(clips, 2, 1)
check("Scenes never change the day's counts", day_coverage(clips, 1, "general") == day_total_before)

# 12. The order of the day and other features are unchanged
check("The trip page order is the same as 1.18",
      [s for s, _ in SLOTS] == ["home", "onTheWay", "whip", "pov", "hyperlapse", "follow", "reaction", "reveal", "wide",
                                "slomo", "talk", "walkaway", "tele", "matchCut", "moment", "orbit", "clone", "dance",
                                "silhouette", "bRoll", "detail", "reflection", "wildlife", "food", "sounds", "ambient",
                                "timelapse", "whip", "voiceover", "stay", "home"])

failed = [r for r in results if not r[1]]
for name, ok, detail in results:
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  ({detail})"))
print(f"\n{len(results) - len(failed)} of {len(results)} passed")
sys.exit(1 if failed else 0)
