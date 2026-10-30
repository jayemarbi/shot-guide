"""Cheap static checks for the Swift sources (no Swift compiler is available here).

1. Brackets balance, honouring strings, string interpolation and comments.
2. Dictionary literals have no duplicate keys (a runtime crash in Swift).
3. Every guide timeline is in order, has no gaps, and fits inside its auto-stop.
"""
import re
import sys
from pathlib import Path

PAIRS = {")": "(", "]": "[", "}": "{"}


def check_brackets(path: Path) -> list[str]:
    src = path.read_text(encoding="utf-8")
    errors = []
    stack = []  # entries: (char, line) for code brackets, ("STR", line, multiline) for strings, ("INTERP", line)
    i, line = 0, 1
    n = len(src)
    mode = ["code"]  # stack of modes: "code", "str", "mstr", "interp"
    while i < n:
        ch = src[i]
        m = mode[-1]
        if ch == "\n":
            line += 1
        if m in ("code", "interp"):
            if src.startswith("//", i):
                j = src.find("\n", i)
                i = n if j == -1 else j
                continue
            if src.startswith("/*", i):
                j = src.find("*/", i + 2)
                line += src[i:j].count("\n")
                i = n if j == -1 else j + 2
                continue
            if src.startswith('"""', i):
                mode.append("mstr")
                i += 3
                continue
            if ch == '"':
                mode.append("str")
                i += 1
                continue
            if ch in "([{":
                stack.append((ch, line))
            elif ch in ")]}":
                if m == "interp" and ch == ")" and (not stack or stack[-1][0] == "INTERP"):
                    stack.pop()
                    mode.pop()
                    i += 1
                    continue
                if not stack or stack[-1][0] != PAIRS[ch]:
                    errors.append(f"{path.name}:{line}: unexpected '{ch}' (open: {stack[-1] if stack else None})")
                else:
                    stack.pop()
            i += 1
            continue
        # inside a string
        if src.startswith("\\(", i):
            stack.append(("INTERP", line))
            mode.append("interp")
            i += 2
            continue
        if ch == "\\":
            i += 2
            continue
        if m == "mstr" and src.startswith('"""', i):
            mode.pop()
            i += 3
            continue
        if m == "str" and ch == '"':
            mode.pop()
            i += 1
            continue
        if m == "str" and ch == "\n":
            errors.append(f"{path.name}:{line}: unterminated string")
            mode.pop()
        i += 1
    for item in stack:
        errors.append(f"{path.name}:{item[1]}: unclosed '{item[0]}'")
    if len(mode) != 1:
        errors.append(f"{path.name}: ended inside {mode[-1]}")
    return errors


def check_duplicate_keys(path: Path) -> list[str]:
    src = path.read_text(encoding="utf-8")
    errors = []
    for match in re.finditer(r"static let (\w+): \[String: String\] = \[(.*?)\n    \]", src, re.S):
        name, body = match.group(1), match.group(2)
        keys = re.findall(r'^\s*"([^"]+)"\s*:', body, re.M)
        seen = set()
        for key in keys:
            if key in seen:
                errors.append(f"{path.name}: duplicate key {key!r} in {name}")
            seen.add(key)
        print(f"  {path.name}: {name} has {len(keys)} keys")
    return errors


def check_timelines(path: Path) -> list[str]:
    src = path.read_text(encoding="utf-8")
    errors = []
    chunks = src.split("return ShotPlan(")[1:]
    for chunk in chunks:
        block = re.split(r"\n\s*(?:case \.|if |return ShotPlan)", chunk)[0]
        stop = re.search(r"autoStop: ([\d.]+|nil)", block)
        auto_stop = None if not stop or stop.group(1) == "nil" else float(stop.group(1))
        has_stop_arg = stop is not None
        for steps_block in re.findall(r"\[\s*(GuideStep\(.*?)\]", block, re.S):
            steps = re.findall(r'GuideStep\(start: ([\d.]+), end: ([\d.]+|nil), text: "(.*?)"\)', steps_block)
            prev_end = 0.0
            for idx, (start, end, text) in enumerate(steps):
                s0 = float(start)
                if abs(s0 - prev_end) > 1e-9:
                    errors.append(f"gap/overlap before '{text}': starts {s0}, previous ended {prev_end}")
                if end == "nil":
                    if idx != len(steps) - 1:
                        errors.append(f"open-ended step not last: '{text}'")
                    prev_end = s0
                else:
                    e = float(end)
                    if e <= s0:
                        errors.append(f"step ends before it starts: '{text}'")
                    prev_end = e
            last_end = steps[-1][1] if steps else "nil"
            label = steps[0][2] if steps else "?"
            if auto_stop is not None and last_end != "nil" and abs(float(last_end) - auto_stop) > 1e-9:
                errors.append(f"autoStop {auto_stop} != last step end {last_end} (plan starting '{label}')")
            if auto_stop is not None and last_end == "nil":
                errors.append(f"auto-stopping plan has an open-ended last step (plan starting '{label}')")
            if auto_stop is None and has_stop_arg and last_end != "nil":
                errors.append(f"manual-stop plan should end with an open step (plan starting '{label}')")
            print(f"  plan '{label[:40]}': {len(steps)} steps, autoStop={auto_stop}, last end={last_end}")
    return errors


def main(root: str) -> int:
    files = sorted(Path(root).rglob("*.swift"))
    errors = []
    for f in files:
        errors += check_brackets(f)
    errors += check_duplicate_keys(Path(root) / "Models/TagVocabulary.swift")
    errors += check_duplicate_keys(Path(root) / "Models/GeoData.swift")
    errors += check_timelines(Path(root) / "Models/ShotType.swift")
    print(f"checked {len(files)} files")
    for e in errors:
        print("ERROR", e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
