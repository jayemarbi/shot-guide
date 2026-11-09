"""A model of how Transcriber.Heard puts captions together (1.25), with the cases it has to handle.

Since iOS 17 the speech recogniser hands back what you said up to each pause as a piece of its own, and its last
("final") piece only holds what came after the last pause. Before 1.25 only that last piece was kept, so a 30-second
voiceover came out as its last sentence. Older iOS repeats everything from the start in each piece.

Run: python3 tools/test_captions.py
"""

def add(words, piece):
    """Each piece covers from its first word on and replaces anything heard from then (Heard.add)."""
    if not piece:
        return words
    start = piece[0][1]
    kept = [w for w in words if not (w[1] >= start - 0.05)]
    return sorted(kept + piece, key=lambda w: w[1])


def text(words):
    return " ".join(w[0] for w in words).strip()


def srt_lines(words):
    """At most 5 words or 2.5 seconds a line (Transcriber.srt)."""
    lines, current = [], []

    def flush():
        nonlocal current
        if current:
            lines.append((current[0][1], current[-1][1] + current[-1][2], " ".join(w[0] for w in current)))
            current = []

    for word in words:
        if current and (len(current) >= 5 or word[1] + word[2] - current[0][1] > 2.5):
            flush()
        current.append(word)
    flush()
    return lines


def piece(*words):
    return [(w, t, d) for (w, t, d) in words]


passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {name}\n  got:  {got!r}\n  want: {want!r}")


# iOS 17 and later: a piece per pause, then a final piece with only the last bit.
first = piece(("If", 1.0, 0.2), ("you're", 1.2, 0.3), ("coming", 1.5, 0.4))
second = piece(("Bring", 9.0, 0.3), ("snacks.", 9.3, 0.5))
last = piece(("Very", 26.7, 0.3), ("nice.", 27.0, 0.4))
words = add(add(add([], first), second), last)
check("pieces per pause keep everything", text(words), "If you're coming Bring snacks. Very nice.")
check("captions start at the first word", srt_lines(words)[0][0], 1.0)

# Older iOS: every piece repeats everything from the start, with corrections.
words = add([], piece(("Hello", 0.5, 0.3), ("word", 0.8, 0.3)))
words = add(words, piece(("Hello", 0.5, 0.3), ("world.", 0.8, 0.3), ("Hi.", 2.0, 0.3)))
check("repeated pieces replace, not double up", text(words), "Hello world. Hi.")

# A piece that redoes the end of the one before it.
words = add([], piece(("We", 1.0, 0.2), ("went", 1.2, 0.2), ("their", 1.4, 0.2)))
words = add(words, piece(("there", 1.4, 0.2), ("today.", 1.6, 0.3)))
check("a redone ending replaces the old words", text(words), "We went there today.")

# A piece with nothing in it changes nothing.
check("empty piece", add(words, []), words)

# Caption lines: 5 words, or 2.5 seconds, at most.
long = [(f"w{i}", i * 0.3, 0.25) for i in range(12)]
lines = srt_lines(long)
check("five words a line", [len(l[2].split()) for l in lines], [5, 5, 2])
slow = [(f"w{i}", i * 1.0, 0.5) for i in range(4)]
check("2.5 seconds a line", [len(l[2].split()) for l in srt_lines(slow)], [3, 1])

print(f"{passed} passed, {failed} failed")
raise SystemExit(1 if failed else 0)
