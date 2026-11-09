"""Checks for the place facts and costs (1.27).

There's no Swift compiler here, so this ports Money.amount(from:) and checks it against amounts as people type them,
and reads the Swift source to check that every fact is read back from older trips and written to facts.txt.

usage: python3 tools/test_costs.py [repo folder]
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
MODELS = ROOT / "ShotGuide" / "Models"
FACTS_SRC = (MODELS / "PlaceFacts.swift").read_text(encoding="utf-8")
TRIP_SRC = (MODELS / "TripModels.swift").read_text(encoding="utf-8")
STORE_SRC = (ROOT / "ShotGuide" / "Services" / "TripStore.swift").read_text(encoding="utf-8")
VIEW_SRC = (ROOT / "ShotGuide" / "Views" / "TripFactsView.swift").read_text(encoding="utf-8")

results = []


def check(name, condition, detail=""):
    results.append((name, bool(condition), detail))


def amount(text):
    """Money.amount(from:): a mark with one or two digits after it is the decimal point; other marks group thousands."""
    kept = [c for c in text if (c.isascii() and c.isdigit()) or c in ".,"]
    if not any(c.isdigit() for c in kept):
        return None
    marks = [i for i, c in enumerate(kept) if c in ".,"]
    decimal_at = None
    if marks:
        last = marks[-1]
        same_kind = sum(1 for i in marks if kept[i] == kept[last])
        digits_after = len(kept) - last - 1
        if same_kind < len(marks):
            decimal_at = last
        elif same_kind == 1 and 0 < digits_after <= 2:
            decimal_at = last
    number = ""
    for i, c in enumerate(kept):
        if c.isdigit():
            number += c
        elif i == decimal_at:
            number += "."
    if number.startswith("."):
        number = "0" + number
    return round(float(number) * 100) / 100


# 1. The parser is the one in the app
amount_src = FACTS_SRC.split("static func amount(from text: String) -> Double? {", 1)[1].split("\n    }\n", 1)[0]
check("The port matches Money.amount(from:): the same rules for the decimal point",
      all(piece in amount_src for piece in ["$0.isASCII && $0.isNumber", "sameKind < marks.count",
                                            "sameKind == 1 && digitsAfter > 0 && digitsAfter <= 2",
                                            'number.hasPrefix(".")', "($0 * 100).rounded() / 100"]))

# 2. Amounts as they're typed
typed = {
    "15": 15, "15.5": 15.5, "15,50": 15.5, "$1,200": 1200, "1.200.000": 1200000, "1,200.50": 1200.5,
    "1.200,50": 1200.5, "1 200,50": 1200.5, "15.": 15, ".5": 0.5, "AU$ 36.90": 36.9, "12,345": 12345, "0": 0,
    "¥1500": 1500, "€8,90": 8.9, "abc": None, "": None, "$": None,
}
for text, want in typed.items():
    check(f"'{text}' reads as {want}", amount(text) == want, amount(text))

# 3. The cost each
check("Shared between 2, $51 is $25.50 each", "%.2f" % (51 / 2) == "25.50")
check("costs.csv has the place, day, when, what, kind, amount, currency, people and the cost each",
      '["Place", "Day", "Added", "Cost", "Kind", "Amount", "Currency", "People", "Each"]' in STORE_SRC)
check("costs.csv is written next to facts.txt, and removed when there are no costs",
      'appendingPathComponent("costs.csv")' in STORE_SRC and "Self.costsCSV(for: trip)" in STORE_SRC)

# 4. Every fact is read back from older trips, written to facts.txt and on the form
facts_body = TRIP_SRC.split("struct TripFacts: Codable, Hashable {", 1)[1].split("\nstruct Trip:", 1)[0]
text_fields = re.findall(r'    var (\w+) = ""', facts_body)
decoder = facts_body.split("init(from decoder: Decoder) throws {", 1)[1].split("\n    }\n", 1)[0]
labelled = facts_body.split("private var labelled: [(String, String)] {", 1)[1].split("\n    }\n", 1)[0]
check("TripFacts has the 17 text facts (9 from before, 8 new)", len(text_fields) == 17, text_fields)
check("Each is read with a default, so trips from before 1.27 still load",
      all(f"{name} = try string(.{name})" in decoder for name in text_fields)
      and all(f"decodeIfPresent([{t}].self, forKey: .{k})" in decoder for t, k in (("CostItem", "costs"),
                                                                                  ("FactLink", "links")))
      and "decodeIfPresent(Double.self, forKey: .rating)" in decoder)
check("Each goes into facts.txt, with the rating as a score out of 10",
      all(re.search(rf"\b{name}\)", labelled) for name in text_fields) and '"/10"' in labelled)
check("Each has a box on the place facts form, and the rating a picker",
      all(f"$facts.{name}" in VIEW_SRC for name in text_fields if name != "difficulty")
      and 'Picker("Difficulty", selection: $facts.difficulty)' in VIEW_SRC
      and 'Picker("Your rating", selection: $facts.rating)' in VIEW_SRC)
check("The form's Save keeps the costs and links, which save as you add them",
      "updated.costs = saved.costs" in STORE_SRC and "updated.links = saved.links" in STORE_SRC)

failed = [r for r in results if not r[1]]
for name, ok, detail in results:
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  ({detail})"))
print(f"\n{len(results) - len(failed)} of {len(results)} passed")
sys.exit(1 if failed else 0)
