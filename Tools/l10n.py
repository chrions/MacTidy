#!/usr/bin/env python3
"""Finds the user-facing strings in Sources and writes Resources/<lang>.lproj/Localizable.strings.

    Tools/l10n.py            check that every string has a translation in every language
    Tools/l10n.py --write    also regenerate the .strings files from Tools/translations/<lang>.json

English is the source language: the text in the code is the key, so English needs no table
(only Localizable.stringsdict, for plurals). Interpolations become %lld for integers and %@
for everything else; translations may reorder them with %1$@, %2$lld and so on.
"""
import json, os, plistlib, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["zh-Hans", "ja", "ko"]

# Interpolated expressions that are integers; everything else is formatted as %@.
INT_HINTS = re.compile(r"(\.count\b|Count$|\.days$|staleDays$|\.index$|withheld$|^pending$|^batches$|^unused$|^n$|^n \+ 1$|^status$)")

SPEC = re.compile(r"%(?:\d+\$)?(lld|@)")

# SwiftUI initialisers and modifiers whose string-literal argument is a LocalizedStringKey.
SWIFTUI = re.compile(r'(?:\bText|\bButton|\bLabel|\bToggle|\bPicker|\bTextField|\bSecureField|Section|ContentUnavailableView|\.alert|\.help)\(\s*"')


def literal_at(src, i):
    """Parses the Swift string literal starting at src[i] == '"'; returns (segments, end)."""
    if src.startswith('"""', i):
        end = src.index('"""', i + 3)
        body = src[i + 3:end]
        lines = body.split("\n")[1:-1]
        indent = min((len(l) - len(l.lstrip()) for l in lines if l.strip()), default=0)
        text = "\n".join(l[indent:] for l in lines)
        return parse_segments(text), end + 3
    j = i + 1
    depth = 0
    while True:
        c = src[j]
        if c == "\\" and src[j + 1] == "(":
            depth_j = j + 2
            d = 1
            while d:
                if src[depth_j] == "(":
                    d += 1
                elif src[depth_j] == ")":
                    d -= 1
                elif src[depth_j] == '"':
                    _, depth_j = literal_at(src, depth_j)
                    continue
                depth_j += 1
            j = depth_j
            continue
        if c == "\\":
            j += 2
            continue
        if c == '"':
            break
        j += 1
    return parse_segments(src[i + 1:j]), j + 1


def parse_segments(text):
    """Turns literal text into a key: escapes resolved, interpolations replaced by format specifiers."""
    out = []
    j = 0
    while j < len(text):
        c = text[j]
        if c == "\\" and text[j + 1] == "(":
            k = j + 2
            d = 1
            while d:
                if text[k] == "(":
                    d += 1
                elif text[k] == ")":
                    d -= 1
                k += 1
            expr = text[j + 2:k - 1]
            out.append("%lld" if INT_HINTS.search(expr) and "Fmt." not in expr else "%@")
            j = k
            continue
        if c == "\\":
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}[text[j + 1]])
            j += 2
            continue
        out.append(c)
        j += 1
    return "".join(out)


def keys():
    found = {}
    for folder in ["Sources/Core", "Sources/App"]:
        for name in sorted(os.listdir(os.path.join(ROOT, folder))):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(ROOT, folder, name)
            src = open(path, encoding="utf-8").read()
            starts = [m.end() - 1 for m in re.finditer(r'\bL\(\s*"', src)]
            if folder.endswith("App"):
                starts += [m.end() - 1 for m in SWIFTUI.finditer(src)]
            for i in starts:
                key, _ = literal_at(src, i)
                if SPEC.sub("", key).strip():
                    line = src.count("\n", 0, i) + 1
                    found.setdefault(key, f"{folder}/{name}:{line}")
    return found


def specs(s):
    return sorted(SPEC.findall(s))


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


NOUNS = {
    "apps": "app", "batches": "batch", "days": "day", "groups": "group",
    "items": "item", "packages": "package", "places": "place",
    "programs": "never-used program", "requests": "request",
    "shelves": "shelf", "times": "time",
}


def english_plurals(found):
    """English has no strings table; only plural forms, via a stringsdict."""
    path = os.path.join(ROOT, "Tools", "translations", "en-plurals.json")
    table = json.load(open(path, encoding="utf-8"))
    ok = True
    entries = {}
    for key, fmt in table.items():
        names = re.findall(r"#@(\w+)@", fmt)
        if key not in found:
            print(f"en: unused plural  {json.dumps(key)}", file=sys.stderr)
            ok = False
        if any(n not in NOUNS for n in names):
            print(f"en: unknown noun in  {json.dumps(key)}", file=sys.stderr)
            ok = False
            continue
        entry = {"NSStringLocalizedFormatKey": fmt}
        for n in names:
            entry[n] = {
                "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                "NSStringFormatValueTypeKey": "lld",
                "one": "%lld " + NOUNS[n],
                "other": "%lld " + n.replace("programs", "never-used programs"),
            }
        entries[key] = entry
    if "--write" in sys.argv:
        out = os.path.join(ROOT, "Resources", "en.lproj", "Localizable.stringsdict")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "wb") as f:
            plistlib.dump(entries, f, sort_keys=True)
    return ok


def main():
    found = keys()
    ok = True
    for lang in LANGS:
        path = os.path.join(ROOT, "Tools", "translations", lang + ".json")
        table = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        missing = [k for k in found if k not in table]
        unused = [k for k in table if k not in found]
        wrong = [k for k in found if k in table and specs(table[k]) != specs(k)]
        for k in missing:
            print(f"{lang}: missing  {json.dumps(k, ensure_ascii=False)}  ({found[k]})", file=sys.stderr)
        for k in wrong:
            print(f"{lang}: placeholders differ  {json.dumps(k, ensure_ascii=False)}", file=sys.stderr)
        for k in unused:
            print(f"{lang}: unused  {json.dumps(k, ensure_ascii=False)}", file=sys.stderr)
        ok = ok and not missing and not wrong
        if "--write" in sys.argv:
            out = os.path.join(ROOT, "Resources", lang + ".lproj", "Localizable.strings")
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "w", encoding="utf-8") as f:
                f.write("/* Generated by Tools/l10n.py from Tools/translations/%s.json. */\n\n" % lang)
                for k in sorted(found):
                    if k in table:
                        f.write(f'"{escape(k)}" = "{escape(table[k])}";\n')
    ok = english_plurals(found) and ok
    if "--keys" in sys.argv:
        json.dump(sorted(found), sys.stdout, ensure_ascii=False, indent=1)
    print(f"{len(found)} strings", "OK" if ok else "with problems", file=sys.stderr)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
