#!/usr/bin/env python3
"""Checks how each shot's walkthrough fits a length you've changed (1.23), and the few words the prompt shows while
you film. A model of ShotPlan.timeline(endingAt:) and GuideStep.headline, run over every step list in
ShotType.swift at every length the timing control offers. (In the app, the stretching applies to shots you're
holding; shots you're in keep their steps where they were written, as before.)

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

print(f"{sum(results)} of {len(results)} passed")
sys.exit(0 if all(results) else 1)
