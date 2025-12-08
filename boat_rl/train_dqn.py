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
# Data loading (episode-aware with improved filtering)
# -----------------------------
def load_transitions(
    log_dir: str = "logs",
    elite_fraction: float = 0.5,
    min_progress_threshold: float = 0.2,  # NEW: Keep episodes with >20% progress
) -> Tuple[List[dict], int, int]:
    """
    Load transitions from logs, treating each file as a single episode.

    Improvements:
    - Keeps episodes with meaningful progress (>20%) OR top 50% by return
    - This ensures we learn from partial successes, not just crashes
    """
    pattern = os.path.join(log_dir, "transitions_*.json")
    files = sorted(glob.glob(pattern))

    if not files:
        raise FileNotFoundError(f"No transition files found at {pattern}")

    episodes = []

    for path in files:
        with open(path, "r") as f:
            data = json.load(f)

        if isinstance(data, dict) and "transitions" in data:
            transitions = data["transitions"]
        elif isinstance(data, list):
            transitions = data
        else:
            transitions = [data]

        if not transitions:
            continue

        ep_return = 0.0
        max_progress = 0.0
        
        for t in transitions:
            ep_return += float(t.get("r", 0.0))
            # Track maximum progress reached (state[0] is progress)
            if "s" in t and len(t["s"]) > 0:
                max_progress = max(max_progress, t["s"][0])

        episodes.append(
            {
                "file": path,
                "transitions": transitions,
                "return": ep_return,
                "max_progress": max_progress,
            }
        )

    if not episodes:
        raise ValueError("Loaded log files but found no transitions in any episode.")

    # NEW: Two-stage filtering
    # Stage 1: Keep episodes with meaningful progress
    progress_filtered = [e for e in episodes if e["max_progress"] >= min_progress_threshold]
    
    # Stage 2: If we filtered out too many, fall back to top elite_fraction by return
    num_episodes = len(episodes)
    min_keep = max(1, int(num_episodes * elite_fraction))
    
    if len(progress_filtered) < min_keep:
        print(f"Progress filter kept {len(progress_filtered)} episodes, using return-based filter instead")
        episodes.sort(key=lambda e: e["return"])
        elite_episodes = episodes[-min_keep:]
    else:
        print(f"Progress filter kept {len(progress_filtered)}/{num_episodes} episodes (progress >= {min_progress_threshold})")
        elite_episodes = progress_filtered

    # Flatten transitions from selected episodes
    all_transitions: List[dict] = []
    for ep in elite_episodes:
        all_transitions.extend(ep["transitions"])

    # Infer state_dim and num_actions from selected transitions
    first_transition = elite_episodes[0]["transitions"][0]
    state_dim = len(first_transition["s"])
    num_actions = max(t["a"] for ep in elite_episodes for t in ep["transitions"])

    # Calculate statistics
    returns = [e["return"] for e in elite_episodes]
    progresses = [e["max_progress"] for e in elite_episodes]
    
    print(f"\n=== Episode Statistics ===")
    print(f"Total episodes: {num_episodes}")
    print(f"Selected episodes: {len(elite_episodes)}")
    print(f"Episode returns: min={min(returns):.2f}, median={sorted(returns)[len(returns)//2]:.2f}, max={max(returns):.2f}")
    print(f"Max progress: min={min(progresses):.2f}, median={sorted(progresses)[len(progresses)//2]:.2f}, max={max(progresses):.2f}")
    print(f"Total transitions: {len(all_transitions)}")
    print(f"Inferred state_dim={state_dim}, num_actions={num_actions}")

    if state_dim != 11:
        print(f"WARNING: Expected state_dim=11, got {state_dim}")
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
            raise ValueError(
                f"Inconsistent state dimension: expected {state_dim}, got s={len(s)}, ns={len(ns)}"
            )

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
# DQN model (with Double DQN support)
# -----------------------------
class DQN(nn.Module):
    """
    DQN architecture: state_dim -> 128 -> 128 -> num_actions
    """
    def __init__(self, state_dim: int, num_actions: int):
        super().__init__()
        
        if state_dim != 11:
            print(f"WARNING: DQN initialized with state_dim={state_dim}, expected 11")
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
# Training loop (with Double DQN)
# -----------------------------
def train_dqn(
    log_dir: str = "logs",
    batch_size: int = 64,
    num_epochs: int = 10,
    gamma: float = 0.95,             # Shorter horizon for tactical navigation
    lr: float = 1e-4,
    device: str = "cpu",
    save_path: str = "dqn_weights.pth",
    best_save_path: str = "dqn_weights_best.pth",
    elite_fraction: float = 0.5,
    min_progress_threshold: float = 0.2,
    use_double_dqn: bool = True,     # NEW: Enable Double DQN
):
    # Load data with improved filtering
    transitions, state_dim, num_actions = load_transitions(
        log_dir=log_dir,
        elite_fraction=elite_fraction,
        min_progress_threshold=min_progress_threshold,
    )
    states, actions, rewards, next_states, dones = transitions_to_tensors(
        transitions, state_dim
    )

    dataset = TensorDataset(states, actions, rewards, next_states, dones)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    device = torch.device(device)
    model = DQN(state_dim, num_actions).to(device)
    target_model = DQN(state_dim, num_actions).to(device)
    target_model.load_state_dict(model.state_dict())

    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.SmoothL1Loss()  # Huber loss

    print(f"\n=== Training Configuration ===")
    print(f"Device: {device}")
    print(f"Architecture: {state_dim} -> 128 -> 128 -> {num_actions}")
    print(f"Dataset size: {len(dataset)}")
    print(f"Batch size: {batch_size}")
    print(f"Epochs: {num_epochs}")
    print(f"Learning rate: {lr}")
    print(f"Gamma: {gamma}")
    print(f"Double DQN: {use_double_dqn}")

    print(f"\n=== Dataset Statistics ===")
    print(f"Rewards: min={rewards.min():.3f}, max={rewards.max():.3f}, mean={rewards.mean():.3f}, std={rewards.std():.3f}")
    print(f"States: min={states.min():.3f}, max={states.max():.3f}")
    print(f"Actions distribution: {torch.bincount(actions)}")
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
            q_values = model(batch_states)
            q_sa = q_values.gather(1, batch_actions.unsqueeze(1)).squeeze(1)

            # Target computation
            with torch.no_grad():
                if use_double_dqn:
                    # Double DQN: use online network to select actions, target network to evaluate
                    next_actions = model(batch_next_states).argmax(dim=1)
                    max_next_q = target_model(batch_next_states).gather(1, next_actions.unsqueeze(1)).squeeze(1)
                else:
                    # Standard DQN: use target network for both selection and evaluation
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

        # Update target network every epoch
        target_model.load_state_dict(model.state_dict())

        # Save best checkpoint
        if avg_loss < best_loss:
            best_loss = avg_loss
            torch.save(
                {
                    "state_dim": state_dim,
                    "num_actions": num_actions,
                    "model_state_dict": model.state_dict(),
                    "epoch": epoch,
                    "loss": avg_loss,
                    "gamma": gamma,
                    "double_dqn": use_double_dqn,
                },
                best_save_path,
            )
            print(f"  → Saved new best model (loss: {avg_loss:.6f})")

    # Save final weights
    torch.save(
        {
            "state_dim": state_dim,
            "num_actions": num_actions,
            "model_state_dict": model.state_dict(),
            "epoch": num_epochs,
            "loss": avg_loss,
            "gamma": gamma,
            "double_dqn": use_double_dqn,
        },
        save_path,
    )
    
    print(f"\n=== Training Complete ===")
    print(f"Final model saved to: {save_path}")
    print(f"Best model saved to: {best_save_path} (loss: {best_loss:.6f})")
    print(f"\nNext steps:")
    print(f"1. Run: python export_weights.py")
    print(f"2. Copy the generated DqnWeights.lua to your Roblox project")
    print(f"3. Test the updated bot in Roblox")


if __name__ == "__main__":
    train_dqn()