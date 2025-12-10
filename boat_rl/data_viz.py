"""
analyze_dqn_training.py

Offline analysis + visualization for the Roblox boat DQN project.

Features:
- Load episode logs from `logs/transitions_*.json`
- Compute per-episode statistics (return, max progress, win flag)
- Plot:
    * Episode returns over time
    * Max progress over time
    * Rolling win rate
- Train a DQN (similar to train_dqn.py) while recording loss per epoch
- Plot loss vs epoch (optionally compare multiple hyper-parameter configs)

Dependencies:
    pip install numpy torch matplotlib
"""

import os
import glob
import json
from typing import List, Dict, Tuple

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import TensorDataset, DataLoader
import matplotlib.pyplot as plt

def load_episode_logs(log_dir: str = "logs") -> List[Dict]:
    """
    Load episodes from JSON logs written by log_data.py / Agent:onEpisodeEnd.

    Assumes each file looks like:
        {
            "episodeId": ...,
            "episodeNum": ...,
            "transitions": [
                {"s": [...], "a": int, "r": float, "ns": [...], "d": bool},
                ...
            ],
            "metadata": {...}
        }

    Returns:
        episodes: list of dicts, each with keys:
            - 'file', 'transitions', 'return', 'max_progress', 'win', 'length'
    """
    pattern = os.path.join(log_dir, "transitions_*.json")
    files = sorted(glob.glob(pattern))

    if not files:
        raise FileNotFoundError(f"No transition files found matching {pattern}")

    episodes: List[Dict] = []

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
        done_flag = False

        for t in transitions:
            r = float(t.get("r", 0.0))
            ep_return += r

            s = t.get("s", [])
            if s:
                max_progress = max(max_progress, float(s[0]))

            if t.get("d", False):
                done_flag = True

        win = done_flag and (max_progress >= 0.98)

        episodes.append(
            {
                "file": path,
                "transitions": transitions,
                "return": ep_return,
                "max_progress": max_progress,
                "win": win,
                "length": len(transitions),
            }
        )

    if not episodes:
        raise ValueError("Loaded log files but found no transitions in any episode.")

    print(f"Loaded {len(episodes)} episodes from {log_dir}")
    return episodes


def flatten_transitions(
    episodes: List[Dict],
    state_dim_expected: int = 11,
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, int]:
    """
    Flatten episode transitions into tensors for DQN training.

    Returns:
        states, actions, rewards, next_states, dones, num_actions
    """
    all_t: List[Dict] = []
    for ep in episodes:
        all_t.extend(ep["transitions"])

    if not all_t:
        raise ValueError("No transitions found in provided episodes.")

    first = all_t[0]
    state_dim = len(first["s"])
    num_actions = max(t["a"] for t in all_t)

    print(f"Inferred state_dim={state_dim}, num_actions={num_actions}")
    if state_dim != state_dim_expected:
        print(f"  WARNING: expected state_dim={state_dim_expected}, got {state_dim}")
    if num_actions != 5:
        print(f"  WARNING: expected num_actions=5, got {num_actions}")

    states, actions, rewards, next_states, dones = [], [], [], [], []

    for t in all_t:
        s = t["s"]
        a = t["a"]
        r = t["r"]
        ns = t["ns"]
        d = t["d"]

        if len(s) != state_dim or len(ns) != state_dim:
            raise ValueError(
                f"Inconsistent state dimension: expected {state_dim}, "
                f"got s={len(s)}, ns={len(ns)}"
            )

        states.append(s)
        actions.append(a - 1)
        rewards.append(r)
        next_states.append(ns)
        dones.append(1.0 if d else 0.0)

    states = torch.tensor(np.array(states), dtype=torch.float32)
    actions = torch.tensor(np.array(actions), dtype=torch.long)
    rewards = torch.tensor(np.array(rewards), dtype=torch.float32)
    next_states = torch.tensor(np.array(next_states), dtype=torch.float32)
    dones = torch.tensor(np.array(dones), dtype=torch.float32)

    print(f"Flattened {len(all_t)} transitions.")
    return states, actions, rewards, next_states, dones, num_actions

class DQN(nn.Module):
    """
    DQN architecture: state_dim -> 128 -> 128 -> num_actions
    """
    def __init__(self, state_dim: int, num_actions: int):
        super().__init__()

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

def train_dqn_with_history(
    states: torch.Tensor,
    actions: torch.Tensor,
    rewards: torch.Tensor,
    next_states: torch.Tensor,
    dones: torch.Tensor,
    num_actions: int,
    batch_size: int = 64,
    num_epochs: int = 10,
    gamma: float = 0.95,
    lr: float = 1e-4,
    device: str = "cpu",
    use_double_dqn: bool = True,
) -> Tuple[DQN, List[float]]:
    """
    Train a DQN and record average loss per epoch.

    Returns:
        model: trained DQN
        loss_history: list of avg loss per epoch
    """
    device = torch.device(device)
    state_dim = states.shape[1]

    dataset = TensorDataset(states, actions, rewards, next_states, dones)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    model = DQN(state_dim, num_actions).to(device)
    target_model = DQN(state_dim, num_actions).to(device)
    target_model.load_state_dict(model.state_dict())

    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.SmoothL1Loss()  # Huber loss

    print("\n=== Training Configuration ===")
    print(f"Device: {device}")
    print(f"Architecture: {state_dim} -> 128 -> 128 -> {num_actions}")
    print(f"Dataset size: {len(dataset)}")
    print(f"Batch size: {batch_size}")
    print(f"Epochs: {num_epochs}")
    print(f"Learning rate: {lr}")
    print(f"Gamma: {gamma}")
    print(f"Double DQN: {use_double_dqn}")
    print()

    model.train()
    target_model.eval()

    loss_history: List[float] = []

    for epoch in range(1, num_epochs + 1):
        epoch_loss = 0.0
        num_batches = 0

        for batch in dataloader:
            batch_states, batch_actions, batch_rewards, batch_next_states, batch_dones = [
                x.to(device) for x in batch
            ]

            q_values = model(batch_states)
            q_sa = q_values.gather(1, batch_actions.unsqueeze(1)).squeeze(1)

            with torch.no_grad():
                if use_double_dqn:
                    next_actions = model(batch_next_states).argmax(dim=1)
                    max_next_q = target_model(batch_next_states).gather(
                        1, next_actions.unsqueeze(1)
                    ).squeeze(1)
                else:
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
        loss_history.append(avg_loss)
        print(f"Epoch {epoch}/{num_epochs} - avg loss: {avg_loss:.6f}")

        target_model.load_state_dict(model.state_dict())

    return model, loss_history

def ensure_dir(path: str):
    if not os.path.exists(path):
        os.makedirs(path, exist_ok=True)


def plot_episode_returns(episodes: List[Dict], out_dir: str = "figures"):
    ensure_dir(out_dir)

    returns = [ep["return"] for ep in episodes]
    xs = np.arange(1, len(returns) + 1)

    plt.figure()
    plt.plot(xs, returns, marker="", linewidth=1)
    plt.xlabel("Episode")
    plt.ylabel("Return (sum of rewards)")
    plt.title("Episode Return Over Time")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    out_path = os.path.join(out_dir, "episode_returns.png")
    plt.savefig(out_path, dpi=200)
    plt.close()
    print(f"Saved {out_path}")


def plot_episode_max_progress(episodes: List[Dict], out_dir: str = "figures"):
    ensure_dir(out_dir)

    max_prog = [ep["max_progress"] for ep in episodes]
    xs = np.arange(1, len(max_prog) + 1)

    plt.figure()
    plt.plot(xs, max_prog, marker="", linewidth=1)
    plt.xlabel("Episode")
    plt.ylabel("Max normalized progress")
    plt.title("Max Progress Per Episode")
    plt.ylim(0.0, 1.05)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    out_path = os.path.join(out_dir, "episode_max_progress.png")
    plt.savefig(out_path, dpi=200)
    plt.close()
    print(f"Saved {out_path}")


def plot_rolling_win_rate(
    episodes: List[Dict],
    window: int = 10,
    out_dir: str = "figures",
):
    ensure_dir(out_dir)

    wins = np.array([1.0 if ep["win"] else 0.0 for ep in episodes], dtype=np.float32)
    xs = np.arange(1, len(wins) + 1)

    if len(wins) < window:
        window = max(1, len(wins))

    kernel = np.ones(window) / window
    rolling = np.convolve(wins, kernel, mode="same")

    plt.figure()
    plt.plot(xs, wins, ".", alpha=0.2, label="Win (raw)")
    plt.plot(xs, rolling, "-", linewidth=2, label=f"Rolling win rate (window={window})")
    plt.xlabel("Episode")
    plt.ylabel("Win rate")
    plt.title("Rolling Win Rate Over Episodes")
    plt.ylim(-0.05, 1.05)
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    out_path = os.path.join(out_dir, "episode_win_rate.png")
    plt.savefig(out_path, dpi=200)
    plt.close()
    print(f"Saved {out_path}")


def plot_loss_histories(
    histories: Dict[str, List[float]],
    out_dir: str = "figures",
):
    """
    histories: dict mapping legend_label -> loss_history_list
    """
    ensure_dir(out_dir)

    plt.figure()
    for label, losses in histories.items():
        xs = np.arange(1, len(losses) + 1)
        plt.plot(xs, losses, marker="o", linewidth=1.5, label=label)

    plt.xlabel("Epoch")
    plt.ylabel("Average training loss")
    plt.title("DQN Loss vs Epoch")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    out_path = os.path.join(out_dir, "dqn_loss_vs_epoch.png")
    plt.savefig(out_path, dpi=200)
    plt.close()
    print(f"Saved {out_path}")

def main():
    log_dir = "logs"
    out_dir = "figures"

    episodes = load_episode_logs(log_dir=log_dir)

    episode_returns = [ep["return"] for ep in episodes]
    max_prog = [ep["max_progress"] for ep in episodes]
    win_rate = sum(ep["win"] for ep in episodes) / len(episodes)

    print("\n=== Episode Summary ===")
    print(f"Num episodes: {len(episodes)}")
    print(f"Returns: min={min(episode_returns):.2f}, "
          f"median={np.median(episode_returns):.2f}, "
          f"max={max(episode_returns):.2f}")
    print(f"Max progress: min={min(max_prog):.2f}, "
          f"median={np.median(max_prog):.2f}, "
          f"max={max(max_prog):.2f}")
    print(f"Overall win rate: {win_rate*100:.1f}%")

    plot_episode_returns(episodes, out_dir=out_dir)
    plot_episode_max_progress(episodes, out_dir=out_dir)
    plot_rolling_win_rate(episodes, window=10, out_dir=out_dir)

    states, actions, rewards, next_states, dones, num_actions = flatten_transitions(
        episodes, state_dim_expected=11
    )

    histories = {}

    _, loss_hist_1 = train_dqn_with_history(
        states,
        actions,
        rewards,
        next_states,
        dones,
        num_actions=num_actions,
        batch_size=64,
        num_epochs=12,
        gamma=0.95,
        lr=1e-4,
        device="cpu",
        use_double_dqn=True,
    )
    histories["gamma=0.95, lr=1e-4"] = loss_hist_1

    _, loss_hist_2 = train_dqn_with_history(
        states,
        actions,
        rewards,
        next_states,
        dones,
        num_actions=num_actions,
        batch_size=64,
        num_epochs=12,
        gamma=0.99,
        lr=1e-4,
        device="cpu",
        use_double_dqn=True,
    )
    histories["gamma=0.99, lr=1e-4"] = loss_hist_2

    _, loss_hist_3 = train_dqn_with_history(
        states,
        actions,
        rewards,
        next_states,
        dones,
        num_actions=num_actions,
        batch_size=64,
        num_epochs=12,
        gamma=0.95,
        lr=5e-4,
        device="cpu",
        use_double_dqn=True,
    )
    histories["gamma=0.95, lr=5e-4"] = loss_hist_3

    plot_loss_histories(histories, out_dir=out_dir)


if __name__ == "__main__":
    main()