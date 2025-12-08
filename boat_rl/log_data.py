from flask import Flask, request
import json, time, os

app = Flask(__name__)

os.makedirs("logs", exist_ok=True)

@app.post("/transitions")
def save_transitions():
    # print("Request received")
    data = request.get_json(silent=True)
    # print("Raw data:", data)

    if not data or "transitions" not in data:
        print("ERROR: Missing 'transitions' key")
        return "bad request", 400

    existing = [f for f in os.listdir("logs")
                if f.startswith("transitions_") and f.endswith(".json")]
    next_idx = len(existing) + 1
    fname = os.path.join("logs", f"transitions_{next_idx:03d}.json")

    with open(fname, "w") as f:
        json.dump(data["transitions"], f)

    # print("Saved", fname)
    return "ok"


if __name__ == "__main__":
    app.run(port=5000, debug=True)
