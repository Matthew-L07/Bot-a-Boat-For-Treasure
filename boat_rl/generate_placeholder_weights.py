# generate_placeholder_weights.py
#
# Generate a random placeholder DQN with the same architecture as train_dqn.py:
#   state_dim -> 128 -> 128 -> num_actions
#
# This is useful when you change the state_dim (e.g., add more rays) and want
# a dimension-consistent DqnWeights.lua before you have real trained weights.

import json
from pathlib import Path

import numpy as np

BASE_DIR = Path(__file__).resolve().parent

# ---- Configure these to match your Lua Config / Env ----
STATE_DIM = 11      # progress, lateral, heading, velocities, 5 rays
NUM_ACTIONS = 5     # FORWARD, F_LEFT, F_RIGHT, SHARP_LEFT, SHARP_RIGHT
HIDDEN1 = 128
HIDDEN2 = 128

# Output paths (match export_weights.py)
JSON_PATH = BASE_DIR / "dqn_weights.json"
LUA_PATH = BASE_DIR.parent / "src" / "ai" / "navigation" / "DqnWeights.lua"


def generate_placeholder_weights(
    state_dim: int,
    num_actions: int,
    hidden1: int,
    hidden2: int,
    seed: int = 42,
):
    rng = np.random.default_rng(seed)

    # Layer 1: Linear(state_dim, hidden1)
    W1 = rng.normal(loc=0.0, scale=0.1, size=(hidden1, state_dim)).astype("float32")
    b1 = np.zeros(hidden1, dtype="float32")

    # Layer 2: Linear(hidden1, hidden2)
    W2 = rng.normal(loc=0.0, scale=0.1, size=(hidden2, hidden1)).astype("float32")
    b2 = np.zeros(hidden2, dtype="float32")

    # Layer 3: Linear(hidden2, num_actions)
    W3 = rng.normal(loc=0.0, scale=0.1, size=(num_actions, hidden2)).astype("float32")
    b3 = np.zeros(num_actions, dtype="float32")

    weights_obj = {
        "state_dim": state_dim,
        "num_actions": num_actions,
        "layers": [
            {"W": W1.tolist(), "b": b1.tolist()},
            {"W": W2.tolist(), "b": b2.tolist()},
            {"W": W3.tolist(), "b": b3.tolist()},
        ],
    }

    return weights_obj


def export_to_lua(weights_obj, json_path: Path, lua_path: Path):
    # Save JSON (optional but handy for debugging)
    json_text = json.dumps(weights_obj, indent=2)
    json_path.write_text(json_text)
    print(f"Saved JSON placeholder weights to {json_path}")

    # Minified JSON for embedding in Lua
    minified_json = json.dumps(weights_obj, separators=(",", ":"))

    lua_code = f"""local HttpService = game:GetService("HttpService")

-- AUTO-GENERATED placeholder DQN weights by generate_placeholder_weights.py.
-- Model: {weights_obj['state_dim']}-dim state, {weights_obj['num_actions']} actions
-- Architecture: {weights_obj['state_dim']} -> {HIDDEN1} -> {HIDDEN2} -> {weights_obj['num_actions']}

local json = [=[{minified_json}]=]

local Weights = HttpService:JSONDecode(json)

return Weights
"""

    lua_path.parent.mkdir(parents=True, exist_ok=True)
    lua_path.write_text(lua_code)
    print(f"Exported placeholder Lua weights to {lua_path}")
    size_kb = lua_path.stat().st_size / 1024
    print(f"Lua file size: {size_kb:.1f} KB")


def main():
    print(
        f"Generating placeholder DQN weights: "
        f"state_dim={STATE_DIM}, num_actions={NUM_ACTIONS}, "
        f"hidden={HIDDEN1},{HIDDEN2}"
    )
    weights_obj = generate_placeholder_weights(
        STATE_DIM, NUM_ACTIONS, HIDDEN1, HIDDEN2
    )
    export_to_lua(weights_obj, JSON_PATH, LUA_PATH)

    print("\nDone. You can now use these placeholder weights in Roblox.")
    print("Later, run train_dqn.py + export_weights.py to overwrite with trained weights.")


if __name__ == "__main__":
    main()
