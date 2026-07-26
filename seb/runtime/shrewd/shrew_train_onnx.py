#!/usr/bin/env python3
"""
shrew_train_onnx.py — Train and export the SHREWD ONNX model.
Shape: (1000, 8) → (1, 4) — 4-class verdict predictor.

Usage:
  python shrew_train_onnx.py                          # train on synthetic data
  python shrew_train_onnx.py --worm-log path/to.jsonl # train on real WORM log
  python shrew_train_onnx.py --export-only             # export existing model

Output:
  shrew_predictor.onnx   — set SHREWD_MODEL_PATH to this path
  shrew_predictor.pt     — PyTorch weights (for fine-tuning)

Model architecture:
  Input:  (batch, 1000, 8)  — sequence of 1000 tick features
  Conv1d: 8→32, kernel=3    — local temporal pattern detection
  LSTM:   32→64             — sequence modeling
  Linear: 64→4              — verdict logits
  Output: (batch, 4)        — [proven, shrewd, causal, noise] probs

Runs on CPU in ~2 minutes. With CUDA: ~15 seconds.
"""

import argparse
import json
import hashlib
import random
import struct
from pathlib import Path
from typing import Optional

VERDICT_ENC = {"SKER_PROVEN": 0, "SKER_SHREWD": 1, "SKER_CAUSAL": 2, "SKER_NOISE": 3}
SOVEREIGN_AGENTS = {
    "cipher","veil","vault","ledger","sentinel","ward","atlas","dawn",
    "ledge","mnemex","oracle","mira","axiom","prism","herald","lyra",
    "flux","storm","phantom","shade","nexus","bridge","forge","ember",
    "nova","echo","ahmad","edaulc","lens","stalas","loc","shrew",
}

# ── Feature extraction (matches shrewd_engine.py exactly) ────────────────────

def extract_features(entries: list) -> list:
    features = []
    prev_tick = entries[0]["tick"] if entries else 0
    for e in entries:
        v_enc  = VERDICT_ENC.get(e.get("verdict","SKER_NOISE"), 3) / 3.0
        has_p  = 1.0 if e.get("proof_hash") else 0.0
        a_hash = int(hashlib.sha256(e.get("agent_key","").encode()).hexdigest()[:4],16) / 65535.0
        t_delt = min((e["tick"] - prev_tick) / 1000.0, 1.0)
        ts_h   = (e.get("ts",0) // 3_600_000 % 24) / 24.0
        op_h   = int(hashlib.sha256(e.get("op","").encode()).hexdigest()[:4],16) / 65535.0
        is_sov = 1.0 if e.get("agent_key","") in SOVEREIGN_AGENTS else 0.0
        seal   = e.get("shrew_seal","00")
        s_ent  = int(seal[:2],16)/255.0 if len(seal)>=2 else 0.0
        features.append([v_enc,has_p,a_hash,t_delt,ts_h,op_h,is_sov,s_ent])
        prev_tick = e["tick"]
    return features

# ── Synthetic data generator ──────────────────────────────────────────────────

def synthetic_window(label: int, size: int = 1000) -> tuple:
    """Generate a synthetic 1000-tick window with label as ground truth."""
    entries = []
    base_tick = random.randint(0, 1_000_000)
    agents = list(SOVEREIGN_AGENTS)

    for i in range(size):
        # Bias distribution toward label
        if label == 0:   # PROVEN: mostly proven
            v = random.choices(["SKER_PROVEN","SKER_SHREWD","SKER_CAUSAL","SKER_NOISE"],
                               weights=[0.7, 0.15, 0.10, 0.05])[0]
        elif label == 1: # SHREWD: mix of shrewd + proven
            v = random.choices(["SKER_PROVEN","SKER_SHREWD","SKER_CAUSAL","SKER_NOISE"],
                               weights=[0.20, 0.55, 0.15, 0.10])[0]
        elif label == 2: # CAUSAL: mostly causal
            v = random.choices(["SKER_PROVEN","SKER_SHREWD","SKER_CAUSAL","SKER_NOISE"],
                               weights=[0.10, 0.20, 0.50, 0.20])[0]
        else:            # NOISE: degrading
            v = random.choices(["SKER_PROVEN","SKER_SHREWD","SKER_CAUSAL","SKER_NOISE"],
                               weights=[0.05, 0.10, 0.15, 0.70])[0]

        tick = base_tick + i
        ts   = 1_700_000_000_000 + tick * 1000
        agent = random.choice(agents) if random.random() > 0.3 else ""
        proof = hashlib.sha256(f"proof{tick}".encode()).hexdigest() if v == "SKER_PROVEN" else None

        entries.append({
            "tick": tick, "ts": ts, "verdict": v,
            "agent_key": agent, "op": f"op_{i%20}",
            "proof_hash": proof, "payload_hash": f"ph{i}",
            "shrew_seal": hashlib.sha256(f"{tick}{v}".encode()).hexdigest()
        })

    feats = extract_features(entries)
    return feats, label


def generate_dataset(n_samples: int = 4000):
    X, y = [], []
    for label in range(4):
        for _ in range(n_samples // 4):
            feats, lbl = synthetic_window(label)
            X.append(feats)
            y.append(lbl)
    return X, y


def load_worm_log(path: str, window_size: int = 1000):
    """Load real WORM log and build training windows with sliding window."""
    entries = []
    with open(path) as f:
        for line in f:
            try:
                entries.append(json.loads(line.strip()))
            except: pass

    if len(entries) < window_size:
        print(f"[train] only {len(entries)} entries — need {window_size} minimum for real data")
        print("[train] falling back to synthetic data")
        return None

    # Build windows: each window labeled by its dominant last-100 verdict
    X, y = [], []
    for start in range(0, len(entries) - window_size, window_size // 4):
        window = entries[start:start + window_size]
        feats  = extract_features(window)
        # Label by majority of last 100 entries
        last100 = window[-100:]
        counts  = {0:0, 1:0, 2:0, 3:0}
        for e in last100:
            counts[VERDICT_ENC.get(e.get("verdict","SKER_NOISE"),3)] += 1
        label = max(counts, key=counts.get)
        X.append(feats)
        y.append(label)

    print(f"[train] loaded {len(X)} windows from {len(entries)} WORM entries")
    return X, y


# ── PyTorch model ─────────────────────────────────────────────────────────────

def build_model():
    import torch
    import torch.nn as nn

    class ShrewdPredictor(nn.Module):
        def __init__(self):
            super().__init__()
            # 1D convolution over time: 8 features → 32 channels
            self.conv = nn.Conv1d(in_channels=8, out_channels=32, kernel_size=3, padding=1)
            self.relu = nn.ReLU()
            # LSTM over 1000 timesteps
            self.lstm = nn.LSTM(input_size=32, hidden_size=64, num_layers=2,
                                batch_first=True, dropout=0.2)
            # Final classifier
            self.classifier = nn.Sequential(
                nn.Linear(64, 32),
                nn.ReLU(),
                nn.Dropout(0.1),
                nn.Linear(32, 4)
            )

        def forward(self, x):
            # x: (batch, 1000, 8)
            x = x.permute(0, 2, 1)           # → (batch, 8, 1000)
            x = self.relu(self.conv(x))        # → (batch, 32, 1000)
            x = x.permute(0, 2, 1)           # → (batch, 1000, 32)
            _, (h, _) = self.lstm(x)          # h: (2, batch, 64)
            x = h[-1]                          # → (batch, 64) last layer hidden
            return self.classifier(x)          # → (batch, 4)

    return ShrewdPredictor()


def train(X, y, epochs: int = 20, batch_size: int = 32) -> "ShrewdPredictor":
    import torch
    import torch.nn as nn
    import torch.optim as optim

    model  = build_model()
    opt    = optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
    loss_fn = nn.CrossEntropyLoss()
    sched  = optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)

    # Convert to tensors
    X_t = torch.tensor(X, dtype=torch.float32)   # (N, 1000, 8)
    y_t = torch.tensor(y, dtype=torch.long)        # (N,)

    dataset = torch.utils.data.TensorDataset(X_t, y_t)
    loader  = torch.utils.data.DataLoader(dataset, batch_size=batch_size, shuffle=True)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"[train] device={device} samples={len(X)} epochs={epochs}")
    model = model.to(device)

    for epoch in range(epochs):
        model.train()
        total_loss, correct, total = 0.0, 0, 0
        for xb, yb in loader:
            xb, yb = xb.to(device), yb.to(device)
            opt.zero_grad()
            out  = model(xb)
            loss = loss_fn(out, yb)
            loss.backward()
            opt.step()
            total_loss += loss.item() * len(yb)
            correct    += (out.argmax(1) == yb).sum().item()
            total      += len(yb)
        sched.step()
        acc = correct / total
        if epoch % 5 == 0 or epoch == epochs - 1:
            print(f"  epoch {epoch+1:3d}/{epochs}  loss={total_loss/total:.4f}  acc={acc:.3f}")

    model = model.cpu()
    return model


def export_onnx(model, output_path: str = "shrew_predictor.onnx"):
    import torch
    model.eval()
    dummy = torch.zeros(1, 1000, 8)  # (batch=1, seq=1000, features=8)
    torch.onnx.export(
        model, dummy, output_path,
        input_names=["shrew_window"],
        output_names=["verdict_logits"],
        dynamic_axes={
            "shrew_window":   {0: "batch"},
            "verdict_logits": {0: "batch"},
        },
        opset_version=17,
        do_constant_folding=True,
    )
    print(f"[export] ONNX model → {output_path}")
    print(f"[export] set SHREWD_MODEL_PATH={output_path}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--worm-log",    default=None, help="Path to WORM .jsonl log")
    ap.add_argument("--epochs",      type=int, default=20)
    ap.add_argument("--samples",     type=int, default=4000, help="Synthetic samples")
    ap.add_argument("--output",      default="shrew_predictor.onnx")
    ap.add_argument("--export-only", action="store_true", help="Export existing .pt")
    args = ap.parse_args()

    try:
        import torch
    except ImportError:
        print("ERROR: pip install torch")
        return 1

    pt_path = args.output.replace(".onnx", ".pt")

    if args.export_only:
        print(f"[export-only] loading {pt_path}")
        import torch
        model = build_model()
        model.load_state_dict(torch.load(pt_path, map_location="cpu"))
        export_onnx(model, args.output)
        return 0

    # Load or generate data
    data = None
    if args.worm_log:
        data = load_worm_log(args.worm_log)

    if data is None:
        print(f"[train] generating {args.samples} synthetic windows...")
        X, y = generate_dataset(args.samples)
    else:
        X, y = data

    # Train
    model = train(X, y, epochs=args.epochs)

    # Save weights
    import torch
    torch.save(model.state_dict(), pt_path)
    print(f"[train] weights → {pt_path}")

    # Export ONNX
    export_onnx(model, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
