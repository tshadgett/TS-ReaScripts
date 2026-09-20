#!/usr/bin/env python3
# @noindex  (a development tool, not a package: never installed)
"""
TS_CV_Audit.py -- check every ImGui.* call site in this folder against the
signatures of the ReaImGui build actually installed.

Lua won't tell you that ImGui.EndChild() is missing its `ctx` until the
frame runs and the script dies mid-draw, which in a defer loop means the
window just vanishes with the reason buried in the console. This reads
REAPER's own ReaImGui reference (Data/reaper_imgui_doc.html) and checks:

  * too few / too many arguments
  * a first argument that isn't what the signature's first parameter is
    called -- `ctx` on most calls, `draw_list` on the DrawList_* family
  * ImGui.Something that doesn't exist in this build at all
  * an End*() that looks unguarded (see below)
  * a call to a `local function`, or a use of a file-scope `local`, above
    the line that declares it

WHY THE HTML DOC AND NOT imgui.py: the generated Python binding drops
pure-output parameters from its argument list, while the Lua API keeps
them as positional slots you pass nil into. GetMouseDragDelta is the trap
-- Python has (ctx, button, lock_threshold), Lua has
(ctx, nil, nil, button, lock_threshold), so `GetMouseDragDelta(ctx,
MouseButton_Right)` reads as an x placeholder and silently watches the
wrong button. Only the doc carries the real Lua argument list.

ReaImGui also keeps Dear ImGui's PRE-1.90 convention: End() and EndChild()
are called ONLY when the matching Begin()/BeginChild() returned true.
Upstream reversed this, so most examples online are wrong here, and
getting it backwards trips an assertion that kills the defer loop. The
guard check bracket-matches each End to its real partner, and understands
the early-return form (`if not ImGui.BeginPopup(...) then return end`).

Run it from anywhere:   python dev/TS_CV_Audit.py
"""

import glob
import html as html_mod
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# This file lives in dev/; the modules it audits are one level up.
PROJECT = os.path.normpath(os.path.join(HERE, ".."))
# dev -> TS_ChannelView -> Scripts -> REAPER resource root -> Data
DOC = os.path.normpath(os.path.join(HERE, "..", "..", "..", "Data",
                                    "reaper_imgui_doc.html"))

DETAILS_RE = re.compile(r'<details id="([A-Za-z0-9_]+)">(.*?)</details>', re.S)
LUA_ROW_RE = re.compile(r"<th>Lua</th><td><code>(.*?)</code>", re.S)
TAG_RE = re.compile(r"<[^>]+>")
LOCALFN_RE  = re.compile(r"^\s*local function (\w+)\s*\(")
# a file-scope local: no leading indent, so it isn't inside a block
LOCALVAR_RE = re.compile(r"^local\s+([A-Za-z_]\w*)\s*(?:,\s*[A-Za-z_]\w*\s*)*=")
END_RE = re.compile(r"\bImGui\.(End\w*)\(")

PAIRS = {
    "End":               ["Begin"],
    "EndChild":          ["BeginChild"],
    "EndListBox":        ["BeginListBox"],
    "EndMenu":           ["BeginMenu"],
    "EndMenuBar":        ["BeginMenuBar"],
    "EndPopup":          ["BeginPopup", "BeginPopupModal",
                          "BeginPopupContextItem", "BeginPopupContextWindow",
                          "BeginPopupContextVoid"],
    "EndTable":          ["BeginTable"],
    "EndTabBar":         ["BeginTabBar"],
    "EndTabItem":        ["BeginTabItem"],
    "EndCombo":          ["BeginCombo"],
    "EndTooltip":        ["BeginTooltip"],
    "EndDragDropSource": ["BeginDragDropSource"],
    "EndDragDropTarget": ["BeginDragDropTarget"],
}


def untag(s):
    return html_mod.unescape(TAG_RE.sub("", s)).replace(" ", " ").strip()


def split_args(s):
    """Top-level comma split, respecting brackets, quotes and Lua's [[ ]]."""
    out, depth, cur, quote, i = [], 0, "", None, 0
    while i < len(s):
        c = s[i]
        if quote:
            if c == "\\":
                cur += c + s[i + 1:i + 2]
                i += 2
                continue
            if c == quote:
                quote = None
            cur += c
        elif c in "\"'":
            quote = c
            cur += c
        elif c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        out.append(cur.strip())
    return out


def load_signatures(path):
    """{name: (required, total, first_param_name, params)} from the Lua rows.

    A parameter is optional when it carries a default (`= something`) or is
    a bare `nil` placeholder standing in for an output. Required count is
    how many leading parameters are neither.
    """
    sigs, consts = {}, set()
    with open(path, encoding="utf-8", errors="replace") as fh:
        doc = fh.read()

    for name, body in DETAILS_RE.findall(doc):
        row = LUA_ROW_RE.search(body)
        if not row:
            continue
        text = untag(row.group(1))
        call = re.search(r"ImGui\.%s\s*\((.*)\)\s*$" % re.escape(name), text, re.S)
        if not call:
            consts.add(name)          # a value, e.g. ImGui.MouseButton_Left
            continue
        params = split_args(call.group(1))
        params = [p for p in params if p]
        required, counting = 0, True
        for p in params:
            if "=" in p or p.strip() == "nil":
                counting = False
            elif counting:
                required += 1
        first = ""
        if params:
            first = params[0].split("=")[0].strip().split()[-1]
        # Everything left of the `=` is what Lua gets back, e.g.
        # "number w, number h = ImGui.CalcTextSize(...)".
        head = text[:call.start()]
        nret = len(split_args(head.rstrip().rstrip("="))) if "=" in head else 0
        # The documented return list UNDERSTATES what Lua actually gets:
        # REAPER hands optional parameters back as further return values,
        # nil for the ones you didn't pass. CalcTextSize is documented as
        # "number w, number h" and returns four. Those trailing nils are
        # invisible until a call splats them into something that compares.
        nret += sum(1 for p in params if "=" in p)
        sigs[name] = (required, len(params), first, params, nret)
    return sigs, consts


def is_ctx_expr(arg):
    """Does this argument expression look like a context?"""
    a = arg.strip()
    return a == "ctx" or a.endswith(".ctx") or a.endswith("_ctx")


def close_paren(src, start):
    i, depth, quote = start, 1, None
    while i < len(src) and depth:
        c = src[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        i += 1
    return i


def blank_strings(line):
    """Blank the contents of quoted strings, keeping the line's length.

    A name-matching check has no business reading string literals: a test
    label like "steps up" is not a use of a local called `steps`.
    """
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c in "\"'":
            quote = c
            out.append(c)
            i += 1
            while i < n:
                if line[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                    continue
                if line[i] == quote:
                    out.append(quote)
                    i += 1
                    break
                out.append(" ")
                i += 1
            continue
        if line.startswith("[[", i):
            j = line.find("]]", i + 2)
            end = (j + 2) if j >= 0 else n
            out.append(" " * (end - i))
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)


def strip_comments(lines):
    """A parallel copy with comments and string contents blanked out,
    indentation preserved.

    Handles Lua's long comments (--[[ ... ]], --[==[ ... ]==]) as well as
    line comments. Without this, prose in a file header trips every
    name-matching check -- "Resolution order" reads as a use of `order`.
    """
    out, close = [], None
    for line in lines:
        if close is not None:                 # inside a long comment
            i = line.find(close)
            if i < 0:
                out.append(" " * len(line))
                continue
            line = " " * (i + len(close)) + line[i + len(close):]
            close = None
        m = re.search(r"--(\[=*\[)?", line)
        if m:
            if m.group(1):                    # a long comment opens here
                close = "]" + "=" * (len(m.group(1)) - 2) + "]"
                j = line.find(close, m.end())
                if j >= 0:
                    line = line[:m.start()] + " " * (j + len(close) - m.start()) \
                           + line[j + len(close):]
                    close = None
                else:
                    line = line[:m.start()]
            else:
                line = line[:m.start()]
        out.append(blank_strings(line))
    return out


def indent_of(line):
    return len(line) - len(line.lstrip())


# REAPER answers nil -- not 0 -- when a track or send does not HAVE the
# thing you asked about: record arm, input monitoring and phase invert on
# the master track, most obviously. `nil > 0.5` is a hard error rather
# than a false, so one unguarded read takes the whole window down the
# moment the master is selected, and only then.
INFO_VALUE_RE = re.compile(
    r"reaper\.Get\w*Info_Value\s*\([^()]*\)\s*(?:[<>]=?|~=|==|[-+*/%])")


def check_info_value(fname, lines, problems):
    """A *Info_Value result compared, or used in arithmetic, with no fallback."""
    for i, line in enumerate(lines):
        m = INFO_VALUE_RE.search(line)
        if not m:
            continue
        # `(reaper.GetMediaTrackInfo_Value(tr, "I_FXEN") or 1) < 0.5` is the
        # correct shape, and puts the `or` before the operator.
        if re.search(r"\bor\b", line[:m.end()]):
            continue
        problems.append((
            "UNGUARDED nil?", fname, i + 1, "Info_Value",
            "REAPER returns nil when a track lacks this -- add `or <default>`",
            line.strip()))


# Our OWN modules call each other by field name with positional
# arguments, and Lua pads a short call with nils rather than complaining.
# One argument too few therefore shows up much later, as a nil in a
# comparison inside the callee -- which names the callee, not the caller
# that shorted it. So every cross-module call is counted against the
# declared parameter list.
def module_signatures(sources):
    """{(module, function): ([param names], required count)}.

    A trailing parameter counts as OPTIONAL when the module treats it as
    one -- `opts = opts or {}`, `if not dflt then`, `param == nil`. Only
    a trailing run of those may be omitted, which is what lets
    `CH.read(tr, key)` pass against `CH.read(track, key, dflt)` while a
    genuinely short call is still caught.
    """
    sigs = {}
    for fname, src in sources.items():
        if not fname.startswith("TS_CV_"):
            continue
        mod = fname[:-4]
        for d in re.finditer(r"^function\s+\w+\.(\w+)\s*\(([^)]*)\)", src, re.M):
            params = [p.strip() for p in d.group(2).split(",") if p.strip()]
            # Only THIS function's body decides which of its own arguments
            # are optional -- a module-wide search would call `peak_db`
            # optional here because some other function defaults it.
            close = re.compile(r"^end$", re.M).search(src, d.end())
            body = src[d.end():close.start() if close else len(src)]
            required = len(params)
            while required > 0:
                p = re.escape(params[required - 1])
                if not re.search(r"\b%s\s+or\b|\bnot\s+%s\b|\b%s\s*==\s*nil\b"
                                 r"|\bif\s+%s\s+(?:then|and)\b" % (p, p, p, p), body):
                    break
                required -= 1
            sigs[(mod, d.group(1))] = (params, required)
    return sigs


def check_call_arity(fname, src, raw, sigs, problems):
    # The require lines have to come from the RAW text: strip_comments
    # blanks string CONTENTS, so require("TS_CV_Widgets") reads as
    # require("          ") and every binding goes missing -- which makes
    # this whole check silently pass everything.
    bind = {}
    for m in re.finditer(r"local\s+(\w+)\s*=\s*require\s*\(?\s*[\"\'](TS_CV_\w+)", raw):
        bind[m.group(1)] = m.group(2)
    own = re.search(r"^local\s+(\w+)\s*=\s*\{\}", src, re.M)
    if own and fname.startswith("TS_CV_"):
        bind[own.group(1)] = fname[:-4]

    for m in re.finditer(r"(?<![\w.])(\w+)\.(\w+)\s*\(", src):
        entry = sigs.get((bind.get(m.group(1)), m.group(2)))
        if entry is None:
            continue
        params, required = entry
        i, depth = m.end(), 1
        while i < len(src) and depth:
            if src[i] in "([{":
                depth += 1
            elif src[i] in ")]}":
                depth -= 1
            i += 1
        n = len(split_args(src[m.end():i - 1]))
        if n > len(params) or n < required:
            problems.append((
                "ARG COUNT", fname, src[:m.start()].count("\n") + 1,
                "%s.%s" % (m.group(1), m.group(2)),
                "%d passed; takes %d (%s), %d required"
                % (n, len(params), ", ".join(params) or "none", required),
                ""))


# ReaImGui echoes a function's OPTIONAL parameters back as extra return
# values, so ImGui.CalcTextSize(ctx, text) returns w, h, nil, nil -- the
# two it wasn't given. Lua adjusts a call to one value almost everywhere,
# but NOT in the last argument position, where the whole list is passed
# on. `math.max(gut, ImGui.CalcTextSize(ctx, s))` therefore compares
# against nil and raises, from inside math.max, naming nothing useful.
# Binding the result to a name first is the fix.
SPLAT_RE = re.compile(r"^ImGui\.(\w+)\s*\(")


def check_multivalue_splat(fname, src, sigs, problems):
    for m in re.finditer(r"(?<![\w.:])([\w.]+)\s*\(", src):
        # select() is how you deliberately pick one of several returns,
        # and ImGui's own arity is checked separately.
        if m.group(1) == "select" or m.group(1).startswith("ImGui."):
            continue
        end = close_paren(src, m.end())
        if end <= m.end():
            continue
        args = split_args(src[m.end():end - 1])
        if not args:
            continue
        last = args[-1].strip()
        hit = SPLAT_RE.match(last)
        # Only a BARE call splats. `ImGui.X(...) < 3` is an expression and
        # Lua adjusts it to one value like anywhere else.
        if not hit or close_paren(last, hit.end()) != len(last):
            continue
        entry = sigs.get(hit.group(1))
        if not entry or entry[4] < 2:
            continue
        problems.append((
            "SPLATS", fname, src[:m.start()].count("\n") + 1, m.group(1),
            "last argument ImGui.%s returns %d values, and the last "
            "argument position passes all of them on -- bind it to a name "
            "first" % (hit.group(1), entry[4]), ""))


def check_guards(fname, lines, problems):
    """Is each End guarded by the `if` its Begin opened?

    Menus and popups nest, so "the nearest Begin above" is often the wrong
    partner -- hence bracket matching. And the idiomatic whole-function
    guard is an early return, which is exempt:

        if not ImGui.BeginPopup(ctx, 'x') then return end
        ...
        ImGui.EndPopup(ctx)          -- same indent, and correct
    """
    for i, line in enumerate(lines):
        m = END_RE.search(line)
        if not m or m.group(1) not in PAIRS:
            continue
        opens = PAIRS[m.group(1)]
        open_re = re.compile(r"\bImGui\.(?:%s)\(" % "|".join(opens))
        close_re = re.compile(r"\bImGui\.%s\(" % m.group(1))

        depth, partner = 1, None
        for j in range(i - 1, -1, -1):
            if close_re.search(lines[j]):
                depth += 1
            elif open_re.search(lines[j]):
                depth -= 1
                if depth == 0:
                    partner = j
                    break
        if partner is None:
            continue                      # several exit paths; can't tell
        if re.search(r"\bthen\b.*\breturn\b", lines[partner]):
            continue                      # early-return guard
        if indent_of(line) <= indent_of(lines[partner]):
            problems.append((
                "UNGUARDED End?", fname, i + 1, m.group(1),
                "not indented past its %s on line %d" % (opens[0], partner + 1),
                line.strip()))


def check_local_order(fname, lines, problems, raw=None):
    """A file-scope `local` is not in scope inside a function body written
    ABOVE it -- the name resolves as a global there, so a read yields nil
    and a write goes to a global nobody reads. Lua gives no warning and the
    file loads fine, so this only surfaces when that code path runs.

    Covers both `local function f` (called too early) and `local x = ...`
    (referenced too early). Only lines indented further than the
    declaration are flagged: an unindented earlier mention would be at file
    scope, where Lua's own ordering rules already make the problem obvious.
    """
    decls = {}
    for i, line in enumerate(lines):
        for rx in (LOCALFN_RE, LOCALVAR_RE):
            m = rx.match(line)
            if m and m.group(1) not in decls:
                decls[m.group(1)] = i

    for name, decl_line in decls.items():
        if len(name) < 3:
            continue                      # too short to match reliably
        use_re = re.compile(r"(?<![\w.:])%s\b" % re.escape(name))
        for i in range(decl_line):
            line = lines[i]
            stripped = line.lstrip()
            if stripped.startswith("--") or not stripped:
                continue
            if LOCALFN_RE.match(line) or LOCALVAR_RE.match(line):
                continue
            # A use INSIDE a function body is the dangerous one: it runs
            # later, when the name looks global and reads as nil. Indented
            # lines are inside something; an unindented line counts too
            # when it defines a function on that same line, which is how
            # `function M.f() ... end` one-liners slip through.
            indented = (len(line) - len(stripped)) > 0
            one_liner = "function" in stripped
            if not (indented or one_liner):
                continue
            if use_re.search(line):
                problems.append((
                    "USED TOO EARLY", fname, i + 1, name,
                    "local %s is declared on line %d" % (name, decl_line + 1),
                    (raw[i] if raw else line).strip()))
                break                     # one report per declaration


def main():
    if not os.path.exists(DOC):
        print("could not find REAPER's ReaImGui reference at:\n  " + DOC)
        print("(it ships with the extension as Data/reaper_imgui_doc.html)")
        return 2

    sigs, consts = load_signatures(DOC)
    if not sigs:
        print("parsed no signatures out of " + DOC)
        return 2

    problems, checked = [], 0
    sources, raws = {}, {}

    for path in sorted(glob.glob(os.path.join(PROJECT, "*.lua"))):
        name = os.path.basename(path)
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        lines = src.split("\n")

        for m in re.finditer(r"\bImGui\.(\w+)\(", src):
            fn = m.group(1)
            line_no = src[:m.start()].count("\n") + 1
            if fn not in sigs:
                if fn not in consts:
                    problems.append(("UNKNOWN", name, line_no, fn,
                                     "no such function in this build", ""))
                continue
            checked += 1
            args = split_args(src[m.end():close_paren(src, m.end()) - 1])
            required, total, first_param, params, _ = sigs[fn]
            src_line = lines[line_no - 1].strip()
            first = args[0] if args else ""

            if len(args) < required:
                problems.append(("TOO FEW", name, line_no, fn,
                                 "got %d, needs %d" % (len(args), required),
                                 src_line))
            elif len(args) > total:
                problems.append(("TOO MANY", name, line_no, fn,
                                 "got %d, takes %d" % (len(args), total),
                                 src_line))
            else:
                # First argument: only the ctx/draw_list mix-up is worth
                # flagging. Any identifier can legitimately hold either --
                # `dl` is a fine name for a draw list -- so compare kinds,
                # not spellings.
                if first_param == "ctx" and args and not is_ctx_expr(first):
                    problems.append(("WANTS ctx", name, line_no, fn,
                                     "first arg is " + first, src_line))
                elif first_param == "draw_list" and is_ctx_expr(first):
                    problems.append(("WANTS draw_list", name, line_no, fn,
                                     "first arg is the context", src_line))

                # Output parameters occupy real positions in the Lua API
                # and must be passed as nil. Putting a value there silently
                # shifts every later argument -- the GetMouseDragDelta trap
                # described at the top of this file.
                for idx, prm in enumerate(params):
                    if prm.strip() != "nil" or idx >= len(args):
                        continue
                    if args[idx].strip() != "nil":
                        problems.append((
                            "NIL SLOT", name, line_no, fn,
                            "argument %d is an output slot and must be nil "
                            "(passing %s here shifts the rest)"
                            % (idx + 1, args[idx].strip()), src_line))

        for m in re.finditer(r"\bImGui\.(\w+)\b(?!\s*\()", src):
            if m.group(1) not in sigs and m.group(1) not in consts:
                problems.append(("UNKNOWN", name,
                                 src[:m.start()].count("\n") + 1, m.group(1),
                                 "no such name in this build", ""))

        code = strip_comments(lines)
        sources[name] = "\n".join(code)
        raws[name] = src
        check_guards(name, code, problems)
        check_local_order(name, code, problems, lines)
        check_info_value(name, code, problems)
        check_multivalue_splat(name, sources[name], sigs, problems)

    own_sigs = module_signatures(sources)
    for name, src in sorted(sources.items()):
        check_call_arity(name, src, raws[name], own_sigs, problems)

    for kind, fname, line, fn, detail, src_line in problems:
        label = fn if kind in ("CALLED TOO EARLY", "USED TOO EARLY",
                                "UNGUARDED nil?", "ARG COUNT",
                                "SPLATS") else "ImGui." + fn
        print("%-16s %s:%d  %s  %s" % (kind, fname, line, label, detail))
        if src_line:
            print("                 %s" % src_line)

    print("\n%d call sites checked against %d functions in this ReaImGui build"
          % (checked, len(sigs)))
    print("%d problem(s)" % len(problems) if problems else "clean")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
