"""
seb/adapters/rpg_ingest.py
Cherry-picked from RBG-ibm-meta-corpus/ingest/rpg_matrix.py
Extended: maps RPG data-flow IR to SEB event schema.

Pipeline:
  fixed-format RPG source (80-col)
    → parse rows (F/I/C/O spec columns)
    → extract reads/writes/opcodes
    → build data flow graph
    → map operations to SEB event types
    → emit SEB event schema JSON

SEB event type mapping (from seb_types.ads EventTypeRegistry):
  WRITE  → target is an audit/ledger file  → FISCAL_SETTLE  0x0100
  WRITE  → target is any other output file → INFRA_PROVISION 0x0001
  CHAIN  → DB2 lookup (read by key)        → ARCH_DECISION  0x0010  (query)
  EXSR   → subroutine call                 → CONFIG_DEPLOY  0x0002
  SETON  LR                               → end-of-job      → SOVEREIGN_ROOT 0xFFFF (if LR)

Usage:
  python rpg_ingest.py <path-to-fixed-rpg>        # parse + emit SEB schema
  python rpg_ingest.py <path> --seb-events        # show SEB event list only
  python rpg_ingest.py <path> --adapter-stub      # emit RPGLE adapter stub

Dependencies: stdlib only (no pip installs)
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

# ── Config (inlined from config/column_map.json) ─────────────────────────────
COLUMN_MAP: dict = {
    "format": "fixed-rpg-80",
    "base_columns": {
        "sequence":     {"start": 1,  "end": 5},
        "spec":         {"start": 6,  "end": 6},
        "comment_tail": {"start": 54, "end": 80},
    },
    "layouts": {
        "token_window": {"start": 7, "end": 60}
    },
    "spec_types": {
        "H": "header", "F": "file",   "E": "extension",
        "L": "line_counter", "I": "input", "C": "calculation",
        "O": "output", "*": "comment",
    },
    "opcode_classes": {
        "ADD": "arithmetic",  "SUB": "arithmetic",  "MULT": "arithmetic",
        "DIV": "arithmetic",  "Z-ADD": "arithmetic", "MOVE": "move",
        "MOVEL": "move",      "CHAIN": "io",         "READ": "io",
        "WRITE": "io",        "READE": "io",         "READP": "io",
        "IFEQ": "condition",  "IFNE": "condition",   "IFLT": "condition",
        "IFGT": "condition",  "IFLE": "condition",   "IFGE": "condition",
        "ELSE": "condition",  "END": "condition",    "BEGSR": "subroutine",
        "ENDSR": "subroutine","EXSR": "subroutine",  "PLIST": "parameter",
        "PARM": "parameter",  "SETON": "indicator",  "SETOF": "indicator",
        "CALL": "call",       "RETURN": "call",
    }
}

# ── SEB event type codes ──────────────────────────────────────────────────────
SEB_INFRA_PROVISION  = 0x0001   # execute capability
SEB_CONFIG_DEPLOY    = 0x0002   # write capability
SEB_ARCH_DECISION    = 0x0010   # verify capability (DB2 query / CHAIN)
SEB_FISCAL_SETTLE    = 0x0100   # execute + weight=MAX (ledger write)
SEB_SOVEREIGN_ROOT   = 0xFFFF   # vacuum_collapse (LR seton = end job)

# Heuristics: file name patterns that indicate fiscal/ledger targets
FISCAL_PATTERNS = re.compile(
    r'(LEDGER|AUDIT|SETTLE|FISCAL|GL_|PAY|JOURNAL|JRN|LEDGE|VAULT)',
    re.IGNORECASE
)

TOKEN_RE = re.compile(r"\S+")


# ── Parser (from rpg_matrix.py, unchanged) ────────────────────────────────────

def pad_line(line: str, width: int = 80) -> str:
    return line.rstrip("\n").rstrip("\r")[:width].ljust(width)

def slice_1(text: str, start: int, end: int) -> str:
    return text[start - 1 : end]

def normalize(s: str) -> str | None:
    v = " ".join(s.strip().split())
    return v or None

def classify_opcode(op: str) -> str:
    return COLUMN_MAP["opcode_classes"].get(op.strip().upper(), "unknown")

def extract_tokens(line: str, start: int = 7, end: int = 53) -> list[str]:
    return TOKEN_RE.findall(slice_1(line, start, end))

def find_opcode_idx(tokens: list[str]) -> int | None:
    for i, t in enumerate(tokens):
        if t.strip().upper() in COLUMN_MAP["opcode_classes"]:
            return i
    return None

def base_row(line: str, lineno: int) -> tuple[dict, str]:
    cols = COLUMN_MAP["base_columns"]
    spec = slice_1(line, cols["spec"]["start"], cols["spec"]["end"]).strip().upper()
    if not spec and slice_1(line, 7, 7) == "*":
        spec = "*"
    row = {
        "line_number": lineno,
        "raw": line,
        "spec_code": spec,
        "spec_kind": COLUMN_MAP["spec_types"].get(spec, "unknown"),
        "fields": {"sequence": slice_1(line, 1, 5).rstrip(),
                   "comment": slice_1(line, cols["comment_tail"]["start"],
                                      cols["comment_tail"]["end"]).rstrip()},
        "classification": {"domain": COLUMN_MAP["spec_types"].get(spec, "unknown"),
                           "is_comment": spec == "*",
                           "is_blank": not line.strip()},
        "reads": [], "writes": [], "warnings": [],
    }
    return row, spec

def decode_file_row(line: str, row: dict) -> dict:
    toks = extract_tokens(line)
    name = toks[0] if toks else ""
    row["fields"].update({"file_name": name, "access": toks[1] if len(toks) > 1 else "",
                          "keywords": toks[2:]})
    if name: row["writes"].append(name)
    else: row["warnings"].append("file row missing file_name")
    return row

def decode_input_row(line: str, row: dict) -> dict:
    toks = extract_tokens(line)
    if not toks:
        row["warnings"].append("input row has no tokens"); return row
    if toks[0].isdigit():
        row["classification"]["domain"] = "input_field"
        fn = toks[2] if len(toks) > 2 else ""
        row["fields"].update({"input_shape": "field", "field_from": toks[0],
                              "field_to": toks[1] if len(toks) > 1 else "",
                              "field_name": fn})
        if fn: row["writes"].append(fn)
    else:
        row["classification"]["domain"] = "input_record"
        row["fields"].update({"input_shape": "record", "record_name": toks[0]})
        row["reads"].append(toks[0])
    return row

def decode_calculation_row(line: str, row: dict) -> dict:
    toks = extract_tokens(line)
    idx = find_opcode_idx(toks)
    comment = slice_1(line, 54, 80).rstrip()
    if idx is None:
        row["fields"].update({"factor1": "", "opcode": "", "factor2": "",
                              "result": "", "comment": comment, "tokens": toks})
        row["classification"]["domain"] = "unknown"
        row["warnings"].append("calculation row missing recognized opcode")
        return row
    op = toks[idx].strip().upper()
    before = toks[:idx]; after = toks[idx + 1:]
    f1 = before[-1] if before else ""
    f2 = after[0] if after else ""
    result = after[1] if len(after) > 1 else ""
    if op in {"WRITE", "SETON", "SETOF", "END", "ELSE", "BEGSR", "ENDSR", "EXSR"}:
        result = ""
    row["fields"].update({"factor1": f1, "opcode": op, "factor2": f2,
                          "result": result, "comment": comment, "tokens": toks})
    row["classification"]["domain"] = classify_opcode(op)
    reads, writes = [], []
    if f1 := normalize(f1): reads.append(f1)
    if f2v := normalize(f2):
        if op not in {"WRITE", "SETON"}: reads.append(f2v)
    if rv := normalize(result):
        if op in {"Z-ADD","ADD","SUB","MULT","DIV","MOVEL","MOVE","PARM"}: writes.append(rv)
    if op == "CHAIN" and f2v: reads.append(f2v)
    if op == "WRITE" and f2v: writes.append(f2v)
    if op == "SETON" and f2v: writes.append(f2v)
    if op in {"BEGSR","EXSR","ENDSR"} and f1: writes.append(f1)
    row["reads"] = list(dict.fromkeys(reads))
    row["writes"] = list(dict.fromkeys(writes))
    return row

def decode_output_row(line: str, row: dict) -> dict:
    toks = extract_tokens(line)
    rec = toks[0] if toks else ""
    row["classification"]["domain"] = "output"
    row["fields"].update({"output_record": rec,
                          "operation": toks[1] if len(toks) > 1 else "",
                          "operands": toks[2:]})
    if rec: row["writes"].append(rec)
    else: row["warnings"].append("output row missing output_record")
    return row

def decode_row(line: str, lineno: int) -> dict:
    row, spec = base_row(line, lineno)
    if row["classification"]["is_blank"] or row["classification"]["is_comment"]:
        return row
    if spec == "F": return decode_file_row(line, row)
    if spec == "I": return decode_input_row(line, row)
    if spec == "C": return decode_calculation_row(line, row)
    if spec == "O": return decode_output_row(line, row)
    return row

def build_matrix(lines: list[str]) -> list[list[int]]:
    return [[ord(ch) for ch in line] for line in lines]

def build_flow(rows: list[dict]) -> dict:
    nodes, edges = [], []
    for row in rows:
        nid = f"line_{row['line_number']}"
        nodes.append({"id": nid, "line_number": row["line_number"],
                      "spec_kind": row["spec_kind"],
                      "opcode": row["fields"].get("opcode", "").strip(),
                      "domain": row["classification"]["domain"],
                      "warnings": row["warnings"]})
        for s in row["reads"]:  edges.append({"type": "reads",  "symbol": s, "target": nid})
        for s in row["writes"]: edges.append({"type": "writes", "symbol": s, "source": nid})
    return {"nodes": nodes, "edges": edges}

def build_summary(rows: list[dict]) -> dict:
    return {"spec_counts": dict(Counter(r["spec_kind"] for r in rows)),
            "domain_counts": dict(Counter(r["classification"]["domain"] for r in rows)),
            "warnings": [{"line_number": r["line_number"], "warnings": r["warnings"]}
                         for r in rows if r["warnings"]]}


# ── SEB event mapping (new — not in original rpg_matrix.py) ──────────────────

def row_to_seb_event(row: dict) -> dict | None:
    """Map a single RPG calculation row to a SEB event descriptor."""
    op = row["fields"].get("opcode", "").strip().upper()
    if not op:
        return None

    writes = row.get("writes", [])
    reads  = row.get("reads",  [])
    lineno = row["line_number"]

    # WRITE to fiscal/ledger target → FISCAL_SETTLE
    if op == "WRITE":
        for w in writes:
            if FISCAL_PATTERNS.search(w):
                return {"line": lineno, "opcode": op, "target": w,
                        "seb_event_type": SEB_FISCAL_SETTLE,
                        "seb_event_name": "FISCAL_SETTLE",
                        "required_capability": "execute",
                        "weight": 0xFFFFFFFF,
                        "human_review_required": True}
        for w in writes:
            return {"line": lineno, "opcode": op, "target": w,
                    "seb_event_type": SEB_INFRA_PROVISION,
                    "seb_event_name": "INFRA_PROVISION",
                    "required_capability": "execute",
                    "weight": 1000,
                    "human_review_required": False}

    # CHAIN → DB2 read-by-key → ARCH_DECISION (query event)
    if op == "CHAIN":
        target = reads[-1] if reads else "unknown"
        return {"line": lineno, "opcode": op, "target": target,
                "seb_event_type": SEB_ARCH_DECISION,
                "seb_event_name": "ARCH_DECISION",
                "required_capability": "verify",
                "weight": 100,
                "human_review_required": False}

    # EXSR → subroutine call → CONFIG_DEPLOY
    if op == "EXSR":
        sub = reads[0] if reads else writes[0] if writes else "unknown"
        return {"line": lineno, "opcode": op, "target": sub,
                "seb_event_type": SEB_CONFIG_DEPLOY,
                "seb_event_name": "CONFIG_DEPLOY",
                "required_capability": "write",
                "weight": 500,
                "human_review_required": False}

    # SETON LR → end-of-job → SOVEREIGN_ROOT
    if op == "SETON":
        factor2 = row["fields"].get("factor2", "").strip().upper()
        if "LR" in factor2 or "LR" in writes:
            return {"line": lineno, "opcode": op, "target": "LR",
                    "seb_event_type": SEB_SOVEREIGN_ROOT,
                    "seb_event_name": "SOVEREIGN_ROOT",
                    "required_capability": "vacuum_collapse",
                    "weight": 0xFFFFFFFF,
                    "human_review_required": True}
    return None


def extract_seb_events(rows: list[dict]) -> list[dict]:
    events = []
    for row in rows:
        if row["spec_code"] == "C":
            evt = row_to_seb_event(row)
            if evt:
                events.append(evt)
    return events


def emit_adapter_stub(source_name: str, events: list[dict]) -> str:
    """Emit an RPGLE adapter stub that emits the detected SEB events."""
    lines = [
        f"** SEB adapter stub generated from {source_name}",
        f"** Cherry-picked rpg_ingest.py from RBG-ibm-meta-corpus",
        f"** DO NOT EDIT — regenerate with: python rpg_ingest.py {source_name} --adapter-stub",
        "**FREE",
        "ctl-opt dftactgrp(*no) actgrp(*new) bnddir('SEB_BND');",
        "",
        "// SEB kernel entry points",
        "dcl-pr SEB_Append_Event extproc(*dclcase);",
        "  Hdr pointer value options(*nopass);",
        "  Pay pointer value options(*nopass);",
        "  Ftr pointer value options(*nopass);",
        "end-pr;",
        "",
        "dcl-pr SEB_Worm_Flush extproc(*dclcase);",
        "end-pr;",
        "",
    ]

    for evt in events:
        ename = evt["seb_event_name"]
        etype = evt["seb_event_type"]
        cap   = evt["required_capability"]
        hr    = evt["human_review_required"]
        target = evt["target"]
        lines += [
            f"// Line {evt['line']}: {evt['opcode']} {target}",
            f"// SEB event: {ename} (0x{etype:04X}) cap={cap} human_review={hr}",
            f"dcl-proc Emit_{ename}_{evt['line']} export;",
            f"  // TODO: build 68-byte Event_Header with Event_Type = 0x{etype:04X}",
            f"  // TODO: build payload from {target} record",
            f"  // TODO: call SEB_Append_Event(hdr_ptr : pay_ptr : ftr_ptr);",
            f"  // TODO: if human_review_required call SEB_Human_Review_Queue;",
            f"end-proc;",
            "",
        ]

    lines += ["// Flush WORM chain after all events emitted",
              "SEB_Worm_Flush();", "*inlr = *on;"]
    return "\n".join(lines)


# ── Main ──────────────────────────────────────────────────────────────────────

def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: python rpg_ingest.py <path-to-fixed-rpg> [--seb-events] [--adapter-stub]")
        return 1

    source_path = Path(argv[1]).resolve()
    if not source_path.exists():
        print(f"error: not found: {source_path}"); return 1

    mode_events  = "--seb-events"  in argv
    mode_adapter = "--adapter-stub" in argv

    lines = [pad_line(l) for l in source_path.read_text(encoding="utf-8").splitlines()]
    rows  = [decode_row(l, i + 1) for i, l in enumerate(lines)]
    flow  = build_flow(rows)
    summary = build_summary(rows)
    events  = extract_seb_events(rows)

    if mode_adapter:
        print(emit_adapter_stub(source_path.name, events))
        return 0

    if mode_events:
        print(json.dumps(events, indent=2))
        return 0

    # Default: full IR output
    out = {
        "source": str(source_path),
        "shape": [len(rows), 80],
        "summary": summary,
        "seb_events": events,
        "flow": flow,
        "rows": rows,
        "matrix": build_matrix(lines),
    }
    print(json.dumps(out, indent=2))

    # Summary to stderr
    import sys as _sys
    print(f"\nsource:     {source_path}", file=_sys.stderr)
    print(f"specs:      {summary['spec_counts']}", file=_sys.stderr)
    print(f"seb_events: {len(events)}", file=_sys.stderr)
    for e in events:
        print(f"  line {e['line']:4d} {e['opcode']:8s} → {e['seb_event_name']} (0x{e['seb_event_type']:04X})",
              file=_sys.stderr)
    print(f"warnings:   {len(summary['warnings'])}", file=_sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
