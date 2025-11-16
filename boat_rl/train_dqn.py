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
            data = [data]
        all_transitions.extend(data)

    if not all_transitions:
        raise ValueError("Loaded transition files but found no transitions.")

    # Infer dimensions from data
    state_dim = len(all_transitions[0]["s"])
    num_actions = max(t["a"] for t in all_transitions)

    print(f"Loaded {len(all_transitions)} transitions from {len(files)} files.")
    print(f"Inferred state_dim = {state_dim}, num_actions = {num_actions}")
    
    # Validate dimensions match expectations
    if state_dim != 9:
        print(f"WARNING: Expected state_dim=9, got {state_dim}")
    if num_actions != 5:
        print(f"WARNING: Expected num_actions=5, got {num_actions}")

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
            raise ValueError(f"Inconsistent state dimension: expected {state_dim}, got s={len(s)}, ns={len(ns)}")

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
    """
    DQN architecture for 9-dimensional state space and 5 actions
    Architecture: 9 -> 128 -> 128 -> 5
    """
    def __init__(self, state_dim: int, num_actions: int):
        super().__init__()
        
        if state_dim != 9:
            print(f"WARNING: DQN initialized with state_dim={state_dim}, expected 9")
        if num_actions != 5:
            print(f"WARNING: DQN initialized with num_actions={num_actions}, expected 5")
        
        self.net = nn.Sequential(
            nn.Linear(state_dim, 128),
            nn.ReLU(),
            nn.Linear(128, 128),
            nn.ReLU(),
            nn.Linear(128, num_actions),
        )
        
        self._initialize_weights()
    
    def _initialize_weights(self):
        for m in self.modules():
            if isinstance(m, nn.Linear):
                nn.init.xavier_uniform_(m.weight)
                nn.init.constant_(m.bias, 0.0)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


# -----------------------------
# Training loop
# -----------------------------
def train_dqn(
    log_dir: str = "logs",
    batch_size: int = 64,
    num_epochs: int = 5,          # fewer epochs over offline data
    gamma: float = 0.99,
    lr: float = 5e-5,             # slightly smaller LR for stability
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

    device = torch.device(device)
    model = DQN(state_dim, num_actions).to(device)
    target_model = DQN(state_dim, num_actions).to(device)
    target_model.load_state_dict(model.state_dict())  # start in sync

    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.SmoothL1Loss()  # Huber loss is more stable than pure MSE

    print(f"\nStarting training on {device}...")
    print(f"Model architecture: {state_dim} -> 128 -> 128 -> {num_actions}")
    print(
        f"Dataset size: {len(dataset)}, "
        f"batch_size: {batch_size}, "
        f"epochs: {num_epochs}, "
        f"lr: {lr}, "
        f"gamma: {gamma}"
    )

    # Print sample statistics
    print(f"\nDataset statistics:")
    print(f"  Rewards: min={rewards.min():.3f}, max={rewards.max():.3f}, mean={rewards.mean():.3f}")
    print(f"  States: min={states.min():.3f}, max={states.max():.3f}")
    print(f"  Actions distribution: {torch.bincount(actions + 1)}")
    print()

    model.train()
    target_model.eval()

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

            # max_a' Q_target(s', a')
            with torch.no_grad():
                next_q_values = target_model(batch_next_states)
                max_next_q, _ = next_q_values.max(dim=1)
                targets = batch_rewards + gamma * (1.0 - batch_dones) * max_next_q

            loss = loss_fn(q_sa, targets)

            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()

            epoch_loss += loss.item()
            num_batches += 1

        avg_loss = epoch_loss / max(num_batches, 1)
        print(f"Epoch {epoch}/{num_epochs} - avg loss: {avg_loss:.6f}")

        # Update target network once per epoch
        target_model.load_state_dict(model.state_dict())

        # Save best checkpoint by avg loss
        if avg_loss < best_loss:
            best_loss = avg_loss
            torch.save(
                {
                    "state_dim": state_dim,
                    "num_actions": num_actions,
                    "model_state_dict": model.state_dict(),
                    "epoch": epoch,
                    "loss": avg_loss,
                },
                best_save_path,
            )
            print(f"  → Saved new best model (loss: {avg_loss:.6f})")

    # Save final weights (last epoch)
    torch.save(
        {
            "state_dim": state_dim,
            "num_actions": num_actions,
            "model_state_dict": model.state_dict(),
            "epoch": num_epochs,
            "loss": avg_loss,
        },
        save_path,
    )
    print(f"\nSaved final DQN weights to {save_path}")
    print(f"Saved best (by avg loss) DQN weights to {best_save_path} with loss {best_loss:.6f}")


if __name__ == "__main__":
    train_dqn()
