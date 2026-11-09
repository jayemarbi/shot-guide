#!/usr/bin/env python3
"""Checks how each shot's walkthrough fits a length you've changed (1.23), the few words the prompt shows while
you film, and the flashes that lead you through a shot you're in (1.24). A model of ShotPlan.timeline(endingAt:),
GuideStep.headline and TakeDirector's lead-ins, run over every step list in ShotType.swift at every length the timing
control offers. Since 1.24 the stretching applies to the shots you're in too, and the flashes follow the steps.

Run: python3 tools/test_timeline.py [path to the repo]
"""

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
SHOT_SRC = (ROOT / "ShotGuide" / "Models" / "ShotType.swift").read_text(encoding="utf-8")
TIMING_SRC = (ROOT / "ShotGuide" / "Views" / "TimingControls.swift").read_text(encoding="utf-8")

SHORT = float(re.search(r"static let shortStep: Double = ([\d.]+)", SHOT_SRC).group(1))
LENGTHS = [float(x) for x in re.search(r"static let lengthSteps: \[Double\] = \[([^\]]+)\]", TIMING_SRC).group(1).split(",")]
STEP = re.compile(r'GuideStep\(start: ([\d.]+), end: ([\d.]+|nil), text: "((?:[^"\\]|\\.)*)"\)')

results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  [{detail}]"))


def step_lists():
    """Every auto-stop plan's steps, as (line, autoStop, [(start, end, text)])."""
    found = []
    for m in re.finditer(r"autoStop: (\d+(?:\.\d+)?)", SHOT_SRC):
        tail = SHOT_SRC[m.end():m.end() + 4000]
        at = tail.find("steps: [")
        if at < 0 or at > 1500:
            continue
        block, depth = "", 0
        for ch in tail[at + len("steps: "):]:
            block += ch
            depth += ch == "["
            depth -= ch == "]"
            if depth == 0:
                break
        if "?" in block.replace("\\?", ""):
            continue                                    # a step chosen by a condition: not modelled here
        steps = [(float(a), None if b == "nil" else float(b), t) for a, b, t in STEP.findall(block)]
        if steps:
            found.append((SHOT_SRC[:m.start()].count("\n") + 1, float(m.group(1)), steps))
    return found


def swift_round(x):
    """Double.rounded(): halves away from zero."""
    return float(int(x + 0.5)) if x >= 0 else -float(int(-x + 0.5))


def timeline(steps, end):
    """ShotPlan.timeline(endingAt:)."""
    first = steps[0]
    if end <= first[0]:
        return steps
    lengths = []
    for i, (start, stop, _) in enumerate(steps):
        stop = stop if stop is not None else (steps[i + 1][0] if i + 1 < len(steps) else end)
        lengths.append(max(0.0, stop - start))
    written = sum(lengths)
    if abs(first[0] + written - end) < 0.01:
        return [(s, s + n, t) for (s, _, t), n in zip(steps, lengths)]
    room = end - first[0]
    fixed = sum(n for n in lengths if n <= SHORT)
    stretchy = written - fixed
    if stretchy > 0 and room > fixed:
        fitted = [n if n <= SHORT else n * (room - fixed) / stretchy for n in lengths]
    elif written > 0:
        fitted = [n * room / written for n in lengths]
    else:
        fitted = [room / len(lengths)] * len(lengths)
    out, clock = [], first[0]
    for i, (_, _, text) in enumerate(steps):
        start = swift_round(clock)
        clock += fitted[i]
        stop = end if i == len(steps) - 1 else min(swift_round(clock), end)
        if stop > start:
            out.append((start, stop, text))
    return out or [(first[0], end, first[2])]


def headline(text):
    """GuideStep.headline."""
    cut = len(text)
    for mark in (": ", ". ", "; "):
        i = text.find(mark)
        if 0 <= i < cut:
            cut = i
    words = text[:cut]
    if words.endswith("."):
        words = words[:-1]
    return words or text


plans = step_lists()
check(f"Found the shots' step lists ({len(plans)})", len(plans) >= 40, len(plans))

# At the length they were written for, the steps are exactly as written.
unchanged = all(timeline(steps, stop) == [(s, s + ((e if e is not None else stop) - s), t) for s, e, t in steps]
                for _, stop, steps in plans)
check("At its own length, every walkthrough is exactly as written", unchanged)

# At every length the timing control offers.
problems = []
for line, stop, steps in plans:
    lengths = [n for s, e, _ in steps for n in [(e if e is not None else stop) - s]]
    for length in LENGTHS:
        got = timeline(steps, length)
        if got[0][0] != steps[0][0]:
            problems.append((line, length, "start"))
        if abs(got[-1][1] - length) > 1e-9:
            problems.append((line, length, "end"))
        if any(abs(a[1] - b[0]) > 1e-9 for a, b in zip(got, got[1:])):
            problems.append((line, length, "gap"))
        if any(e <= s for s, e, _ in got):
            problems.append((line, length, "empty step"))
        if any(s != int(s) for s, _, _ in got):
            problems.append((line, length, "not whole seconds"))
        if length >= sum(lengths) and any(n > SHORT for n in lengths):
            kept = {t: e - s for s, e, t in got}
            for (s, e, t), n in zip(steps, lengths):
                if n <= SHORT and t in kept and abs(kept[t] - n) > 1:
                    problems.append((line, length, f"short step changed: {t[:20]}"))
check("At every length: starts at 0, no gaps, whole seconds, no empty steps, ends exactly at the length",
      not [p for p in problems if not p[2].startswith("short")], problems[:5])
check("Longer than written: starting and stopping steps keep their length (within a second of rounding)",
      not [p for p in problems if p[2].startswith("short")], [p for p in problems if p[2].startswith("short")][:5])

# The examples Jody asked about.
pov = next(steps for _, stop, steps in plans if steps[1][2].startswith("Walk smoothly towards it"))
check("POV · Approach at 25 s: 0–2 start, 2–22 walk, 22–25 ease to a stop",
      [(s, e) for s, e, _ in timeline(pov, 25)] == [(0, 2), (2, 22), (22, 25)], timeline(pov, 25))
check("POV · Approach at 15 s, as written: 0–2, 2–12, 12–15",
      [(s, e) for s, e, _ in timeline(pov, 15)] == [(0, 2), (2, 12), (12, 15)])
check("POV · Approach at 10 s: the walk shrinks, 0–2, 2–7, 7–10",
      [(s, e) for s, e, _ in timeline(pov, 10)] == [(0, 2), (2, 7), (7, 10)], timeline(pov, 10))
check("Nothing longer than the take: POV · Approach at 3 s still fits, 0–1, 1–2, 2–3",
      timeline(pov, 3)[-1][1] == 3 and len(timeline(pov, 3)) >= 2, timeline(pov, 3))

slomo = next(steps for _, stop, steps in plans if steps[0][2] == "Get set.")
check("A walkthrough of only short steps (SLOMO in the shot) changes in proportion: at 16 s, 0–6, 6–12, 12–16",
      [(s, e) for s, e, _ in timeline(slomo, 16)] == [(0, 6), (6, 12), (12, 16)], timeline(slomo, 16))

# The prompt's few words.
texts = [t for _, _, steps in plans for _, _, t in steps]
check("Every step has a headline for the prompt", all(headline(t) for t in texts))
check("Headlines: 'Walk smoothly towards it', 'Hold the frame', 'Start moving slowly'",
      headline("Walk smoothly towards it: feet, hands, the track ahead.") == "Walk smoothly towards it"
      and headline("Hold the frame. No panning.") == "Hold the frame"
      and headline("Start moving slowly.") == "Start moving slowly")
check("The extra seconds' step reads 'Keep the phone steady for 2 more seconds'",
      headline("Keep the phone steady for 2 more seconds. It gives the edit room.")
      == "Keep the phone steady for 2 more seconds")

# The flashes into each step while you're in the shot (TakeDirector.startTimeline, 1.24): 5 flashes, one a second,
# leading into every step whose step before is 5 seconds or more.
def lead_ins(steps):
    cues = []
    for i in range(1, len(steps)):
        if steps[i][0] - steps[i - 1][0] >= 5:
            cues.append([steps[i][0] - k for k in (5, 4, 3, 2, 1)])
    return cues


bad = []
for line, stop, steps in plans:
    for length in LENGTHS:
        got = timeline(steps, length)
        cues = lead_ins(got)
        flat = [t for cue in cues for t in cue]
        if any(t < 0 for t in flat):
            bad.append((line, length, "before the take"))
        if len(flat) != len(set(flat)):
            bad.append((line, length, "overlap"))
        for cue, step in zip(cues, [s for i, s in enumerate(got) if i and got[i][0] - got[i - 1][0] >= 5]):
            if cue[-1] != step[0] - 1:
                bad.append((line, length, "not leading into its step"))
check("Every shot at every length: 5 flashes into each step there's room for, never before the take, never overlapping",
      not bad, bad[:5])

walk = next(steps for _, stop, steps in plans if steps[1][2].startswith("Walk in and keep going. Don't look back."))
check("WALKAWAY (30 s since 1.24): flashes at 13–17 into Stop and look out, and 22–26 into Hold still",
      lead_ins(timeline(walk, 30)) == [[13, 14, 15, 16, 17], [22, 23, 24, 25, 26]], lead_ins(timeline(walk, 30)))

clone = next(steps for _, stop, steps in plans if steps[0][2].startswith("Empty frame. Stay out of shot"))
check("CLONE (3:00 since 1.24): 10 s empty, a new spot every 30 s, walk out for the last 20",
      [s for s, _, _ in timeline(clone, 180)] == [0, 10, 40, 70, 100, 130, 160])

# ONE TAKE (TakeDirector.startOneTake): each part for its length, 5 flashes into the next, clones nudged to a new spot
# every 30 seconds and into walking out for the last 30, then the walk-back flicker.
ONE_SRC = (ROOT / "ShotGuide" / "Models" / "OneTake.swift").read_text(encoding="utf-8")
body = ONE_SRC.split("var defaultLength: Double {", 1)[1].split("\n    }\n", 1)[0]
LENGTH = {}
for cases, value in re.findall(r"case ([.\w, ]+?):\s*return ([\d.]+)", body):
    for case in re.findall(r"\.(\w+)", cases):
        LENGTH[case] = float(value)
ORDER = re.findall(r"case (\w+)\n", ONE_SRC.split("enum OneTakePart", 1)[1].split("var id", 1)[0])


def one_take_cues(parts, lengths, found_after=0.0):
    """Every flash, and when the walk-back flicker comes, for a ONE TAKE where MATCH CUT's part finds you
    `found_after` seconds after it begins."""
    flashes, clock, events = [], 0.0, []
    for i, part in enumerate(parts):
        start = clock
        if part == "matchCut":
            found = start + found_after
            flashes += [found + k for k in range(5)]
            clock = found + 5
            events.append(("move", clock))
        end = clock + lengths[i]
        if part == "clones" and end - clock >= 60:
            nudge = clock + 30
            while nudge <= end - 60:
                flashes += [nudge - k for k in (5, 4, 3, 2, 1)]
                nudge += 30
            flashes += [end - 30 - k for k in (5, 4, 3, 2, 1)]
        if i + 1 < len(parts):
            flashes += [end - k for k in (5, 4, 3, 2, 1)]
        events.append((part, start, end))
        clock = end
    return sorted(flashes), clock, events


lengths = [LENGTH[p] for p in ORDER]
flashes, back, events = one_take_cues(ORDER, lengths, found_after=12)
check("ONE TAKE: no two flashes at once, all inside the take", len(flashes) == len(set(flashes)) and min(flashes) >= 0
      and max(flashes) < back, flashes)
check("ONE TAKE: MATCH CUT's 30 seconds start 5 s after it finds you, so finding you never eats into them",
      ("move", 197.0) in events and ("matchCut", 180.0, 227.0) in events, events)
check("ONE TAKE: clones nudged at 30, 60 and 90 s in, and told to walk out 30 s before the end",
      [t for t in flashes if 227 < t < 377] == [252, 253, 254, 255, 256, 282, 283, 284, 285, 286, 312, 313, 314, 315,
                                                316, 342, 343, 344, 345, 346], [t for t in flashes if 227 < t < 377])
check("ONE TAKE: you walk back at 6:17 here (6:00 of parts, 12 s finding you and the 5 flashes into your move)",
      back == 377, back)

print(f"{sum(results)} of {len(results)} passed")
sys.exit(0 if all(results) else 1)
