#!/usr/bin/env python3
"""
sovereign-xml-compiler — converts natural language to valid XML prompts.

Three modes:
  1. GBNF constrained decoding (llama.cpp) — zero syntax errors, one shot
  2. Skeleton in-filling — fill {{PLACEHOLDERS}} via LLM, inject into template
  3. Dual-pass chain-of-XML — thought_process first, xml_output second

Usage:
    python compiler.py --mode skeleton --input "You are a Lean 4 proof verifier..."
    python compiler.py --mode gbnf --input "..." --llama-url http://localhost:8080
    python compiler.py --mode dual-pass --input "..."
"""
import argparse
import json
import os
import re
import urllib.request
from pathlib import Path

BASE = Path(__file__).parent.parent
SKELETON = BASE / "skeletons" / "sovereign_prompt.xml"
GRAMMAR = BASE / "grammars" / "sovereign_prompt.gbnf"

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
LLAMA_URL = os.environ.get("LLAMA_URL", "http://localhost:8080")
MODEL = os.environ.get("XML_MODEL", "nemotron")

DUAL_PASS_SYSTEM = """You are a Compiler Agent. Convert natural language into sovereign XML prompts.

Follow this exact output sequence:
1. <thought_process>: outline the identity, logic gates, and execution flow needed.
2. <xml_output>: convert your thought process into the finalized XML.
   Do not output any text after </xml_output>.

The XML must match this structure:
<system_prompt>
  <identity>...</identity>
  <logic_gates><gate><name/><condition/><action/></gate></logic_gates>
  <execution_flow><step><order/><instruction/></step></execution_flow>
</system_prompt>"""

SKELETON_SYSTEM = """You are a Skeleton Filler Agent.
You will receive an XML skeleton with {{PLACEHOLDER}} tokens.
Return ONLY a JSON object mapping each placeholder key to its value.
No XML. No explanation. Pure JSON."""


def call_ollama(system, prompt, temperature=0.3):
    payload = {
        "model": MODEL,
        "system": system,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": temperature, "top_p": 0.9}
    }
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/generate",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read()).get("response", "")


def call_llama_gbnf(prompt, grammar_text, temperature=0.3):
    """llama.cpp server with grammar-constrained sampling."""
    payload = {
        "prompt": prompt,
        "grammar": grammar_text,
        "temperature": temperature,
        "n_predict": 2048,
    }
    req = urllib.request.Request(
        f"{LLAMA_URL}/completion",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read()).get("content", "")


def mode_gbnf(natural_language):
    grammar = GRAMMAR.read_text()
    prompt = f"Convert this natural language instruction into a sovereign XML system prompt:\n\n{natural_language}"
    print("[gbnf] calling llama.cpp with grammar-constrained sampling...")
    result = call_llama_gbnf(prompt, grammar)
    return result


def mode_skeleton(natural_language):
    skeleton = SKELETON.read_text()
    placeholders = re.findall(r"\{\{(\w+)\}\}", skeleton)

    prompt = f"""Skeleton placeholders to fill: {placeholders}

Natural language instruction:
{natural_language}

Return a JSON object with exactly these keys: {placeholders}"""

    print("[skeleton] filling placeholders via LLM...")
    raw = call_ollama(SKELETON_SYSTEM, prompt, temperature=0.2)

    # extract JSON
    j_start = raw.find("{")
    j_end = raw.rfind("}") + 1
    if j_start == -1:
        raise ValueError(f"No JSON in response: {raw[:200]}")

    fills = json.loads(raw[j_start:j_end])

    result = skeleton
    for key, value in fills.items():
        result = result.replace("{{" + key + "}}", str(value))

    # check for unfilled placeholders
    remaining = re.findall(r"\{\{(\w+)\}\}", result)
    if remaining:
        print(f"[skeleton] warning: unfilled placeholders: {remaining}")

    return result


def mode_dual_pass(natural_language):
    print("[dual-pass] generating thought_process then xml_output...")
    raw = call_ollama(DUAL_PASS_SYSTEM, natural_language, temperature=0.4)

    # extract xml_output block
    match = re.search(r"<xml_output>(.*?)</xml_output>", raw, re.DOTALL)
    if match:
        return match.group(1).strip()

    # fallback: extract any XML
    match = re.search(r"<system_prompt>.*?</system_prompt>", raw, re.DOTALL)
    if match:
        return match.group(0)

    return raw


def validate_xml(xml_text):
    """Basic structural validation."""
    required = ["<system_prompt>", "<identity>", "<logic_gates>", "<execution_flow>"]
    missing = [tag for tag in required if tag not in xml_text]
    if missing:
        return False, f"missing tags: {missing}"
    return True, "ok"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["gbnf", "skeleton", "dual-pass"], default="skeleton")
    parser.add_argument("--input", required=True, help="Natural language system prompt description")
    parser.add_argument("--output", default=None, help="Write XML to file")
    args = parser.parse_args()

    if args.mode == "gbnf":
        result = mode_gbnf(args.input)
    elif args.mode == "skeleton":
        result = mode_skeleton(args.input)
    else:
        result = mode_dual_pass(args.input)

    valid, msg = validate_xml(result)
    if not valid:
        print(f"[validate] WARN: {msg}")
    else:
        print("[validate] ok")

    if args.output:
        Path(args.output).write_text(result)
        print(f"[output] written to {args.output}")
    else:
        print("\n" + result)


if __name__ == "__main__":
    main()
