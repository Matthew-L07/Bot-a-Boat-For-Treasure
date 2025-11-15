# export_weights.py
import json
import torch
import numpy as np

CKPT_PATH = "dqn_weights_best.pth"
OUT_JSON_PATH = "dqn_weights.json"

def main():
    ckpt = torch.load(CKPT_PATH, map_location="cpu")
    state_dim = ckpt["state_dim"]
    num_actions = ckpt["num_actions"]
    state_dict = ckpt["model_state_dict"]

    print("Checkpoint keys:", ckpt.keys())
    print("state_dim:", state_dim, "num_actions:", num_actions)
    for name, param in state_dict.items():
        print(name, param.shape)

    # We know the model is:
    # Linear(state_dim -> 128) -> ReLU -> Linear(128 -> 128) -> ReLU -> Linear(128 -> num_actions)
    layers = []
    layer_names = [
        ("net.0.weight", "net.0.bias"),  # first Linear
        ("net.2.weight", "net.2.bias"),  # second Linear
        ("net.4.weight", "net.4.bias"),  # output Linear
    ]

    for w_name, b_name in layer_names:
        W = state_dict[w_name].cpu().numpy().tolist()  # shape: [out_dim, in_dim]
        b = state_dict[b_name].cpu().numpy().tolist()  # shape: [out_dim]
        layers.append({"W": W, "b": b})

    export = {
        "state_dim": int(state_dim),
        "num_actions": int(num_actions),
        "layers": layers,
    }

    with open(OUT_JSON_PATH, "w") as f:
        json.dump(export, f)
    print(f"Exported weights to {OUT_JSON_PATH}")

if __name__ == "__main__":
    main()
