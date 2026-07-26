#!/usr/bin/env python3
"""
ai.py — sovereign AI CLI. No Claude. DeepSeek-R1 by default.

Usage:
  python ai.py "write me a lean 4 proof of X"
  python ai.py --model coder "scaffold this file"
  cat file.lean | python ai.py "close the sorries"
  python ai.py --list
"""
import sys, os, json, requests, argparse

KEY = os.environ.get("OPENROUTER_API_KEY", """")
URL = "https://openrouter.ai/api/v1/chat/completions"

MODELS = {
    "r1":     "deepseek/deepseek-r1-0528",
    "coder":  "qwen/qwen-2.5-coder-32b-instruct",
    "free":   "deepseek/deepseek-r1-0528:free",
    "flash":  "google/gemini-2.5-flash",
    "pro":    "google/gemini-2.5-pro",
}
DEFAULT = "coder"

def call(model_key, prompt, system=None):
    model = MODELS.get(model_key, model_key)
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    resp = requests.post(URL,
        headers={
            "Authorization": f"Bearer {KEY}",
            "HTTP-Referer": "https://snapkittywest.io",
            "X-Title": "SNAPKITTY"
        },
        json={
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 16384,
            "stream": False
        },
        timeout=300)

    resp.raise_for_status()
    data = resp.json()
    content = data["choices"][0]["message"]["content"]
    print(content)
    return content

def main():
    parser = argparse.ArgumentParser(description="Sovereign AI CLI — DeepSeek/Qwen via OpenRouter")
    parser.add_argument("prompt", nargs="?", help="Prompt text")
    parser.add_argument("--model", "-m", default=DEFAULT, help=f"Model: {list(MODELS.keys())}")
    parser.add_argument("--list", "-l", action="store_true", help="List available models")
    parser.add_argument("--system", "-s", default=None, help="System prompt")
    parser.add_argument("--out", "-o", default=None, help="Write output to file")
    args = parser.parse_args()

    if args.list:
        for k, v in MODELS.items():
            marker = " *" if k == DEFAULT else ""
            print(f"  {k:8} {v}{marker}")
        return

    stdin_data = ""
    if not sys.stdin.isatty():
        stdin_data = sys.stdin.read().strip()

    prompt = args.prompt or ""
    if stdin_data:
        prompt = f"{prompt}\n\n```\n{stdin_data}\n```" if prompt else stdin_data

    if not prompt:
        parser.print_help()
        return

    result = call(args.model, prompt, args.system)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"\n→ written to {args.out}", file=sys.stderr)

if __name__ == "__main__":
    main()
