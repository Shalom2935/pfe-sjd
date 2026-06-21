"""
Pipeline PyTorch compact pour le diagnostic FaultSim.

Usage Colab / local :
python ai/pipeline_faultdiag.py \
  --features_csv /content/faultdiag_dataset/features.csv \
  --out_dir /content/runs/faultdiag_mlp

Le script attend un CSV contenant les features exportées par FaultSim. Les colonnes
`class_name` et `fault_distance_m` servent de cibles. Les colonnes descriptives du
scénario sont exclues des entrées afin d'éviter une fuite d'information.
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, classification_report
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from torch.utils.data import DataLoader, TensorDataset


SEED = 42
LOOP_LENGTH_M = 9007.0
TARGET_CLASSES = [
    "HUMIDITY_PROGRESSIVE",
    "REACTIVE_INCIPIENT",
    "EARTH_SHORT",
    "OPEN_CIRCUIT",
]
EXCLUDED_COLUMNS = {
    "scenario_id",
    "class_id",
    "class_name",
    "fault_group",
    "electrical_fault_family",
    "fault_location_type",
    "fault_distance_m",
    "node_index",
    "fault_regard_index",
    "fault_module_index",
    "fault_R_ohm",
    "fault_C_F",
    "load_fault_mode",
    "brightness_label",
}


def set_seed(seed: int = SEED) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


class TabularHierMLP(nn.Module):
    def __init__(self, feature_dim: int, num_classes: int, dropout: float = 0.15) -> None:
        super().__init__()
        self.encoder = nn.Sequential(
            nn.LayerNorm(feature_dim),
            nn.Linear(feature_dim, 128),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(128, 128),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(128, 64),
            nn.GELU(),
        )
        self.classifier = nn.Sequential(
            nn.Linear(64, 32),
            nn.GELU(),
            nn.Linear(32, num_classes),
        )
        self.distance = nn.Sequential(
            nn.Linear(64, 32),
            nn.GELU(),
            nn.Linear(32, 1),
        )

    def forward(self, x: torch.Tensor) -> Dict[str, torch.Tensor]:
        z = self.encoder(x)
        return {
            "logits": self.classifier(z),
            "distance_norm": self.distance(z).squeeze(1),
        }


def count_parameters(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


def load_dataset(features_csv: Path) -> Tuple[pd.DataFrame, List[str], Dict[str, int]]:
    df = pd.read_csv(features_csv)
    df = df[df["class_name"].isin(TARGET_CLASSES)].copy()
    df = df.dropna(subset=["class_name", "fault_distance_m"])

    label_to_id = {name: i for i, name in enumerate(TARGET_CLASSES)}
    df["y_class"] = df["class_name"].map(label_to_id)
    df["y_distance_norm"] = df["fault_distance_m"] / LOOP_LENGTH_M

    numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
    feature_cols = [c for c in numeric_cols if c not in EXCLUDED_COLUMNS and not c.startswith("y_")]
    df[feature_cols] = df[feature_cols].replace([np.inf, -np.inf], np.nan)
    df = df.dropna(subset=feature_cols)
    return df, feature_cols, label_to_id


def make_loaders(df: pd.DataFrame, feature_cols: List[str], batch_size: int = 64):
    train_df, temp_df = train_test_split(
        df,
        test_size=0.35,
        stratify=df["y_class"],
        random_state=SEED,
    )
    val_df, test_df = train_test_split(
        temp_df,
        test_size=0.57,
        stratify=temp_df["y_class"],
        random_state=SEED,
    )

    scaler = StandardScaler()
    x_train = scaler.fit_transform(train_df[feature_cols].values).astype("float32")
    x_val = scaler.transform(val_df[feature_cols].values).astype("float32")
    x_test = scaler.transform(test_df[feature_cols].values).astype("float32")

    def to_dataset(part: pd.DataFrame, x: np.ndarray) -> TensorDataset:
        return TensorDataset(
            torch.tensor(x),
            torch.tensor(part["y_class"].values, dtype=torch.long),
            torch.tensor(part["y_distance_norm"].values, dtype=torch.float32),
            torch.tensor(part["fault_distance_m"].values, dtype=torch.float32),
        )

    loaders = {
        "train": DataLoader(to_dataset(train_df, x_train), batch_size=batch_size, shuffle=True),
        "val": DataLoader(to_dataset(val_df, x_val), batch_size=batch_size, shuffle=False),
        "test": DataLoader(to_dataset(test_df, x_test), batch_size=batch_size, shuffle=False),
    }
    return loaders, scaler, {"train": train_df, "val": val_df, "test": test_df}


def run_epoch(model, loader, optimizer, device, train: bool) -> Dict[str, float]:
    model.train(train)
    ce = nn.CrossEntropyLoss()
    huber = nn.SmoothL1Loss(beta=0.05)
    losses = []
    y_true, y_pred, d_true, d_pred = [], [], [], []

    for x, yc, yd_norm, yd_m in loader:
        x, yc, yd_norm = x.to(device), yc.to(device), yd_norm.to(device)
        with torch.set_grad_enabled(train):
            out = model(x)
            loss_cls = ce(out["logits"], yc)
            loss_dist = huber(out["distance_norm"], yd_norm)
            loss = loss_cls + 0.30 * loss_dist
            if train:
                optimizer.zero_grad()
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                optimizer.step()

        losses.append(float(loss.detach().cpu()))
        pred = out["logits"].argmax(dim=1).detach().cpu().numpy()
        y_true.extend(yc.detach().cpu().numpy().tolist())
        y_pred.extend(pred.tolist())
        d_true.extend(yd_m.numpy().tolist())
        d_pred.extend((out["distance_norm"].detach().cpu().numpy() * LOOP_LENGTH_M).tolist())

    err = np.abs(np.array(d_pred) - np.array(d_true))
    return {
        "loss": float(np.mean(losses)),
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, y_pred)),
        "macro_f1": float(f1_score(y_true, y_pred, average="macro")),
        "distance_mae_m": float(err.mean()),
        "distance_median_ae_m": float(np.median(err)),
        "within_60m": float((err <= 60).mean()),
        "within_120m": float((err <= 120).mean()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--features_csv", type=Path, required=True)
    parser.add_argument("--out_dir", type=Path, default=Path("runs/faultdiag_mlp"))
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--batch_size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-3)
    args = parser.parse_args()

    set_seed()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    device = "cuda" if torch.cuda.is_available() else "cpu"

    df, feature_cols, label_to_id = load_dataset(args.features_csv)
    loaders, scaler, split_frames = make_loaders(df, feature_cols, args.batch_size)

    model = TabularHierMLP(len(feature_cols), len(label_to_id)).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)

    best_val = float("inf")
    log = []
    best_path = args.out_dir / "best.pt"

    for epoch in range(1, args.epochs + 1):
        train_metrics = run_epoch(model, loaders["train"], optimizer, device, train=True)
        val_metrics = run_epoch(model, loaders["val"], optimizer, device, train=False)
        row = {"epoch": epoch, **{f"train_{k}": v for k, v in train_metrics.items()}, **{f"val_{k}": v for k, v in val_metrics.items()}}
        log.append(row)
        if val_metrics["loss"] < best_val:
            best_val = val_metrics["loss"]
            torch.save({
                "model_state": model.state_dict(),
                "feature_cols": feature_cols,
                "label_to_id": label_to_id,
                "num_parameters": count_parameters(model),
            }, best_path)

    checkpoint = torch.load(best_path, map_location=device)
    model.load_state_dict(checkpoint["model_state"])
    final_metrics = {name: run_epoch(model, loader, None, device, train=False) for name, loader in loaders.items()}

    pd.DataFrame(log).to_csv(args.out_dir / "training_log.csv", index=False)
    with open(args.out_dir / "metrics.json", "w", encoding="utf-8") as f:
        json.dump({
            "num_rows": int(len(df)),
            "num_features": int(len(feature_cols)),
            "num_parameters": int(count_parameters(model)),
            "label_to_id": label_to_id,
            "metrics": final_metrics,
        }, f, indent=2, ensure_ascii=False)

    print(json.dumps(final_metrics["test"], indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
