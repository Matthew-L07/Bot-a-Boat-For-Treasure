# train_dqn.py
import os
import glob
import json
from typing import List, Tuple

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import TensorDataset, DataLoader


# -----------------------------
# Data loading
# -----------------------------
def load_transitions(log_dir: str = "logs") -> Tuple[List[dict], int, int]:
    pattern = os.path.join(log_dir, "transitions_*.json")
    files = sorted(glob.glob(pattern))

    if not files:
        raise FileNotFoundError(f"No transition files found at {pattern}")

    all_transitions: List[dict] = []
    for path in files:
        with open(path, "r") as f:
            data = json.load(f)
        if isinstance(data, dict):
            # Just in case, but your Agent writes a list
            data = [data]
        all_transitions.extend(data)

    if not all_transitions:
        raise ValueError("Loaded transition files but found no transitions.")

    # Infer dimensions from data
    state_dim = len(all_transitions[0]["s"])
    num_actions = max(t["a"] for t in all_transitions)

    print(f"Loaded {len(all_transitions)} transitions from {len(files)} files.")
    print(f"Inferred state_dim = {state_dim}, num_actions = {num_actions}")

    return all_transitions, state_dim, num_actions


def transitions_to_tensors(
    transitions: List[dict],
    state_dim: int,
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
    states = []
    actions = []
    rewards = []
    next_states = []
    dones = []

    for t in transitions:
        s = t["s"]
        a = t["a"]          # 1-based from Roblox
        r = t["r"]
        ns = t["ns"]
        d = t["d"]

        if len(s) != state_dim or len(ns) != state_dim:
            raise ValueError("Inconsistent state dimension in transitions.")

        states.append(s)
        actions.append(a - 1)  # convert to 0-based for PyTorch
        rewards.append(r)
        next_states.append(ns)
        dones.append(1.0 if d else 0.0)

    states = torch.tensor(np.array(states), dtype=torch.float32)
    actions = torch.tensor(np.array(actions), dtype=torch.long)
    rewards = torch.tensor(np.array(rewards), dtype=torch.float32)
    next_states = torch.tensor(np.array(next_states), dtype=torch.float32)
    dones = torch.tensor(np.array(dones), dtype=torch.float32)

    return states, actions, rewards, next_states, dones


# -----------------------------
# DQN model
# -----------------------------
class DQN(nn.Module):
    def __init__(self, state_dim: int, num_actions: int):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(state_dim, 128),
            nn.ReLU(),
            nn.Linear(128, 128),
            nn.ReLU(),
            nn.Linear(128, num_actions),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


# -----------------------------
# Training loop
# -----------------------------
def train_dqn(
    log_dir: str = "logs",
    batch_size: int = 64,
    num_epochs: int = 10,      # fewer epochs to reduce late-epoch blowups
    gamma: float = 0.99,
    lr: float = 1e-4,          # smaller LR for stability
    device: str = "cpu",
    save_path: str = "dqn_weights.pth",
    best_save_path: str = "dqn_weights_best.pth",
):
    # Load data
    transitions, state_dim, num_actions = load_transitions(log_dir)
    states, actions, rewards, next_states, dones = transitions_to_tensors(
        transitions, state_dim
    )

    dataset = TensorDataset(states, actions, rewards, next_states, dones)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    # Model + optimizer
    device = torch.device(device)
    model = DQN(state_dim, num_actions).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    mse_loss = nn.MSELoss()

    print(f"Starting training on {device}...")
    print(
        f"Dataset size: {len(dataset)}, "
        f"batch_size: {batch_size}, "
        f"epochs: {num_epochs}, "
        f"lr: {lr}"
    )

    model.train()
    best_loss = float("inf")

    for epoch in range(1, num_epochs + 1):
        epoch_loss = 0.0
        num_batches = 0

        for batch in dataloader:
            batch_states, batch_actions, batch_rewards, batch_next_states, batch_dones = [
                x.to(device) for x in batch
            ]

            # Q(s, a)
            q_values = model(batch_states)  # (B, num_actions)
            q_sa = q_values.gather(1, batch_actions.unsqueeze(1)).squeeze(1)

            # max_a' Q(s', a')
            with torch.no_grad():
                next_q_values = model(batch_next_states)
                max_next_q, _ = next_q_values.max(dim=1)
                targets = batch_rewards + gamma * (1.0 - batch_dones) * max_next_q

            loss = mse_loss(q_sa, targets)

            optimizer.zero_grad()
            loss.backward()

            # Gradient clipping to prevent exploding updates
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)

            optimizer.step()

            epoch_loss += loss.item()
            num_batches += 1

        avg_loss = epoch_loss / max(num_batches, 1)
        print(f"Epoch {epoch}/{num_epochs} - avg loss: {avg_loss:.6f}")

        # Save best checkpoint by avg loss
        if avg_loss < best_loss:
            best_loss = avg_loss
            torch.save(
                {
                    "state_dim": state_dim,
                    "num_actions": num_actions,
                    "model_state_dict": model.state_dict(),
                },
                best_save_path,
            )

    # Save final weights (last epoch)
    torch.save(
        {
            "state_dim": state_dim,
            "num_actions": num_actions,
            "model_state_dict": model.state_dict(),
        },
        save_path,
    )
    print(f"Saved final DQN weights to {save_path}")
    print(f"Saved best (by avg loss) DQN weights to {best_save_path} with loss {best_loss:.6f}")


if __name__ == "__main__":
    # Runs with the more conservative defaults above
    train_dqn()
