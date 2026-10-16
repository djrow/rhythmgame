import os
import sys
import json

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from tests.e2e.e2e_test_utils import ChartValidator

# Let's inspect the 3 ground truth charts vs our generated output format
for piece in ["piece_1_monophonic", "piece_2_harmony", "piece_3_polyphonic"]:
    chart_path = os.path.join(PROJECT_ROOT, "assets", "charts", f"{piece}.json")
    with open(chart_path, "r", encoding="utf-8") as f:
        chart = json.load(f)
    valid, msg = ChartValidator.validate_chart_dict(chart)
    print(f"Validating {piece}: {valid} ({msg})")
    assert valid, f"Failed on {piece}: {msg}"

print("All charts pass ChartValidator!")
