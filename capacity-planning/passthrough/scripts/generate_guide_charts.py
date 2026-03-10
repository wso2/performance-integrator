"""
Generate the three charts embedded in docs/CapacityGuide.md:

  docs/images/max_throughput.png   — bar chart: max achievable RPS by payload size
  docs/images/response_times.png   — line chart: avg & p99 response times by payload size
  docs/images/resource_heatmap.png — heatmap: recommended CPU/memory config per
                                     (payload size × target RPS) combination

Usage:
    python generate_guide_charts.py

Output is written relative to the script's location:
    ../docs/images/
"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from matplotlib.colors import ListedColormap, BoundaryNorm

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(SCRIPT_DIR, "..", "..", "..", "docs", "capacity-planning", "passthrough", "images")

# ---------------------------------------------------------------------------
# Style
# ---------------------------------------------------------------------------
BLUE   = "#005DAA"
ORANGE = "#FF7300"

plt.rcParams.update({
    "font.family": "sans-serif",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
})

# ---------------------------------------------------------------------------
# Shared data
# ---------------------------------------------------------------------------
PAYLOAD_LABELS = ["1 KB", "10 KB", "50 KB", "100 KB", "250 KB", "1 MB"]

# ---------------------------------------------------------------------------
# Chart 1: Maximum achievable throughput by payload size
# ---------------------------------------------------------------------------
def make_max_throughput():
    max_rps = [5000, 2000, 2000, 500, 200, 100]

    fig, ax = plt.subplots(figsize=(9, 5))
    bars = ax.bar(PAYLOAD_LABELS, max_rps, color=BLUE, width=0.55, zorder=3)

    ax.set_title("Maximum Achievable Throughput by Payload Size",
                 fontsize=14, fontweight="bold", pad=14)
    ax.set_xlabel("Payload Size", fontsize=11)
    ax.set_ylabel("Max Throughput (RPS)", fontsize=11)
    ax.yaxis.grid(True, linestyle="--", alpha=0.5, zorder=0)
    ax.set_ylim(0, 5800)

    for bar, val in zip(bars, max_rps):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 90,
            f"{val:,}",
            ha="center", va="bottom", fontsize=10, color="#333",
        )

    plt.tight_layout()
    out = os.path.join(OUT, "max_throughput.png")
    plt.savefig(out, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"Saved: {out}")


# ---------------------------------------------------------------------------
# Chart 2: Response time by payload size (avg and p99 with range bands)
# ---------------------------------------------------------------------------
def make_response_times():
    # Measured ranges (min, max) across concurrency levels 10–500 users
    avg_lo = [ 74,  73,  88,  95, 100, 265]
    avg_hi = [ 84, 116, 228, 295, 374, 702]
    p99_lo = [ 80,  83, 216, 280, 340, 602]
    p99_hi = [160, 192, 340, 429, 572, 966]

    mid_avg = [(l + h) / 2 for l, h in zip(avg_lo, avg_hi)]
    mid_p99 = [(l + h) / 2 for l, h in zip(p99_lo, p99_hi)]
    x = np.arange(len(PAYLOAD_LABELS))

    fig, ax = plt.subplots(figsize=(9, 5))

    # Shaded range bands
    ax.fill_between(x, avg_lo, avg_hi, alpha=0.18, color=BLUE)
    ax.fill_between(x, p99_lo, p99_hi, alpha=0.18, color=ORANGE)

    # Midpoint lines
    ax.plot(x, mid_avg, "o-",  color=BLUE,   linewidth=2.2, markersize=6,
            label="Avg (range midpoint)")
    ax.plot(x, mid_p99, "s--", color=ORANGE, linewidth=2.2, markersize=6,
            label="p99 (range midpoint)")

    ax.set_title("Response Time by Payload Size",
                 fontsize=14, fontweight="bold", pad=14)
    ax.set_xlabel("Payload Size", fontsize=11)
    ax.set_ylabel("Response Time (ms)", fontsize=11)
    ax.set_xticks(x)
    ax.set_xticklabels(PAYLOAD_LABELS)
    ax.yaxis.grid(True, linestyle="--", alpha=0.5)

    # Combined legend: lines + shaded-band patches
    avg_patch = mpatches.Patch(color=BLUE,   alpha=0.35, label="Avg range")
    p99_patch = mpatches.Patch(color=ORANGE, alpha=0.35, label="p99 range")
    handles, labels = ax.get_legend_handles_labels()
    ax.legend(
        handles=handles + [avg_patch, p99_patch],
        labels=labels + ["Avg range", "p99 range"],
        fontsize=9, ncol=2,
    )

    plt.tight_layout()
    out = os.path.join(OUT, "response_times.png")
    plt.savefig(out, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"Saved: {out}")


# ---------------------------------------------------------------------------
# Chart 3: Recommended resource configuration heatmap
# ---------------------------------------------------------------------------
def make_resource_heatmap():
    # Cell encoding:
    #   0 = Not achievable (N/A)
    #   1 = 0.2 vCPU / 512 MB
    #   2 = 0.5 vCPU / 1 GB
    #   3 = 1.0 vCPU / 1 GB
    #
    # Rows: payload sizes (1 KB → 1 MB)
    # Cols: target RPS   (50, 100, 200, 500, 1 000, 2 000, 5 000)
    rps_labels = ["50", "100", "200", "500", "1 000", "2 000", "5 000"]
    matrix = np.array([
        [1, 1, 2, 2, 2, 2, 2],  # 1 KB  — 1000 RPS: 1.0→0.5 vCPU (analysis says ≥0.5 sufficient)
        [1, 1, 2, 2, 2, 2, 0],  # 10 KB — 1000 RPS: 1.0→0.5 vCPU (same reason)
        [1, 1, 2, 3, 3, 2, 0],  # 50 KB — 1000 RPS: N/A→1.0 vCPU (achievable if 2000 RPS is)
        [1, 1, 2, 3, 0, 0, 0],  # 100 KB
        [1, 2, 2, 0, 0, 0, 0],  # 250 KB
        [2, 3, 0, 0, 0, 0, 0],  # 1 MB
    ])

    cell_text = {
        0: "N/A",
        1: "0.2 vCPU\n512 MB",
        2: "0.5 vCPU\n1 GB",
        3: "1.0 vCPU\n1 GB",
    }

    # Colors: red for N/A, green scale for resource tiers
    cmap_colors = ["#FECACA", "#D1FAE5", "#86EFAC", "#22C55E"]
    cmap = ListedColormap(cmap_colors)
    norm = BoundaryNorm([-0.5, 0.5, 1.5, 2.5, 3.5], cmap.N)

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.imshow(matrix, cmap=cmap, norm=norm, aspect="auto")

    ax.set_xticks(np.arange(len(rps_labels)))
    ax.set_yticks(np.arange(len(PAYLOAD_LABELS)))
    ax.set_xticklabels(rps_labels, fontsize=11)
    ax.set_yticklabels(PAYLOAD_LABELS, fontsize=11)
    ax.set_xlabel("Target Throughput (RPS)", fontsize=12, labelpad=10)
    ax.set_ylabel("Payload Size", fontsize=12)
    ax.set_title(
        "Recommended Resource Configuration\n(CPU / Memory per replica)",
        fontsize=14, fontweight="bold", pad=14,
    )

    # Annotate each cell
    for r in range(matrix.shape[0]):
        for c in range(matrix.shape[1]):
            val = matrix[r, c]
            color = "#B91C1C" if val == 0 else "#111"
            weight = "normal"
            ax.text(c, r, cell_text[val],
                    ha="center", va="center",
                    fontsize=8.5, color=color, fontweight=weight)

    # Legend
    legend_patches = [
        mpatches.Patch(color="#FECACA", label="Not achievable"),
        mpatches.Patch(color="#D1FAE5", label="0.2 vCPU / 512 MB"),
        mpatches.Patch(color="#86EFAC", label="0.5 vCPU / 1 GB"),
        mpatches.Patch(color="#22C55E", label="1.0 vCPU / 1 GB"),
    ]
    ax.legend(
        handles=legend_patches,
        loc="lower right",
        bbox_to_anchor=(1.0, -0.28),
        ncol=4, fontsize=9,
        frameon=True, edgecolor="#ccc",
    )

    plt.tight_layout()
    out = os.path.join(OUT, "resource_heatmap.png")
    plt.savefig(out, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"Saved: {out}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_max_throughput()
    make_response_times()
    make_resource_heatmap()
    print("All guide charts generated successfully.")
