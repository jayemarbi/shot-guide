"""A Python model of Shot Guide's coverage (1.19, reworked in 1.28), with tests.

There's no Swift compiler here, so this ports the rules in Models/Coverage.swift and Models/TripPhase.swift and checks
them against scenarios. The tables (roles, targets, tiers, light-day takes, trip-type tuning, the lists of each part
of the day, the cards before each shot) are read from the Swift source, so the model can't drift from them. The logic
is a port: keep it in step with the Swift. It checks the rules, not the Swift code itself; the app's build and a phone
test do that.

usage: python3 tools/test_coverage.py [repo folder]
"""
import re
import sys
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from math import asin, cos, radians, sin, sqrt
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
MODELS = ROOT / "ShotGuide" / "Models"
SHOT_SRC = (MODELS / "ShotType.swift").read_text(encoding="utf-8")
COVERAGE_SRC = (MODELS / "Coverage.swift").read_text(encoding="utf-8")
TYPE_SRC = (MODELS / "TripType.swift").read_text(encoding="utf-8")
PHASE_SRC = (MODELS / "TripPhase.swift").read_text(encoding="utf-8")
CARDS_SRC = (MODELS / "ShotCards.swift").read_text(encoding="utf-8")
ONE_SRC = (MODELS / "OneTake.swift").read_text(encoding="utf-8")

# ---------------------------------------------------------------- tables, read from the Swift source

RAW = dict(re.findall(r'case (\w+) = "(\w+)"', SHOT_SRC.split("enum ShotType")[1].split("}")[0]))
CASE = {v: k for k, v in RAW.items()}


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
CREATIVE = {k for k, v in switch_values(SHOT_SRC, "var isCreative: Bool {", "false").items() if v == "true"}
AT_HOME = {k for k, v in switch_values(SHOT_SRC, "var isAtHome: Bool {", "false").items() if v == "true"}
VARIANTS = {"reveal": ["Auto zoom", "Walk reveal", "Tilt up"], "whip": ["Out", "In"], "home": ["Before", "After"],
            "talk": ["At home", "One line"]}


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
TYPES = ["general", "mountain", "falls", "beach", "city", "road", "snow"]

# ---------------------------------------------------------------- the lists (TripPhase.swift, 1.28)


@dataclass(frozen=True)
class Row:
    shot: str            # case name, like "wide"
    half: object = None
    role: object = None
    variant: object = None

    @property
    def key(self):
        base = RAW[self.shot] + ("" if self.half is None else f"-{self.half}")
        return base + ("" if self.role is None else "." + self.role)

    @property
    def id(self):
        return self.key + ("" if self.variant is None else f"~{self.variant}")

    @property
    def slot(self):
        return (self.shot, self.half)

    @property
    def role_info(self):
        return next((r for r in ROLES.get(self.shot, []) if r.id == self.role), None)


ROW_CALL = re.compile(r'ShotRow\(shot: \.(\w+)(?:, half: (\d+))?(?:, role: "([\w-]+)")?(?:, variant: (\d+))?\)')


def rows_in(chunk):
    rows = []
    mapped = re.search(r'\[([^\]]*)\]\.map \{ ShotRow\(shot: \.(\w+), role: \$0\) \}', chunk)
    if mapped:
        return [Row(mapped.group(2), role=r) for r in re.findall(r'"([\w-]+)"', mapped.group(1))]
    every = re.search(r'ShotType\.(\w+)\.roles\.map \{ ShotRow\(shot: \.(\w+), role: \$0\.id\) \}', chunk)
    if every:
        return [Row(every.group(2), role=r.id) for r in ROLES[every.group(1)]]
    for shot, half, role, variant in ROW_CALL.findall(chunk):
        rows.append(Row(shot, int(half) if half else None, role or None, int(variant) if variant else None))
    return rows


def read_cases(header):
    body = PHASE_SRC.split(header, 1)[1].split("\n    }\n", 1)[0]
    return {case: chunk for case, chunk in re.findall(r"case \.(\w+):(.*?)(?=\n        case \.|\n        default:|\Z)",
                                                      body, re.S)}


def read_broll_groups():
    body = PHASE_SRC.split("private var bRollGroups: [RowGroup] {", 1)[1].split("\n    }\n", 1)[0]
    groups = []
    for call in body.split("RowGroup(")[1:]:
        ident = re.search(r'id: "(\w+)"', call).group(1)
        groups.append((ident, rows_in(call)))
    return groups


BROLL_GROUPS = read_broll_groups()
PART_ROWS = {}
for case, chunk in read_cases("var rows: [ShotRow] {").items():
    PART_ROWS[case] = [r for _, rows in BROLL_GROUPS for r in rows] if "bRollGroups" in chunk else rows_in(chunk)
PART_CREATIVE = {case: rows_in(chunk) for case, chunk in read_cases("var creative: [ShotRow] {").items()}
PARTS = re.findall(r"case (\w+)\n", PHASE_SRC.split("enum TripPhase", 1)[1].split("var id", 1)[0])
DAY_PARTS = re.findall(r"\.(\w+)", PHASE_SRC.split("static let dayParts: [TripPhase] = [", 1)[1].split("]", 1)[0])


def all_rows(part):
    return PART_ROWS.get(part, []) + PART_CREATIVE.get(part, [])


def part_slots(part):
    out = []
    for row in all_rows(part):
        if row.slot not in out:
            out.append(row.slot)
    return out


ALL_SLOTS = []
for _part in PARTS:
    for _slot in part_slots(_part):
        if _slot not in ALL_SLOTS:
            ALL_SLOTS.append(_slot)
ALL_ROWS = [row for part in PARTS for row in all_rows(part)]

# ---------------------------------------------------------------- the cards (ShotCards.swift, 1.28)

STRING = r'"((?:[^"\\]|\\.)*)"'


def read_cards():
    cards = {}
    for chunk in CARDS_SRC.split('cards["')[1:]:
        ident = chunk.split('"', 1)[0]
        body = chunk.split("= ShotCard(", 1)[1].split("\n\n", 1)[0]
        what = re.search(r"what: " + STRING, body).group(1)
        where = re.search(r"whereItGoes: " + STRING, body).group(1)
        how = re.findall(STRING, body.split("how: [", 1)[1].split("],", 1)[0])
        ideas = re.findall(r"Idea\(" + STRING + r", " + STRING + r"\)", body)
        if ident in cards:
            raise SystemExit(f"two cards for {ident}")
        cards[ident] = {"what": what, "where": where, "how": how, "ideas": ideas}
    return cards


CARDS = read_cards()
LINES = dict(re.findall(STRING + r": " + STRING,
                        CARDS_SRC.split("static let lines: [String: String] = [", 1)[1].split("\n    ]", 1)[0]))


def card_for(row):
    """ShotRow.card: its own, or its shot's."""
    return CARDS.get(row.id) or CARDS.get(row.key) or CARDS.get(RAW[row.shot])

# ---------------------------------------------------------------- the rules (Coverage.swift)


def tuned(shot, trip_type, key):
    entry = TUNING[trip_type].get(shot)
    return entry[key] if entry else None


def target(shot, trip_type):
    value = tuned(shot, trip_type, "target")
    return value if value is not None else TARGET[shot]


def tier(shot, trip_type):
    """TripType.tier(for:): the creative shots and the ones filmed at home never count (1.28)."""
    if shot in CREATIVE or shot in AT_HOME:
        return "extra"
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
    shot, half = slot
    if half is not None or tier(shot, trip_type) != "core":
        return 0
    light = tuned(shot, trip_type, "light")
    return min(light if light is not None else LIGHT[shot], target(shot, trip_type))


def goal(slot, level, trip_type, want):
    t = tier(slot[0], trip_type)
    if t == "core":
        return min(light_target(slot, trip_type), want) if level == "light" else want
    if t == "fullDay":
        return want if level == "full" else 0
    return 0


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
    usable: object = None     # only set on takes from before 1.28
    favourite: bool = False
    added: bool = False
    lat: object = None
    lon: object = None
    name: object = None
    parts: object = None      # ONE TAKE (1.24): a list of dicts, like ClipPart

    @property
    def case(self):
        return CASE.get(self.shot)

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
        if case == "slomo":
            return "you" if self.in_shot else "water"
        return None

    @property
    def counts(self):
        """Clip.countsAsCoverage (1.28): every take you keep. Only a take marked not usable before 1.28 doesn't."""
        return self.usable is not False


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


def coverage(clips, slot, day, trip_type="general", away=()):
    """Trip.coverage(for:day:): what each take does, with rows swiped away for the day (1.28)."""
    shot, half = slot
    want = slot_target(slot, trip_type)
    takes = [c for c in all_takes(clips) if c.shot == RAW[shot] and c.day == day]
    if half is not None:
        takes = [c for c in takes if c.variant == VARIANTS[shot][half]]
    takes.sort(key=lambda c: c.at)
    statuses = {c.id: "rejected" for c in takes if not c.counts}
    usable = [c for c in takes if c.counts]
    roles = roles_for(shot, trip_type) if half is None else []
    key = RAW[shot] + ("" if half is None else f"-{half}")
    done, lines, unsorted_count, row_away, away_roles = 0, {}, 0, False, set()
    if not roles:
        if not usable and key in away:
            row_away, want = True, 0
        for c in usable:
            if done < want:
                statuses[c.id] = "counts"
                done += 1
            else:
                statuses[c.id] = "extra"
    else:
        by_role, unsorted = {}, []
        for c in usable:
            (by_role.setdefault(c.role_id, []) if c.role_id else unsorted).append(c)
        counted = [r for r in roles if not r.optional and not r.substitute]
        away_roles = {r.id for r in roles if r.id not in by_role and f"{key}.{r.id}" in away}
        counted_away = sum(1 for r in counted if r.id in away_roles)
        spare = max(0, len(counted) - want)
        want = max(0, want - max(0, counted_away - spare))
        filling = set()
        for r in counted + [r for r in roles if r.substitute]:
            if done < want and by_role.get(r.id):
                statuses[by_role[r.id][0].id] = "counts"
                done += 1
                filling.add(r.id)
        for c in unsorted:
            if done < want:
                statuses[c.id] = "counts"
                done += 1
                unsorted_count += 1
        for c in usable:
            statuses.setdefault(c.id, "extra")
        for r in roles:
            lines[r.id] = {"usable": len(by_role.get(r.id, [])), "fills": r.id in filling,
                           "away": r.id in away_roles, "role": r}
    complete = done >= want
    open_roles = set() if complete else {r.id for r in roles if not r.optional and not lines[r.id]["usable"]
                                         and not lines[r.id]["away"]}
    return {"target": want, "done": done, "statuses": statuses, "lines": lines, "open": open_roles,
            "complete": complete, "away": row_away, "filmed": len(takes), "unsorted": unsorted_count}


def day_coverage(clips, day, trip_type, away=()):
    result = {level: [0, 0] for level in ("light", "everyday", "full")}
    for slot in ALL_SLOTS:
        if tier(slot[0], trip_type) == "extra":
            continue
        cov = coverage(clips, slot, day, trip_type, away)
        for level in result:
            g = goal(slot, level, trip_type, cov["target"])
            result[level][0] += min(cov["done"], g)
            result[level][1] += g
    return result


def progress(clips, part, day, trip_type="general", away=()):
    """Trip.progress(of:day:): what a part's shots that count have, out of what they need today."""
    done = want = 0
    for slot in part_slots(part):
        if tier(slot[0], trip_type) == "extra":
            continue
        cov = coverage(clips, slot, day, trip_type, away)
        done += min(cov["done"], cov["target"])
        want += cov["target"]
    return done, want


def row_takes(clips, row, day):
    """Trip.takes(of:day:)."""
    out = []
    for c in all_takes(clips):
        if c.shot != RAW[row.shot] or c.day != day or not c.counts:
            continue
        if row.half is not None:
            ok = c.variant == VARIANTS[row.shot][row.half]
        elif row.role is not None:
            ok = c.role_id == row.role
        elif row.variant is not None:
            ok = c.variant == VARIANTS.get(row.shot, [None] * 9)[row.variant]
        else:
            ok = True
        if ok:
            out.append(c)
    return out


def status(clips, row, day, trip_type="general", away=()):
    """Trip.status(of:day:): what a row shows on its right (1.28)."""
    filmed = len(row_takes(clips, row, day))
    if tier(row.shot, trip_type) == "extra":
        return ("filmed", filmed) if filmed else ("extra",)
    cov = coverage(clips, row.slot, day, trip_type, away)
    if row.role is not None and row.role in cov["lines"]:
        line = cov["lines"][row.role]
        if line["away"]:
            return ("notToday",)
        if line["usable"]:
            return ("filmed", line["usable"])
        if line["role"].optional:
            return ("optional",)
        if line["role"].substitute:
            return ("swapIn",)
        return ("spare",) if cov["complete"] else ("progress", 0, 1)
    if cov["away"]:
        return ("notToday",)
    return ("progress", cov["done"], cov["target"])


def can_set_aside(clips, row, day, trip_type="general"):
    """Trip.canSetAside: counts today, a usual row and not filmed yet."""
    if tier(row.shot, trip_type) == "extra" or row_takes(clips, row, day):
        return False
    if row.role is not None:
        usual = next((r for r in roles_for(row.shot, trip_type) if r.id == row.role), None)
        return usual is not None and not usual.optional and not usual.substitute
    return True

# ---------------------------------------------------------------- spots (1.28)


def distance(lat1, lon1, lat2, lon2):
    p1, p2 = radians(lat1), radians(lat2)
    a = sin((p2 - p1) / 2) ** 2 + cos(p1) * cos(p2) * sin(radians(lon2 - lon1) / 2) ** 2
    return 2 * 6_371_000 * asin(sqrt(a))


SPOT_DISTANCE = float(re.search(r"static let spotDistance: Double = (\d+)", COVERAGE_SRC).group(1))
SPOT_GAP = float(re.search(r"static let spotGap: TimeInterval = (\d+) \* 60", COVERAGE_SRC).group(1)) * 60


def spots(clips, day):
    """Trip.spots(onDay:): a new spot more than 250 m from where the last one started, or after 20 minutes."""
    result, current, anchor = [], [], None
    for c in sorted((c for c in clips if c.day == day), key=lambda c: c.at):
        if current:
            last = current[-1]
            if anchor is not None and None not in (anchor.lat, anchor.lon, c.lat, c.lon):
                new = distance(anchor.lat, anchor.lon, c.lat, c.lon) > SPOT_DISTANCE
            else:
                new = (c.at - last.at).total_seconds() > SPOT_GAP
            if new:
                result.append(current)
                current, anchor = [], None
        current.append(c)
        if anchor is None and c.lat is not None and c.lon is not None:
            anchor = c
    if current:
        result.append(current)
    return result


def spot_name(members):
    """ClipSpot.name: the name most clips share, the first given on a tie."""
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

# ---------------------------------------------------------------- ONE TAKE (1.24), ported from OneTake.swift


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


def one_take_plan(clips, parts, day, trip_type="general"):
    """Trip.oneTakePlan: what each part counts as today."""
    taken, result = set(), []
    for part in parts:
        shot = PART_SHOT[part]
        cov = coverage(clips, (shot, None), day, trip_type)
        order = PART_ROLES[part]
        if not order:
            result.append((part, None, not cov["complete"] and shot not in taken))
            taken.add(shot)
            continue
        covered = {rid for rid, line in cov["lines"].items() if line["usable"] > 0}
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


def film_one_take(clips, parts, starts, duration, walk_back_at=None, move="Run across", day=1, **kw):
    """Films a ONE TAKE the way ShotCameraView.saveTake and OneTakeRun.clipParts do, and adds it to `clips`."""
    reached = parts[:len(starts)]
    fills = {p: role for p, role, _ in one_take_plan(clips, reached, day)}
    takes, made = {}, []
    for part, (start, end) in zip(reached, filmed_ranges(starts, walk_back_at, duration)):
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
             at=datetime(2026, 11, 14, 10, 0), day=day, in_shot=True, duration=duration, parts=made, **kw)
    clips.append(c)
    return c


def default_starts(parts):
    starts, clock = [], 0.0
    for p in parts:
        starts.append(clock)
        clock += PART_LENGTH[p]
    return starts, clock

# ---------------------------------------------------------------- tests

results = []


def check(name, condition, detail=""):
    results.append((name, bool(condition), detail))


T0 = datetime(2026, 11, 16, 9, 0)
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
SLOMO = ("slomo", None)

# 1. Roles, read from the source
check("WIDE has 3 usual roles and an optional vertical hero",
      [r.id for r in ROLES["wide"]] == ["establishing", "human-scale", "alternative", "vertical-hero"]
      and ROLES["wide"][3].optional, [r.id for r in ROLES["wide"]])
check("B-ROLL has 6 usual kinds and 2 swap-ins",
      sum(not r.substitute for r in ROLES["bRoll"]) == 6 and sum(r.substitute for r in ROLES["bRoll"]) == 2)
check("DETAIL has 5 usual kinds and 1 swap-in",
      sum(not r.substitute for r in ROLES["detail"]) == 5 and sum(r.substitute for r in ROLES["detail"]) == 1)
check("ON THE WAY has four kinds (1.28): getting going, window, road ahead, pulling in",
      [r.id for r in ROLES["onTheWay"]] == ["getting-going", "window", "road-ahead", "pulling-in"])
check("SLOMO has water in your hand, and you in it on the tripod, optional on most days (1.28)",
      [(r.id, r.in_shot, r.optional) for r in ROLES["slomo"]] == [("water", False, False), ("you", True, True)])
check("Every role id is unique within its shot", all(len({r.id for r in v}) == len(v) for v in ROLES.values()))

# 2. The lists (1.28)
check("Your day is five parts, in the order you'd film them, plus B-roll any time and At home",
      DAY_PARTS == ["onTheWay", "arriving", "firstLook", "atTheSpot", "leaving"]
      and PARTS == DAY_PARTS + ["bRoll", "atHome"], PARTS)
ids = [row.id for row in ALL_ROWS]
check("Every row is on one list once", len(ids) == len(set(ids)), [i for i in ids if ids.count(i) > 1])
check("Every row with a role names one of its shot's roles",
      all(row.role is None or row.role_info is not None for row in ALL_ROWS))
missing_roles = [(shot, r.id) for shot, roles in ROLES.items() for r in roles
                 if not any(row.shot == shot and row.role == r.id for row in ALL_ROWS)]
check("Every role of every shot is a row of its own, so the camera never has to ask", missing_roles == [], missing_roles)
check("Every shot is on a list", {row.shot for row in ALL_ROWS} == set(RAW), set(RAW) - {row.shot for row in ALL_ROWS})
role_shots_whole = [row.id for row in ALL_ROWS if ROLES.get(row.shot) and row.role is None]
check("No shot with roles is listed without one", role_shots_whole == [], role_shots_whole)
check("At the spot, in order: WHIP · IN, the handheld views, then you in the view",
      [row.id for row in PART_ROWS["atTheSpot"]] == [
          "WHIP-1", "WIDE.establishing", "WIDE.alternative", "WIDE.vertical-hero", "SLOMO.water", "WIDE.human-scale",
          "WALKAWAY.into-view", "WALKAWAY.new-spot", "TELE", "MOMENT.with-place", "MOMENT.together", "SLOMO.you"],
      [row.id for row in PART_ROWS["atTheSpot"]])
check("The creative shots are in At the spot's drop-down, with TALK's one line, and HYPERLAPSE in Arriving's",
      [row.id for row in PART_CREATIVE["atTheSpot"]] == ["ONETAKE", "MATCHCUT", "CLONE", "ORBIT", "DANCE", "SILHOUETTE",
                                                       "TALK~1"]
      and [row.id for row in PART_CREATIVE["arriving"]] == ["HYPERLAPSE"])
check("Every creative shot is in a drop-down, and nothing else is",
      {row.shot for p in PART_CREATIVE.values() for row in p} == CREATIVE | {"talk"}
      and all(row.shot not in CREATIVE for p in PART_ROWS.values() for row in p))
check("At home: HOME before and after, TALK from your script and VOICEOVER",
      [row.id for row in PART_ROWS["atHome"]] == ["HOME-0", "HOME-1", "TALK~0", "VOICEOVER"])
check("B-roll's groups: B-roll, Detail, Sound, More and TIMELAPSE on the tripod",
      [g for g, _ in BROLL_GROUPS] == ["broll", "detail", "sound", "more", "tripod"]
      and [row.id for row in dict(BROLL_GROUPS)["sound"]] == ["AMBIENT", "SOUNDS"])
check("Leaving: WHIP · OUT, then STAY", [row.id for row in PART_ROWS["leaving"]] == ["WHIP-0", "STAY"])

# 3. The card before each shot (1.28)
no_card = [row.id for row in ALL_ROWS if card_for(row) is None]
check("Every row has a card of its own", no_card == [], no_card)
row_ids = set(ids) | {row.key for row in ALL_ROWS} | {RAW[row.shot] for row in ALL_ROWS}
check("Every card is for a row on the lists", set(CARDS) <= row_ids, sorted(set(CARDS) - row_ids))
check("Every card says what it is, where it goes and three steps to get it",
      all(c["what"] and c["where"] and len(c["how"]) == 3 for c in CARDS.values()),
      [k for k, c in CARDS.items() if not (c["what"] and c["where"] and len(c["how"]) == 3)])
check("Every card has 4 to 7 ideas, each with a line on how",
      all(4 <= len(c["ideas"]) <= 7 and all(t and h for t, h in c["ideas"]) for c in CARDS.values()),
      {k: len(c["ideas"]) for k, c in CARDS.items() if not 4 <= len(c["ideas"]) <= 7})
check("No idea is on a card twice", all(len({t for t, _ in c["ideas"]}) == len(c["ideas"]) for c in CARDS.values()))
words = " ".join(c["what"] + c["where"] + " ".join(c["how"]) + " ".join(t + h for t, h in c["ideas"])
                 for c in CARDS.values())
check("The cards are in plain words: no dashes standing in for commas", "—" not in words and " - " not in words)
check("Never film while driving: ON THE WAY's road ahead says only as the passenger",
      any("passenger" in step for step in CARDS["ONTHEWAY.road-ahead"]["how"]))
check("MATCH CUT's card lists the moves as its ideas",
      [t for t, _ in CARDS["MATCHCUT"]["ideas"]] == ["Run across", "Leap", "Arms out", "Spin", "Fall back", "Snap",
                                                     "Ridge walk"])
no_line = [row.id for row in ALL_ROWS if not (LINES.get(row.id) or LINES.get(row.key))]
check("Every row has a short line under its name", no_line == [], no_line)
check("The lines are short and end without a full stop",
      all(len(v) <= 48 and not v.endswith(".") for v in LINES.values()),
      [v for v in LINES.values() if len(v) > 48 or v.endswith(".")])
check("Every line is for a row", set(LINES) <= set(ids) | {row.key for row in ALL_ROWS}, set(LINES) - set(ids))

# 4. One take fills one role; every take you keep counts (1.28)
clips = []
clips.append(clip("WIDE", "establishing", existing=clips))
clips.append(clip("WIDE", "establishing", existing=clips))
cov = coverage(clips, WIDE, 1)
check("Two Establishing takes count once: WIDE 1/3, the repeat an extra",
      cov["done"] == 1 and cov["target"] == 3 and sorted(cov["statuses"].values()) == ["counts", "extra"], cov)
check("Open roles after it: Me in the view, Another angle", cov["open"] == {"human-scale", "alternative"}, cov["open"])
for role in ("human-scale", "alternative"):
    clips.append(clip("WIDE", role, existing=clips, in_shot=role == "human-scale"))
check("All three roles: WIDE 3/3", coverage(clips, WIDE, 1)["complete"])
clips.append(clip("WIDE", "vertical-hero", existing=clips))
check("The optional vertical hero never changes the target", coverage(clips, WIDE, 1)["target"] == 3)
check("A take that failed its check still counts: you keep it or delete it (1.28)",
      coverage([clip("WIDE", "establishing", check_passed=False)], WIDE, 1)["done"] == 1)
check("…and so does one you stopped early",
      coverage([clip("WIDE", "establishing", duration=4, planned=22)], WIDE, 1)["done"] == 1)
old = clip("WIDE", "establishing", usable=False)
check("A take marked not usable before 1.28 still doesn't count",
      coverage([old], WIDE, 1)["statuses"][old.id] == "rejected" and coverage([old], WIDE, 1)["done"] == 0)
clips = []
for role in ("atmosphere", "movement", "local", "lens-angle", "transition", "nature"):
    clips.append(clip("BROLL", role, existing=clips))
check("No people at a lookout: Nature swaps in, B-ROLL 6/6", coverage(clips, BROLL, 1)["complete"])
check("Six takes of the same kind count once: B-ROLL 1/6",
      coverage([clip("BROLL", "atmosphere") for _ in range(6)], BROLL, 1)["done"] == 1)
older = [clip("WIDE", None, take=1), clip("WIDE", None, take=2), clip("WIDE", None, take=3, in_shot=True),
         clip("REVEAL", None, take=1, variant="Tilt up"), clip("SLOMO", None, take=1, in_shot=True),
         clip("SLOMO", None, take=2), clip("BROLL", None, take=1), clip("WIDE", None, take=4, added=True)]
check("Older takes get roles from how they were filmed: WIDE, REVEAL, and SLOMO by whether you were in it",
      [c.role_id for c in older[:6]] == ["establishing", "alternative", "human-scale", "tilt-up", "you", "water"])
check("Older B-ROLL and clips from Photos have no role, and still count",
      older[6].role_id is None and older[7].role_id is None and coverage(older, BROLL, 1)["done"] == 1)

# 5. Not today (1.28)
detail_away = ("DETAIL.hands",)
cov = coverage([], DETAIL, 1, "general", detail_away)
check("DETAIL needs 4 of its 5 kinds: one swiped away changes nothing", cov["target"] == 4, cov["target"])
cov = coverage([], DETAIL, 1, "general", ("DETAIL.hands", "DETAIL.object"))
check("…a second takes it to 3", cov["target"] == 3, cov["target"])
cov = coverage([], WIDE, 1, "general", ("WIDE.human-scale",))
check("WIDE needs all three of its roles: one swiped away takes it to 2", cov["target"] == 2)
cov = coverage([clip("DETAIL", "hands")], DETAIL, 1, "general", ("DETAIL.hands", "DETAIL.object"))
check("A row you've filmed is never away: DETAIL stays 4 with only Object swiped away", cov["target"] == 4, cov)
cov = coverage([], ("tele", None), 1, "mountain", ("TELE",))
check("A shot without roles swiped away needs nothing today", cov["target"] == 0 and cov["away"] and cov["complete"])
general = day_coverage([], 1, "general")
mountain_away = day_coverage([], 1, "mountain", ("TELE",))
check("Swiping a shot away lowers the day's total by what it needed",
      day_coverage([], 1, "mountain")["everyday"][1] - mountain_away["everyday"][1] == 1)
check("Not today is for one day: day 2 still needs it",
      coverage([], ("tele", None), 2, "mountain")["target"] == 1)
row = Row("detail", role="hands")
check("A swiped-away row shows Not today", status([], row, 1, "general", ("DETAIL.hands",)) == ("notToday",))
check("Rows that count and aren't filmed can be swiped; filmed ones, swap-ins, optional ones and extras can't",
      can_set_aside([], Row("detail", role="hands"), 1) and can_set_aside([], Row("tele"), 1, "mountain")
      and not can_set_aside([clip("DETAIL", "hands")], Row("detail", role="hands"), 1)
      and not can_set_aside([], Row("detail", role="nature"), 1)
      and not can_set_aside([], Row("wide", role="vertical-hero"), 1)
      and not can_set_aside([], Row("food"), 1) and not can_set_aside([], Row("matchCut"), 1, "road"))

# 6. What each row shows (1.28)
clips = [clip("WIDE", "alternative"), clip("WIDE", "alternative")]
check("A role filmed twice shows a tick and 2", status(clips, Row("wide", role="alternative"), 1) == ("filmed", 2))
check("A role still to film shows 0/1", status(clips, Row("wide", role="establishing"), 1) == ("progress", 0, 1))
check("WIDE's vertical hero is optional, and B-ROLL's swap-ins say so",
      status([], Row("wide", role="vertical-hero"), 1) == ("optional",)
      and status([], Row("bRoll", role="nature"), 1) == ("swapIn",))
check("At falls the vertical hero counts, so it's 0/1 there",
      status([], Row("wide", role="vertical-hero"), 1, "falls") == ("progress", 0, 1))
done4 = [clip("DETAIL", r) for r in ("texture", "object", "hands", "foreground")]
check("Once DETAIL has its 4, the fifth kind is an extra, not 0/1",
      status(done4, Row("detail", role="only-here"), 1) == ("spare",))
check("A creative shot is an extra until it's filmed, then a tick",
      status([], Row("clone"), 1) == ("extra",) and status([clip("CLONE")], Row("clone"), 1) == ("filmed", 1))
check("A shot without roles shows done of target: AMBIENT 0/1", status([], Row("ambient"), 1) == ("progress", 0, 1))
whip_in = clip("WHIP", variant="In")
check("WHIP's halves are counted apart", status([whip_in], Row("whip", half=1), 1) == ("filmed", 1)
      and status([whip_in], Row("whip", half=0), 1) == ("extra",))
check("TALK's two versions are counted apart",
      len(row_takes([clip("TALK", variant="One line")], Row("talk", variant=1), 1)) == 1
      and len(row_takes([clip("TALK", variant="One line")], Row("talk", variant=0), 1)) == 0)

# 7. The creative shots and the ones filmed at home never count (1.28)
check("Creative: ONE TAKE, MATCH CUT, CLONE, ORBIT, DANCE, SILHOUETTE and HYPERLAPSE",
      CREATIVE == {"oneTake", "matchCut", "clone", "orbit", "dance", "silhouette", "hyperlapse"}, CREATIVE)
check("At home: HOME, TALK and VOICEOVER", AT_HOME == {"home", "talk", "voiceover"}, AT_HOME)
check("They're extras on every type of day, whatever the type's table says (MATCH CUT on a road trip, too)",
      all(tier(shot, t) == "extra" for shot in CREATIVE | AT_HOME for t in TYPES)
      and tuned("matchCut", "road", "tier") == "core")
check("Filming them changes no level", day_coverage([clip("TALK", variant="At home"), clip("CLONE"),
                                                     clip("SILHOUETTE")], 1, "general") == day_coverage([], 1, "general"))

# 8. SLOMO and ON THE WAY's kinds (1.28)
water = clip("SLOMO", "water")
you = clip("SLOMO", "you", in_shot=True)
check("A general day needs one SLOMO: water counts, you in it on its own is optional",
      coverage([water], SLOMO, 1)["complete"] and coverage([you], SLOMO, 1)["done"] == 0
      and status([], Row("slomo", role="you"), 1) == ("optional",))
check("Falls, beaches and snow need two, so you in it counts there",
      all(coverage([water, you], SLOMO, 1, t)["done"] == 2 and coverage([water, you], SLOMO, 1, t)["target"] == 2
          for t in ("falls", "beach", "snow")))
kinds = [clip("ONTHEWAY", r) for r in ("getting-going", "window", "road-ahead", "pulling-in")]
check("A road trip needs all four kinds of ON THE WAY", coverage(kinds[:3], ("onTheWay", None), 1, "road")["done"] == 3
      and not coverage(kinds[:3], ("onTheWay", None), 1, "road")["complete"]
      and coverage(kinds, ("onTheWay", None), 1, "road")["complete"])
check("Two windows count once", coverage([clip("ONTHEWAY", "window"), clip("ONTHEWAY", "window")],
                                         ("onTheWay", None), 1, "road")["done"] == 1)

# 9. Levels and totals per type of place
totals_now = {t: tuple(day_coverage([], 1, t)[level][1] for level in ("light", "everyday", "full")) for t in TYPES}
# 1.28: TALK, MATCH CUT, SILHOUETTE and HYPERLAPSE no longer count, so full days are smaller, and a road trip's
# everyday loses MATCH CUT.
expected_totals = {"general": (10, 22, 25), "mountain": (10, 23, 26), "falls": (10, 26, 29), "beach": (10, 24, 27),
                   "city": (10, 24, 28), "road": (10, 24, 27), "snow": (10, 25, 26)}
for trip_type, want in expected_totals.items():
    check(f"{trip_type}: light, everyday and full targets", totals_now[trip_type] == want, totals_now[trip_type])
clips = []
for shot, role in [("WIDE", "establishing"), ("WIDE", "human-scale"), ("BROLL", "atmosphere"), ("BROLL", "people"),
                   ("BROLL", "movement"), ("DETAIL", "texture"), ("DETAIL", "hands"), ("POV", "approach"),
                   ("REVEAL", "tilt-up"), ("MOMENT", "with-place")]:
    clips.append(clip(shot, role, existing=clips))
totals = day_coverage(clips, 1, "general")
check("A light day's ten clips: light 10/10", totals["light"] == [10, 10], totals)
check("Light counts towards everyday, everyday towards full",
      totals["light"][0] <= totals["everyday"][0] <= totals["full"][0])
check("REACTION counts towards a full day only",
      day_coverage(clips + [clip("REACTION")], 1, "general")["full"][0] == totals["full"][0] + 1
      and day_coverage(clips + [clip("REACTION")], 1, "general")["everyday"][0] == totals["everyday"][0])

# 10. Each part's progress (1.28)
check("Parts add up to the day's full total: everything that counts is on one list",
      sum(progress([], p, 1)[1] for p in PARTS) == day_coverage([], 1, "general")["full"][1])
check("At home and the creative shots never add to a part", progress([], "atHome", 1) == (0, 0))
check("On the way only counts on a road trip", progress([], "onTheWay", 1) == (0, 0)
      and progress([], "onTheWay", 1, "road") == (0, 4))
at_spot = [clip("WIDE", "establishing"), clip("WIDE", "establishing"), clip("TELE")]
check("At the spot on a mountain: a repeat doesn't add, TELE does",
      progress(at_spot, "atTheSpot", 1, "mountain")[0] == 2, progress(at_spot, "atTheSpot", 1, "mountain"))

# 11. Spots (1.28)
lake = (40.3127, -105.6450)
falls = (40.3040, -105.6400)                                                          # ~1 km on
clips = [clip("WIDE", "establishing", lat=lake[0], lon=lake[1], at=T0, name="Bear Lake"),
         clip("BROLL", "atmosphere", lat=lake[0] + 0.0015, lon=lake[1], at=T0 + timedelta(minutes=5)),   # ~170 m
         clip("DETAIL", "texture", lat=lake[0] + 0.0030, lon=lake[1], at=T0 + timedelta(minutes=9),      # ~330 m
              name="Bear Lake"),
         clip("WIDE", "alternative", lat=falls[0], lon=falls[1], at=T0 + timedelta(hours=1), name="Alberta Falls")]
groups = spots(clips, 1)
check("A new spot starts more than 250 m from where the last one started, not from the last clip",
      [len(g) for g in groups] == [2, 1, 1], [len(g) for g in groups])
check("A spot's name is the one its clips share", [spot_name(g) for g in groups] == ["Bear Lake", "Bear Lake",
                                                                                      "Alberta Falls"])
no_gps = [clip("BROLL", "people", at=T0), clip("BROLL", "movement", at=T0 + timedelta(minutes=15)),
          clip("BROLL", "local", at=T0 + timedelta(minutes=40))]
check("Without locations, a new spot after 20 minutes with nothing filmed", [len(g) for g in spots(no_gps, 1)] == [2, 1])
check("Spots never change the counts",
      day_coverage(clips, 1, "general") == day_coverage([replace(c, lat=None, lon=None) for c in clips], 1, "general"))

# 12. ONE TAKE
PARTS_1T = PART_ORDER
starts, total = default_starts(PARTS_1T)
check("ONE TAKE's parts, in order: empty frame, walk in, in the view, moment, MATCH CUT, clones",
      PARTS_1T == ["emptyFrame", "walkIn", "inView", "moment", "matchCut", "clones"], PARTS_1T)
clips = []
first = film_one_take(clips, PARTS_1T, starts, duration=400, walk_back_at=total)
check("Its parts fill Establishing, Into the view, Me in the view, With the place, MATCH CUT and CLONE",
      [(p["shot"], p["role"]) for p in first.parts] == [("WIDE", "establishing"), ("WALKAWAY", "into-view"),
                                                       ("WIDE", "human-scale"), ("MOMENT", "with-place"),
                                                       ("MATCHCUT", None), ("CLONE", None)])
check("WIDE 2/3, WALKAWAY 1/2, MOMENT 1/2 from one take",
      [coverage(clips, (s, None), 1)["done"] for s in ("wide", "walkaway", "moment")] == [2, 1, 1])
second = film_one_take(clips, PARTS_1T, starts, duration=380, walk_back_at=total)
check("A second ONE TAKE fills the second roles: Another angle, New spot or action",
      [(p["shot"], p["role"]) for p in second.parts][:2] == [("WIDE", "alternative"), ("WALKAWAY", "new-spot")])
check("Its parts count on the rows: WIDE · Another angle shows a tick",
      status(clips, Row("wide", role="alternative"), 1) == ("filmed", 1))

# 13. Which way each shot is filmed (1.25.1)
FILMING = switch_values(SHOT_SRC, "    var filming: Filming {", "portrait")
check("The big views stay landscape",
      {s for s, f in FILMING.items() if f == "landscape"} == {"wide", "tele", "walkaway", "silhouette", "timelapse",
                                                              "reflection", "matchCut", "onTheWay", "wildlife", "oneTake"})
check("Only REVEAL and B-ROLL go both ways", {s for s, f in FILMING.items() if f == "either"} == {"reveal", "bRoll"})

# 14. Each type of place gets the shots its reels need (1.26)
missing_tips = [(t, shot) for t in TYPES for shot in RAW if not (tuned(shot, t, "summary") or "").strip()]
check("Every type of place has a tip for every shot", set(TUNING) == set(TYPES) and missing_tips == [], missing_tips[:6])


def light_day(trip_type):
    return {slot[0]: light_target(slot, trip_type) for slot in ALL_SLOTS if light_target(slot, trip_type) > 0}


check("General's light day: WIDE 2, B-ROLL 3, DETAIL 2, POV, REVEAL and MOMENT 1",
      light_day("general") == {"wide": 2, "bRoll": 3, "detail": 2, "pov": 1, "reveal": 1, "moment": 1},
      light_day("general"))
signature = {"mountain": ("tele", "bRoll"), "falls": ("slomo", "bRoll"), "beach": ("slomo", "bRoll"),
             "city": ("food", "wide"), "road": ("onTheWay", "bRoll"), "snow": ("slomo", "bRoll")}
for trip_type, (shot, makes_room) in signature.items():
    days = light_day(trip_type)
    check(f"{trip_type}: a light day is 10 clips with its signature shot ({shot}) in place of a {makes_room}",
          sum(days.values()) == 10 and days.get(shot) == 1 and days[makes_room] == light_day("general")[makes_room] - 1,
          days)

failed = [r for r in results if not r[1]]
for name, ok, detail in results:
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  ({detail})"))
print(f"\n{len(results) - len(failed)} of {len(results)} passed")
sys.exit(1 if failed else 0)
