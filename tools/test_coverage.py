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
    """Each type's ShotTuning table: target, tier, light day, optional roles that count, and the tip (1.26)."""
    tuning = {}
    for name, body in re.findall(r"static let (\w+)Tuning: \[ShotType: ShotTuning\] = \[(.*?)\n    \]", TYPE_SRC, re.S):
        entries = {}
        for shot, args in re.findall(r'\.(\w+): ShotTuning\(((?:[^()"]|"[^"]*")*)\)', body):
            target = re.search(r"target: (\d+)", args)
            tier = re.search(r"tier: \.(\w+)", args)
            light = re.search(r"lightDay: (\d+)", args)
            also = re.search(r"alsoCounts: \[([^\]]*)\]", args)
            summary = re.search(r'summary: "([^"]*)"', args)
            if shot in entries:
                raise SystemExit(f"{name}Tuning has {shot} twice")
            entries[shot] = {"target": int(target.group(1)) if target else None,
                             "tier": tier.group(1) if tier else None,
                             "light": int(light.group(1)) if light else None,
                             "also": re.findall(r'"([\w-]+)"', also.group(1)) if also else [],
                             "summary": summary.group(1) if summary else None}
        tuning[name] = entries
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


def tuned(shot, trip_type, key):
    """One field of TripType.tuning(for:), or None where the type leaves it as the shot's own."""
    entry = TUNING[trip_type].get(shot)
    return entry[key] if entry else None


def target(shot, trip_type):
    value = tuned(shot, trip_type, "target")
    return value if value is not None else TARGET[shot]


def tier(shot, trip_type):
    value = tuned(shot, trip_type, "tier")
    return value if value is not None else TIER[shot]


def roles_for(shot, trip_type):
    """ShotType.roles(for:): the type can count an optional role, like WIDE's vertical hero at falls (1.26)."""
    counted = tuned(shot, trip_type, "also") or []
    return [replace(r, optional=False) if r.id in counted else r for r in ROLES.get(shot, [])]


def slot_target(slot, trip_type):
    shot, half = slot
    return 1 if half is not None else target(shot, trip_type)


def light_target(slot, trip_type):
    """TripType.lightDayTarget(for:): a little of each core shot, with the place's signature shot (1.26)."""
    shot, half = slot
    if half is not None or tier(shot, trip_type) != "core":
        return 0
    light = tuned(shot, trip_type, "light")
    return min(light if light is not None else LIGHT[shot], target(shot, trip_type))


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
    parts: object = None      # ONE TAKE (1.24): a list of dicts, like ClipPart

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
    roles = roles_for(shot, trip_type) if half is None else []
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


def next_role(shot, current, open_ids, trip_type="general"):
    roles = roles_for(shot, trip_type)
    usual = [r for r in roles if not r.optional and not r.substitute]
    ids = [r.id for r in usual]
    start = ids.index(current) + 1 if current in ids else 0
    for r in usual[start:] + usual[:start]:
        if r.id in open_ids:
            return r.id
    return next((r.id for r in roles if r.substitute and r.id in open_ids), None)


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


# ---------------------------------------------------------------- places (1.21)


def scenes(clips, day):
    """Trip.scenes(onDay:): (number, clips) in the order they were filmed."""
    numbers = scene_numbers(clips, day)
    order, grouped = [], {}
    for c in sorted((c for c in clips if c.day == day), key=lambda c: c.at):
        n = numbers[c.id]
        if n not in grouped:
            order.append(n)
            grouped[n] = []
        grouped[n].append(c)
    return [(n, grouped[n]) for n in order]


def place_name(members):
    """ClipScene.placeName: the name most clips share, the first given on a tie."""
    counts, order = {}, []
    for c in members:
        if c.name:
            if c.name not in counts:
                order.append(c.name)
            counts[c.name] = counts.get(c.name, 0) + 1
    best = None
    for n in order:
        if best is None or counts[n] > counts[best]:
            best = n
    return best


def next_starts(clips, day, lat, lon, at, choice=None):
    """Trip.nextClipStartsScene: your choice, else the suggestion."""
    if choice is not None:
        return choice
    day_clips = [c for c in clips if c.day == day]
    if not day_clips:
        return True
    return is_new_scene(max(day_clips, key=lambda c: c.at), lat, lon, at)


def place_now(clips, day, starts_new, chosen_name=None):
    """Trip.placeNow: None for a day at one place, else (scene or None for a new place, name)."""
    day_scenes = scenes(clips, day)
    if not day_scenes:
        return None
    if starts_new:
        return (None, chosen_name)
    if len(day_scenes) < 2:
        return None
    number, members = day_scenes[-1]
    return (number, place_name(members))


def coverage_at(clips, slot, day, place, trip_type="general"):
    """Trip.coverage(for:day:at:): only the place's takes count."""
    here = set()
    for n, members in scenes(clips, day):
        if n == place[0]:
            here = {c.id for c in members}
    return coverage([c for c in clips if c.day != day or c.id in here], slot, day, trip_type)


def name_place(clips, scene, day, name):
    """Trip.namePlace: unnamed clips, and ones with the place's old name, get the new one."""
    fix_scenes(clips, day)
    old = next((place_name(m) for n, m in scenes(clips, day) if n == scene), None)
    changed = []
    for c in clips:
        if c.day == day and c.scene == scene and (c.name is None or c.name == old) and c.name != name:
            c.name = name
            changed.append(c.id)
    return changed


PER_PLACE = set(re.findall(r"\.(\w+)", COVERAGE_SRC.split("var perPlace: Bool {", 1)[1].split("return true", 1)[0]))


def chips_coverage(clips, slot, day, place, trip_type="general"):
    """What the chips under a shot show (TripView.placeChips): the place's, for shots tracked at each place on a day
    at more than one place, otherwise the day's."""
    if slot[0] in PER_PLACE and slot[1] is None and place is not None:
        return coverage_at(clips, slot, day, place, trip_type)
    return coverage(clips, slot, day, trip_type)


def name_for_new_clip(clips, day, scene_number, chosen_name, prefill):
    """TripStore.sceneForNewClip + the camera: a new place's chosen name, else your last name here, else the place's."""
    existing = next((m for n, m in scenes(clips, day) if n == scene_number), None)
    if existing is None:
        return chosen_name
    return prefill or place_name(existing)

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
    "human-scale": ("inShot", "ultraWide", "30", "off", "45", "landscape"),   # longer since 1.24
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
expected_totals = {"general": (10, 22, 30), "mountain": (10, 23, 31), "falls": (10, 26, 33), "beach": (10, 24, 32),
                   "city": (10, 24, 33), "road": (10, 25, 32), "snow": (10, 25, 31)}             # 1.26
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

# 13. Two waterfalls on one hike (1.21)
falls1 = (-28.19, 153.27)
falls2 = (-28.20, 153.27)                                                              # ~1.1 km on
clips = [clip("WIDE", r, lat=falls1[0], lon=falls1[1], at=T0 + timedelta(minutes=i))
         for i, r in enumerate(("establishing", "human-scale", "alternative"))]
check("One place so far: the role buttons follow the whole day",
      place_now(clips, 1, next_starts(clips, 1, falls1[0], falls1[1], T0 + timedelta(minutes=10))) is None)
arrive = T0 + timedelta(hours=1)
starts = next_starts(clips, 1, falls2[0], falls2[1], arrive)
place = place_now(clips, 1, starts)
check("At the second falls: a new place, and its WIDE roles are all still to film there",
      starts and place == (None, None) and coverage_at(clips, WIDE, 1, place)["done"] == 0
      and len(coverage_at(clips, WIDE, 1, place)["open"]) == 3)
check("…while the day's WIDE stays 3 of 3", coverage(clips, WIDE, 1, "general")["complete"])
named = place_now(clips, 1, True, "Twin Falls")
check("New place, named: the buttons say At Twin Falls", named == (None, "Twin Falls"))
scene, _ = scene_for_new_clip(clips, 1, falls2[0], falls2[1], arrive, choice=True)
check("Its first clip gets the name you gave it, not the last falls' name",
      name_for_new_clip(clips, 1, scene, "Twin Falls", "Purling Brook Falls") == "Twin Falls")
clips.append(clip("WIDE", "establishing", lat=falls2[0], lon=falls2[1], at=arrive, name="Twin Falls", scene=scene))
place = place_now(clips, 1, next_starts(clips, 1, falls2[0], falls2[1], arrive + timedelta(minutes=2)))
here = coverage_at(clips, WIDE, 1, place)
check("Back on the trip page: At Twin Falls, Establishing done there, two roles to go",
      place == (scene, "Twin Falls") and here["done"] == 1 and here["open"] == {"human-scale", "alternative"})
check("…and next is Me in the view", next_role("wide", "establishing", here["open"]) == "human-scale")
day_wide = coverage(clips, WIDE, 1, "general")
check("The day's WIDE: still 3 of 3, the second falls' Establishing is an extra",
      day_wide["done"] == 3 and day_wide["statuses"][clips[-1].id] == "extra")
check("A clip 400 m down at the base of the falls takes the place's name",
      name_for_new_clip(clips, 1, scene, None, None) == "Twin Falls")
check("…but your last clip's own name wins when you're still beside it",
      name_for_new_clip(clips, 1, scene, None, "The pool") == "The pool")

# 13b. Which shots are tracked at each place (1.22)
check("Tracked at each place: REACTION, REVEAL, WIDE, TELE, WALKAWAY, MOMENT, SLOMO, MATCH CUT and AMBIENT",
      PER_PLACE == {"reaction", "reveal", "wide", "tele", "walkaway", "moment", "slomo", "matchCut", "ambient"},
      sorted(PER_PLACE))
REACTION = ("reaction", None)
clips = [clip("REACTION", lat=falls1[0], lon=falls1[1], at=T0),
         clip("BROLL", "atmosphere", lat=falls1[0], lon=falls1[1], at=T0 + timedelta(minutes=1)),
         clip("BROLL", "people", lat=falls1[0], lon=falls1[1], at=T0 + timedelta(minutes=2))]
place = place_now(clips, 1, next_starts(clips, 1, falls2[0], falls2[1], T0 + timedelta(hours=1)), "Twin Falls")
check("At the second falls, REACTION is to film here, though the day already has one",
      chips_coverage(clips, REACTION, 1, place)["done"] == 0 and coverage(clips, REACTION, 1, "general")["complete"])
check("…while B-ROLL keeps counting for the whole day (2 of 6, Atmosphere and People done)",
      chips_coverage(clips, BROLL, 1, place)["done"] == 2
      and chips_coverage(clips, BROLL, 1, place)["lines"] == coverage(clips, BROLL, 1, "general")["lines"])
check("DETAIL and POV are gathered for the whole day too", "detail" not in PER_PLACE and "pov" not in PER_PLACE)
scene, _ = scene_for_new_clip(clips, 1, falls2[0], falls2[1], T0 + timedelta(hours=1), choice=True)
clips.append(clip("REACTION", lat=falls2[0], lon=falls2[1], at=T0 + timedelta(hours=1), name="Twin Falls", scene=scene))
place = place_now(clips, 1, next_starts(clips, 1, falls2[0], falls2[1], T0 + timedelta(hours=1, minutes=1)))
check("After filming it there: REACTION is filmed here, and an extra for the day",
      chips_coverage(clips, REACTION, 1, place)["done"] == 1
      and coverage(clips, REACTION, 1, "general")["statuses"][clips[-1].id] == "extra")

# 14. Naming a place afterwards (1.21)
clips = [clip("WIDE", "establishing", lat=falls1[0], lon=falls1[1]),
         clip("BROLL", "atmosphere", lat=falls1[0], lon=falls1[1]),
         clip("DETAIL", "texture", lat=falls1[0], lon=falls1[1])]
changed = name_place(clips, 1, 1, "Purling Brook Falls")
check("Naming a place names all its clips", {c.name for c in clips} == {"Purling Brook Falls"} and len(changed) == 3)
clips.append(clip("DETAIL", "hands", lat=falls1[0], lon=falls1[1], name="Lookout"))
clips.append(clip("BROLL", "people", lat=falls1[0], lon=falls1[1]))
check("Its name is the one most clips share", place_name(clips) == "Purling Brook Falls")
changed = name_place(clips, 1, 1, "Purling Brook")
check("Renaming it changes the clips with its old name, and unnamed ones, and keeps one you named yourself",
      [c.name for c in clips] == ["Purling Brook"] * 3 + ["Lookout", "Purling Brook"] and len(changed) == 4)
only = [clip("WIDE", "establishing", lat=falls2[0], lon=falls2[1], name="Lookout"),
        clip("BROLL", "atmosphere", lat=falls2[0], lon=falls2[1])]
name_place(only, 1, 1, "Twin Falls")
check("A place named after its only named clip: renaming the place renames that clip too",
      [c.name for c in only] == ["Twin Falls", "Twin Falls"])
check("Names never change the day's counts",
      day_coverage(clips, 1, "general") == day_coverage([replace(c, name=None) for c in clips], 1, "general"))

# ---------------------------------------------------------------- ONE TAKE and Skip (1.24), ported from OneTake.swift
ONE_SRC = (MODELS / "OneTake.swift").read_text(encoding="utf-8")


def one_take_table(header):
    body = ONE_SRC.split(header, 1)[1].split("\n    }\n", 1)[0]
    table = {}
    for cases, value in re.findall(r"case ([.\w, ]+?):\s*return (.+)", body):
        for case in re.findall(r"\.(\w+)", cases):
            table[case] = value.strip()
    return table


PART_ORDER = re.findall(r"case (\w+)\n", ONE_SRC.split("enum OneTakePart", 1)[1].split("var id", 1)[0])
PART_SHOT = {k: v.lstrip(".") for k, v in one_take_table("var shot: ShotType {").items()}
PART_ROLES = {k: re.findall(r'"([\w-]+)"', v) for k, v in one_take_table("var roleOrder: [String] {").items()}
PART_LENGTH = {k: float(v) for k, v in one_take_table("var defaultLength: Double {").items()}
ONE_TAKE_SHOTS = re.findall(r"\.(\w+)", ONE_SRC.split("static let shots: [ShotType] = [", 1)[1].split("]", 1)[0])


def part_take(c, part):
    """Clip.partTake: a part as a take of its shot, with the clip's place, time, light and check."""
    own = part.get("usable")
    return replace(c, id=part["id"], shot=part["shot"], take=part["take"], role=part.get("role"),
                   variant=part.get("variant"), in_shot=part["in_shot"], at=c.at + timedelta(seconds=part["start"]),
                   duration=max(0, part["end"] - part["start"]), planned=None,
                   usable=own if own is not None else c.usable, favourite=False, parts=None)


def all_takes(clips):
    """Trip.allTakes: each ONE TAKE as itself and its parts."""
    out = []
    for c in clips:
        out.append(c)
        if c.shot == "ONETAKE":
            out.extend(part_take(c, p) for p in (c.parts or []))
    return out


def one_take_plan(clips, parts, day, trip_type="general"):
    """Trip.oneTakePlan on a day at one place: what each part counts as."""
    taken, result = set(), []
    for part in parts:
        shot = PART_SHOT[part]
        cov = coverage(all_takes(clips), (shot, None), day, trip_type)
        order = PART_ROLES[part]
        if not order:
            result.append((part, None, not cov["complete"] and shot not in taken))
            taken.add(shot)
            continue
        covered = {rid for rid, n in cov["lines"].items() if n > 0}
        free = [r for r in order if shot + "." + r not in taken]
        role = next((r for r in free if r not in covered), free[0] if free else order[0])
        taken.add(shot + "." + role)
        result.append((part, role, role in cov["open"]))
    return result


def filmed_ranges(starts, walk_back_at, duration):
    out = []
    for i, start in enumerate(starts):
        nxt = starts[i + 1] if i + 1 < len(starts) else (walk_back_at if walk_back_at is not None else duration)
        out.append((start, max(start, min(nxt, duration))))
    return out


def next_take(clips, shot_raw, day):
    return max([c.take for c in all_takes(clips) if c.shot == shot_raw and c.day == day] or [0]) + 1


one_take_ids = [0]


def film_one_take(clips, parts, starts, duration, walk_back_at=None, move="Run across", day=1, at=None, **kw):
    """Films a ONE TAKE the way ShotCameraView.saveTake and OneTakeRun.clipParts do, and adds it to `clips`."""
    reached = parts[:len(starts)]
    fills = {p: role for p, role, _ in one_take_plan(clips, reached, day)}
    ranges = filmed_ranges(starts, walk_back_at, duration)
    takes, made = {}, []
    for part, (start, end) in zip(reached, ranges):
        if end - start < 0.5:
            continue
        shot = RAW[PART_SHOT[part]]
        take = takes.get(shot) or next_take(clips, shot, day)
        takes[shot] = take + 1
        one_take_ids[0] += 1
        made.append({"id": f"p{one_take_ids[0]}", "part": part, "shot": shot, "take": take, "role": fills[part],
                     "variant": move if part == "matchCut" else None, "in_shot": part != "emptyFrame",
                     "start": start, "end": end})
    one_take_ids[0] += 1
    c = Clip(id=f"ot{one_take_ids[0]}", shot="ONETAKE", take=next_take(clips, "ONETAKE", day),
             at=at or datetime(2026, 11, 14, 10, 0), day=day, in_shot=True, duration=duration, parts=made, **kw)
    clips.append(c)
    return c


def default_starts(parts):
    starts, clock = [], 0.0
    for p in parts:
        starts.append(clock)
        clock += PART_LENGTH[p]
    return starts, clock


def one_take_can_fill(row):
    """OneTakePart.canFill (1.25.1): one of ONE TAKE's shots and, for those with roles, a role one of its parts fills.
    MOMENT with only Together left doesn't count: that's filmed on its own, upright."""
    shot, open_roles = row[0][0], row[2]
    if shot not in ONE_TAKE_SHOTS:
        return False
    fillable = {r for part, s in PART_SHOT.items() if s == shot for r in PART_ROLES[part]}
    return not open_roles or any(r in fillable for r in open_roles)


def suggestions(clips, day, trip_type="general"):
    """Trip.nextSuggestions: the rows still needed, lowest level first, with ONE TAKE before the first of its shots
    when two or more of them that it can fill are needed at that level. One entry per skip key."""
    takes = all_takes(clips)
    out, seen = [], set()

    def add(shot, half, role):
        key = RAW[shot] + ("" if half is None else f"-{half}")
        if key not in seen:
            seen.add(key)
            out.append((shot, half, role, key))

    for level in ("light", "everyday", "full"):
        rows = missing(takes, level, day, trip_type)
        one_rows = [r for r in rows if one_take_can_fill(r)]
        for row in rows:
            slot = row[0]
            if len(one_rows) >= 2 and row is one_rows[0]:
                add("oneTake", None, None)
            cov = coverage(takes, slot, day, trip_type)
            add(slot[0], slot[1], next_role(slot[0], None, cov["open"], trip_type))
    return out


def next_suggestion(clips, day, skipped=(), trip_type="general"):
    every = suggestions(clips, day, trip_type)
    return next((s for s in every if s[3] not in skipped), every[0] if every else None)


def skip(clips, day, skipped, key):
    """TripStore.skipNext: once everything's skipped, start again from the top."""
    skipped = list(skipped) + ([key] if key not in skipped else [])
    left = [s for s in suggestions(clips, day) if s[3] not in skipped]
    return skipped if left else []


PARTS = PART_ORDER
starts, total = default_starts(PARTS)
check("ONE TAKE's parts, in order: empty frame, walk in, in the view, moment, MATCH CUT, clones",
      PARTS == ["emptyFrame", "walkIn", "inView", "moment", "matchCut", "clones"], PARTS)
check("By default it runs 6:00 before you walk back (30, 30, 60, 60, 30 and 150 seconds)", total == 360, total)

clips = []
first = film_one_take(clips, PARTS, starts, duration=400, walk_back_at=total)
takes = all_takes(clips)
check("A ONE TAKE counts as itself and its six parts", len(takes) == 7, len(takes))
check("Its parts fill Establishing, Into the view, Me in the view, With the place, MATCH CUT and CLONE",
      [(p["shot"], p["role"]) for p in first.parts] == [("WIDE", "establishing"), ("WALKAWAY", "into-view"),
                                                       ("WIDE", "human-scale"), ("MOMENT", "with-place"),
                                                       ("MATCHCUT", None), ("CLONE", None)],
      [(p["shot"], p["role"]) for p in first.parts])
wide = coverage(takes, ("wide", None), 1, "general")
check("WIDE 2/3 from one take: two parts, two roles", wide["done"] == 2 and wide["open"] == {"alternative"}, wide["done"])
check("WALKAWAY 1/2, MOMENT 1/2, MATCH CUT 1/1, CLONE 1/1",
      [coverage(takes, (s, None), 1, "general")["done"] for s in ("walkaway", "moment", "matchCut", "clone")]
      == [1, 1, 1, 1])
check("Its parts are takes 1 and 2 of WIDE, and take 1 of the rest", [p["take"] for p in first.parts] == [1, 1, 2, 1, 1, 1])
check("The clones part ends where you set off back, not where you stopped it",
      first.parts[-1]["start"] == 210 and first.parts[-1]["end"] == 360)
check("The MATCH CUT part carries the move", first.parts[4]["variant"] == "Run across")
light = day_coverage(takes, 1, "general")["light"]
check("One ONE TAKE fills 3 of a light day's 10 (WIDE twice, MOMENT)", light[0] == 3, light)

second = film_one_take(clips, PARTS, starts, duration=380, walk_back_at=total)
plan2 = [(p["shot"], p["role"]) for p in second.parts]
check("A second ONE TAKE fills the second roles: Another angle, New spot or action; its moment is With the place again",
      plan2[:4] == [("WIDE", "alternative"), ("WALKAWAY", "new-spot"), ("WIDE", "human-scale"), ("MOMENT", "with-place")],
      plan2)
takes = all_takes(clips)
moment = coverage(takes, ("moment", None), 1, "general")
check("…so WIDE is 3/3 and WALKAWAY 2/2, the repeats are extras, and MOMENT stays 1/2 with Together to film upright",
      [coverage(takes, (s, None), 1, "general")["done"] for s in ("wide", "walkaway", "moment")] == [3, 2, 1]
      and coverage(takes, ("wide", None), 1, "general")["statuses"][second.parts[2]["id"]] == "extra"
      and moment["statuses"][second.parts[3]["id"]] == "extra" and moment["open"] == {"together"},
      moment)

clips = []
skipped_parts = film_one_take(clips, PARTS, starts, duration=400, walk_back_at=total)
skipped_parts.parts[4]["usable"] = False
check("A part you mark not usable (you skipped the move) doesn't count, and MATCH CUT stays to film",
      coverage(all_takes(clips), ("matchCut", None), 1, "general")["done"] == 0)
clips = [replace(skipped_parts, usable=False)]
check("Marking the whole take not usable stops every part counting…",
      sum(coverage(all_takes(clips), (s, None), 1, "general")["done"] for s in ("wide", "walkaway", "moment")) == 0)
clips[0].parts[1]["usable"] = True
check("…except a part you mark usable yourself",
      coverage(all_takes(clips), ("walkaway", None), 1, "general")["done"] == 1)

clips = []
quick = [0.0, 30.0, 31.0]
early = film_one_take(clips, PARTS, quick, duration=50)
check("Moving on after a second leaves a short part that doesn't count",
      coverage(all_takes(clips), ("walkaway", None), 1, "general")["statuses"].get(early.parts[1]["id"]) == "short")
check("Stopped during In the view: it ends at the end of the clip, and the parts after it aren't there",
      len(early.parts) == 3 and early.parts[2]["end"] == 50)
clips = []
tiny = film_one_take(clips, PARTS, [0.0, 20.0], duration=20.3)
check("A part under half a second (stopped as it began) is left out", len(tiny.parts) == 1)

clips = []
out = ["emptyFrame", "walkIn", "inView", "moment"]
left = film_one_take(clips, out, default_starts(out)[0], duration=200, walk_back_at=180)
check("Leave MATCH CUT and CLONE out and they're still to film, for along the trail",
      [coverage(all_takes(clips), (s, None), 1, "general")["done"] for s in ("matchCut", "clone")] == [0, 0]
      and len(left.parts) == 4)

# Next and Skip
clips = []
order = [s[0] for s in suggestions(clips, 1)][:5]
check("A new day's Next: POV, REVEAL, then ONE TAKE just before WIDE, as WIDE and MOMENT are both needed",
      order == ["pov", "reveal", "oneTake", "wide", "moment"], order)
skipped = skip(clips, 1, [], "POV")
check("Skip POV: REVEAL comes forward", next_suggestion(clips, 1, skipped)[0] == "reveal")
skipped = skip(clips, 1, skipped, "REVEAL")
check("Skip REVEAL too: ONE TAKE", next_suggestion(clips, 1, skipped)[0] == "oneTake")
check("After your next take, the skipped ones are back first (POV)", next_suggestion(clips, 1, [])[0] == "pov")
everything = []
for s in suggestions(clips, 1):
    everything = skip(clips, 1, everything, s[3])
check("Skip everything and it starts again from the top", everything == [] and next_suggestion(clips, 1, everything)[0] == "pov")
check("Skip leaves out the whole shot, whatever role it was on (WIDE is one key)",
      len([s for s in suggestions(clips, 1) if s[0] == "wide"]) == 1)
clips = []
film_one_take(clips, PARTS, starts, duration=400, walk_back_at=total)
check("Once ONE TAKE has filled them, Next moves on from WIDE and MOMENT's first roles",
      ("wide", None, "alternative", "WIDE") in suggestions(clips, 1)
      and not any(s[0] == "moment" and s[2] == "with-place" for s in suggestions(clips, 1)))

# 12. The order of the day and other features are unchanged
check("The trip page order is 1.18's, with ONE TAKE at the top of At the spot (1.24)",
      [s for s, _ in SLOTS] == ["home", "onTheWay", "whip", "pov", "hyperlapse", "follow", "reaction", "reveal", "oneTake", "wide",
                                "slomo", "talk", "walkaway", "tele", "matchCut", "moment", "orbit", "clone", "dance",
                                "silhouette", "bRoll", "detail", "reflection", "wildlife", "food", "sounds", "ambient",
                                "timelapse", "whip", "voiceover", "stay", "home"])

# 13. Which way each shot is filmed (1.25.1): every reel plays upright, so the big views stay landscape and the rest
# are filmed upright, with REVEAL and B-ROLL set for each version or role
FILMING = switch_values(SHOT_SRC, "    var filming: Filming {", "portrait")
BIG_VIEWS = {"wide", "tele", "walkaway", "silhouette", "timelapse", "reflection", "matchCut", "onTheWay", "wildlife",
             "oneTake"}
check("The big views stay landscape: WIDE, TELE, WALKAWAY, SILHOUETTE, TIMELAPSE, REFLECTION, MATCH CUT, ON THE WAY, "
      "WILDLIFE and ONE TAKE", {s for s, f in FILMING.items() if f == "landscape"} == BIG_VIEWS,
      sorted(s for s, f in FILMING.items() if f == "landscape"))
check("MOMENT and HOME are upright now, and so is every shot that went either way",
      all(FILMING[s] == "portrait" for s in ("moment", "home", "detail", "sounds", "slomo", "dance", "orbit", "stay",
                                              "hyperlapse", "ambient", "clone")))
check("Only REVEAL and B-ROLL go both ways, as their versions and roles differ",
      {s for s, f in FILMING.items() if f == "either"} == {"reveal", "bRoll"})


def plan_filming(block, label):
    """The orientation a plan in ShotType.swift sets, or None when it leaves it to the shot."""
    found = re.search(r"filming: \.(\w+)", block)
    return found.group(1) if found else None


broll_block = SHOT_SRC.split("        case .bRoll:\n            switch roleID {", 1)[1].split("\n        case .stay:", 1)[0]
broll = {}
for role, body in re.findall(r'(?:case "([\w-]+)":|default:)(.*?)(?=\n            case "|\n            default:|\Z)',
                             broll_block, re.S):
    broll[role or ROLES["bRoll"][0].id] = plan_filming(body, role)
check("B-ROLL's plans cover every role, the first (Atmosphere) by default",
      set(broll) == {r.id for r in ROLES["bRoll"]} and ROLES["bRoll"][0].id == "atmosphere", sorted(broll))
check("B-ROLL: Atmosphere, Movement and New lens or angle landscape; People, Local character, Transition, Nature and "
      "Into the light upright",
      broll == {"atmosphere": "landscape", "movement": "landscape", "lens-angle": "landscape", "people": "portrait",
                "local": "portrait", "transition": "portrait", "nature": "portrait", "into-light": "portrait"}, broll)

reveal_block = SHOT_SRC.split("        case .reveal:\n            if variantIndex == 0 {", 1)[1].split("\n        case .timelapse:", 1)[0]
reveal_plans = reveal_block.split("return ShotPlan(")[1:]
reveal = dict(zip(["Auto zoom", "Tilt up", "Walk reveal"], [plan_filming(b, None) for b in reveal_plans]))
check("REVEAL: Auto zoom landscape (the zoom across the lenses); Walk reveal and Tilt up upright",
      len(reveal_plans) == 3 and "zoomRamp" in reveal_plans[0] and "tilt slowly up" in reveal_plans[1]
      and reveal == {"Auto zoom": "landscape", "Tilt up": "portrait", "Walk reveal": "portrait"}, reveal)
snap = SHOT_SRC.split("case .snap:\n            return make(", 1)[1].split("case .", 1)[0]
check("Still upright on their own: WIDE's vertical hero and MATCH CUT's Snap",
      found["vertical-hero"][5] == "portrait" and plan_filming(snap, None) == "portrait")
check("ONE TAKE's moment counts only as MOMENT · With the place, so Together is filmed on its own, upright",
      PART_ROLES["moment"] == ["with-place"] and PART_SHOT["moment"] == "moment")
check("ONE TAKE can't fill MOMENT · Together, so a row needing only that doesn't count towards suggesting one",
      not one_take_can_fill((("moment", None), 1, ["together"]))
      and one_take_can_fill((("moment", None), 2, ["together", "with-place"]))
      and one_take_can_fill((("clone", None), 1, [])) and not one_take_can_fill((("tele", None), 1, [])))

clips = []
film_one_take(clips, PARTS, starts, duration=400, walk_back_at=total)
check("After a ONE TAKE, Next suggests another while it can fill two shots (WIDE · Another angle, WALKAWAY · New spot)",
      ("oneTake", None, None) in [s[:3] for s in suggestions(clips, 1)])
clips.append(clip("WALKAWAY", "new-spot", existing=clips, in_shot=True))
check("…but not once only WIDE · Another angle and MOMENT · Together are left: it could only fill one of them",
      "oneTake" not in [s[0] for s in suggestions(clips, 1)]
      and ("moment", None, "together", "MOMENT") in suggestions(clips, 1))

# 14. Each type of place gets the shots its reels need (1.26)
TYPES = ["general", "mountain", "falls", "beach", "city", "road", "snow"]
missing_tips = [(t, shot) for t in TYPES for shot in RAW if not (tuned(shot, t, "summary") or "").strip()]
check("Every type of place has a tip for every shot, General included: no missing tips",
      set(TUNING) == set(TYPES) and missing_tips == [] and all(len(TUNING[t]) == len(RAW) for t in TYPES),
      missing_tips[:6])
tips = [(t, tuned(shot, t, "summary")) for t in TYPES for shot in RAW]
check("Tips read as one line before the set-up: no full stop at the end, and none repeated within a type",
      all(not tip.endswith(".") for _, tip in tips)
      and all(len({tuned(shot, t, "summary") for shot in RAW}) == len(RAW) for t in TYPES),
      [tip for _, tip in tips if tip.endswith(".")][:3])


def light_day(trip_type):
    return {slot[0]: light_target(slot, trip_type) for slot in SLOTS if light_target(slot, trip_type) > 0}


check("General's light day is unchanged: WIDE 2, B-ROLL 3, DETAIL 2, POV, REVEAL and MOMENT 1",
      light_day("general") == {"wide": 2, "bRoll": 3, "detail": 2, "pov": 1, "reveal": 1, "moment": 1},
      light_day("general"))
signature = {"mountain": ("tele", "bRoll"), "falls": ("slomo", "bRoll"), "beach": ("slomo", "bRoll"),
             "city": ("food", "wide"), "road": ("onTheWay", "bRoll"), "snow": ("slomo", "bRoll")}
for trip_type, (shot, makes_room) in signature.items():
    days = light_day(trip_type)
    base = light_day("general")
    check(f"{trip_type}: a light day is 10 clips with its signature shot ({shot}) in place of a {makes_room}",
          sum(days.values()) == 10 and days.get(shot) == 1 and days[makes_room] == base[makes_room] - 1, days)

changes = {
    "mountain": {"tele": ("core", 1), "wildlife": ("fullDay", 2), "slomo": ("extra", None)},
    "falls": {"slomo": ("core", 2), "wide": ("core", 4), "wildlife": ("fullDay", 1), "walkaway": ("core", 1),
              "silhouette": ("extra", None), "detail": ("core", 5), "ambient": ("core", 2)},
    "beach": {"slomo": ("core", 2), "reflection": ("fullDay", 1)},
    "city": {"bRoll": ("core", 7), "detail": ("core", 5), "food": ("core", 2), "follow": ("fullDay", 1),
             "hyperlapse": ("fullDay", 1), "reveal": ("core", 1), "walkaway": ("core", 1), "silhouette": ("extra", None)},
    "road": {"onTheWay": ("core", 4), "matchCut": ("core", 1), "timelapse": ("fullDay", 1), "reveal": ("core", 1),
             "walkaway": ("core", 1), "slomo": ("extra", None)},
    "snow": {"slomo": ("core", 2), "tele": ("core", 1)},
}
for trip_type, shots in changes.items():
    got = {shot: (tier(shot, trip_type), target(shot, trip_type) if want[1] is not None else None)
           for shot, want in shots.items()}
    check(f"{trip_type}: " + ", ".join(f"{shot} {w[0]}" + (f" {w[1]}" if w[1] else "") for shot, w in shots.items()),
          got == shots, got)
changed = {(t, shot) for t in TYPES for shot in RAW
           if (tier(shot, t), target(shot, t)) != (tier(shot, "general"), target(shot, "general"))}
check("Nothing else changes from General's counts (TIMELAPSE's 2 in a city stays an extra)",
      changed == {(t, shot) for t, shots in changes.items() for shot in shots} | {("city", "timelapse")},
      sorted(changed - {(t, shot) for t, shots in changes.items() for shot in shots}))

three = [clip("WIDE", r, in_shot=r == "human-scale") for r in ("establishing", "human-scale", "alternative")]
general_wide = coverage(three, WIDE, 1, "general")
falls_wide = coverage(three, WIDE, 1, "falls")
check("At falls WIDE counts its vertical hero: the usual three are 3/3 on a general day, 3/4 at falls",
      general_wide["complete"] and falls_wide["done"] == 3 and falls_wide["target"] == 4
      and falls_wide["open"] == {"vertical-hero"}, falls_wide)
check("…and the camera and Next go to it after Another angle (on a general day it stays optional)",
      next_role("wide", "alternative", falls_wide["open"], "falls") == "vertical-hero"
      and next_role("wide", "alternative", {"vertical-hero"}, "general") is None
      and ("wide", None, "vertical-hero", "WIDE") in suggestions(three, 1, "falls"))
hero = three + [clip("WIDE", "vertical-hero", existing=three)]
check("Filmed, it fills WIDE at falls (4/4); on a general day it's an extra",
      coverage(hero, WIDE, 1, "falls")["complete"]
      and coverage(hero, WIDE, 1, "general")["statuses"][hero[-1].id] == "extra")
check("ONE TAKE still can't fill the vertical hero, as it's upright",
      not one_take_can_fill((("wide", None), 1, ["vertical-hero"])))

kinds = [clip("BROLL", r) for r in ("atmosphere", "people", "movement", "local", "lens-angle", "transition")]
city_broll = coverage(kinds, BROLL, 1, "city")
check("City B-ROLL: the six kinds are 6/7, and a swap-in (the sun between the towers) makes 7",
      city_broll["done"] == 6 and city_broll["target"] == 7
      and next_role("bRoll", None, city_broll["open"], "city") == "nature"
      and coverage(kinds + [clip("BROLL", "into-light")], BROLL, 1, "city")["complete"])
check("General B-ROLL is still six kinds: a swap-in on top is an extra",
      coverage(kinds + [clip("BROLL", "into-light")], BROLL, 1, "general")["done"] == 6)

failed = [r for r in results if not r[1]]
for name, ok, detail in results:
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  ({detail})"))
print(f"\n{len(results) - len(failed)} of {len(results)} passed")
sys.exit(1 if failed else 0)
