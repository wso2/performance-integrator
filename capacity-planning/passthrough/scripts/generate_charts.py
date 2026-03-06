"""
Generate 10 performance report charts for the integrator capacity planning.
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.colors import ListedColormap, BoundaryNorm

# ---------------------------------------------------------------------------
# Global style
# ---------------------------------------------------------------------------
plt.rcParams.update({
    'font.family': 'DejaVu Sans',
    'axes.spines.top': False,
    'axes.spines.right': False,
    'figure.facecolor': 'white',
    'axes.facecolor': 'white',
    'axes.grid': True,
    'grid.alpha': 0.4,
    'axes.axisbelow': True,
})

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CONFIGS  = ["0.2vCPU/512MB", "0.5vCPU/1GB", "1vCPU/1GB", "2vCPU/1GB"]
USERS    = [10, 50, 100, 200, 500]
PAYLOADS = ["1KB", "10KB", "50KB", "100KB", "250KB", "1MB"]
NA   = 'N/A'
DASH = '-'

OUTPUT_DIR = "/Users/tharmigan/Documents/github/TharmiganK/integrator-performance/capacity-planning/passthrough/reports/images/"

# Payloads tested per RPS
TESTED_PAYLOADS = {
    50:   PAYLOADS,          # all 6
    100:  PAYLOADS,          # all 6
    200:  PAYLOADS,          # all 6
    500:  PAYLOADS,          # all 6
    1000: PAYLOADS[:5],      # first 5 (no 1MB)
    2000: PAYLOADS[:5],      # first 5 (no 1MB)
    5000: PAYLOADS[:4],      # first 4 (no 250KB, 1MB)
}

# ---------------------------------------------------------------------------
# Data builders
# ---------------------------------------------------------------------------
def build_data():
    """
    Returns data[rps][users][payload][config] = replica count (int, NA, or DASH)
    """
    data = {}

    # ---- 50 RPS ----
    rps = 50
    data[rps] = {}
    for u in USERS:
        data[rps][u] = {}
        for p in PAYLOADS:
            data[rps][u][p] = {}
            for c in CONFIGS:
                if p == "1MB" and u == 10:
                    data[rps][u][p][c] = NA
                elif p == "1MB" and u in [50, 100, 200, 500] and c == "0.2vCPU/512MB":
                    data[rps][u][p][c] = 2
                else:
                    data[rps][u][p][c] = 1

    # ---- 100 RPS ----
    rps = 100
    data[rps] = {}
    for u in USERS:
        data[rps][u] = {}
        for p in PAYLOADS:
            data[rps][u][p] = {}
            for c in CONFIGS:
                if p in ["1KB", "10KB", "50KB", "100KB"]:
                    data[rps][u][p][c] = 1
                elif p == "250KB":
                    if u == 10:
                        data[rps][u][p][c] = NA
                    elif u in [50, 100, 200, 500]:
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 2
                        else:
                            data[rps][u][p][c] = 1
                elif p == "1MB":
                    if u == 10:
                        data[rps][u][p][c] = NA
                    elif u in [50, 100, 200, 500]:
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 4
                        elif c == "0.5vCPU/1GB":
                            data[rps][u][p][c] = 2
                        else:  # 1vCPU/1GB, 2vCPU/1GB
                            data[rps][u][p][c] = 1

    # ---- 200 RPS ----
    rps = 200
    data[rps] = {}
    for u in USERS:
        data[rps][u] = {}
        for p in PAYLOADS:
            data[rps][u][p] = {}
            for c in CONFIGS:
                if u == 10:
                    data[rps][u][p][c] = NA
                elif p == "1MB":
                    data[rps][u][p][c] = NA
                elif p in ["1KB", "10KB", "50KB"]:
                    data[rps][u][p][c] = 1
                elif p == "100KB":
                    if u in [50, 100, 200]:
                        data[rps][u][p][c] = 1
                    else:  # 500 users
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 2
                        else:
                            data[rps][u][p][c] = 1
                elif p == "250KB":
                    if c == "0.2vCPU/512MB":
                        data[rps][u][p][c] = 3
                    else:
                        data[rps][u][p][c] = 1

    # ---- 500 RPS ----
    rps = 500
    data[rps] = {}
    for u in USERS:
        data[rps][u] = {}
        for p in PAYLOADS:
            data[rps][u][p] = {}
            for c in CONFIGS:
                if u == 10:
                    data[rps][u][p][c] = NA
                elif p in ["250KB", "1MB"]:
                    data[rps][u][p][c] = NA
                elif p == "1KB":
                    if u == 50:
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = NA
                        else:
                            data[rps][u][p][c] = 1
                    else:  # 100-500 users
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 2
                        else:
                            data[rps][u][p][c] = 1
                elif p == "10KB":
                    if c == "0.2vCPU/512MB":
                        data[rps][u][p][c] = 2
                    else:
                        data[rps][u][p][c] = 1
                elif p == "50KB":
                    if c == "0.2vCPU/512MB":
                        data[rps][u][p][c] = 3
                    elif c == "0.5vCPU/1GB":
                        data[rps][u][p][c] = 2
                    else:
                        data[rps][u][p][c] = 1
                elif p == "100KB":
                    if u == 50:
                        data[rps][u][p][c] = NA
                    else:  # 100-500 users
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 4
                        elif c == "0.5vCPU/1GB":
                            data[rps][u][p][c] = 2
                        else:
                            data[rps][u][p][c] = 1

    # ---- 1000 RPS ----
    rps = 1000
    data[rps] = {}
    for u in USERS:
        data[rps][u] = {}
        for p in PAYLOADS:
            data[rps][u][p] = {}
            for c in CONFIGS:
                if p == "1MB":
                    data[rps][u][p][c] = DASH
                elif p in ["50KB", "100KB", "250KB"]:
                    data[rps][u][p][c] = NA
                elif p == "1KB":
                    if u in [10, 50]:
                        data[rps][u][p][c] = NA
                    else:  # 100-500 users
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 3
                        else:
                            data[rps][u][p][c] = 1
                elif p == "10KB":
                    if u in [10, 50, 100]:
                        data[rps][u][p][c] = NA
                    else:  # 200-500 users
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 3
                        else:
                            data[rps][u][p][c] = 1

    # ---- 2000 RPS ----
    rps = 2000
    data[rps] = {}
    for u in USERS:
        data[rps][u] = {}
        for p in PAYLOADS:
            data[rps][u][p] = {}
            for c in CONFIGS:
                if p == "1MB":
                    data[rps][u][p][c] = DASH
                elif u in [10, 50, 100]:
                    data[rps][u][p][c] = NA
                elif u == 200:
                    if p == "1KB":
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 3
                        else:
                            data[rps][u][p][c] = 1
                    else:
                        data[rps][u][p][c] = NA
                elif u == 500:
                    if p == "1KB":
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 3
                        else:
                            data[rps][u][p][c] = 1
                    elif p in ["10KB", "50KB"]:
                        data[rps][u][p][c] = 1
                    else:  # 100KB, 250KB
                        data[rps][u][p][c] = NA

    # ---- 5000 RPS ----
    rps = 5000
    data[rps] = {}
    for u in USERS:
        data[rps][u] = {}
        for p in PAYLOADS:
            data[rps][u][p] = {}
            for c in CONFIGS:
                if p in ["250KB", "1MB"]:
                    data[rps][u][p][c] = DASH
                elif u in [10, 50, 100, 200]:
                    data[rps][u][p][c] = NA
                elif u == 500:
                    if p == "1KB":
                        if c == "0.2vCPU/512MB":
                            data[rps][u][p][c] = 3
                        else:
                            data[rps][u][p][c] = 1
                    else:  # 10KB, 50KB, 100KB
                        data[rps][u][p][c] = NA

    return data


# ---------------------------------------------------------------------------
# Helper: encode a value for bar height
# ---------------------------------------------------------------------------
def bar_height(v):
    if v in (NA, DASH):
        return 0.08
    return float(v)


# ---------------------------------------------------------------------------
# Images 1–7: Grouped bar charts (one per RPS)
# ---------------------------------------------------------------------------
def make_bar_chart(rps, data, img_num):
    tested = TESTED_PAYLOADS[rps]
    n = len(tested)
    bar_width = 0.12
    offsets = (np.arange(n) - (n - 1) / 2) * bar_width
    tab10 = plt.cm.tab10.colors

    user_subplots = [50, 100, 200, 500]
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()

    for ax_idx, u in enumerate(user_subplots):
        ax = axes[ax_idx]
        x = np.arange(len(CONFIGS))

        for p_idx, p in enumerate(tested):
            heights = []
            for c in CONFIGS:
                v = data[rps][u][p][c]
                heights.append(bar_height(v))

            color = tab10[p_idx % 10]
            ax.bar(
                x + offsets[p_idx],
                heights,
                width=bar_width,
                color=color,
                label=p,
                zorder=3,
            )

        ax.set_ylim(0, 6)
        ax.set_xticks(x)
        ax.set_xticklabels(CONFIGS, fontsize=9)
        ax.set_xlabel("Component Configuration", fontsize=10)
        ax.set_ylabel("Minimum Required Replicas", fontsize=10)
        ax.set_title(f"{u} Concurrent Users", fontsize=11)
        ax.legend(
            title="Payload Size",
            fontsize=8,
            title_fontsize=8,
            loc="upper right",
        )

    fig.suptitle(
        f"Minimum Required Replicas to Achieve {rps} RPS Throughput\n"
        "(N/A = Latency limited - cannot achieve target throughput)",
        fontweight='bold',
        fontsize=13,
    )
    fig.tight_layout(rect=[0, 0, 1, 0.93])

    out = f"{OUTPUT_DIR}image{img_num}.png"
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f"Saved: {out}")


# ---------------------------------------------------------------------------
# Image 8: Heatmap
# ---------------------------------------------------------------------------
def make_heatmap(data, img_num):
    rps_list = [50, 100, 200, 500, 1000]
    u = 100

    # Encoding: 1→1, 2→2, 3→3, 4→4, NA→5, DASH→6
    def encode(v):
        if v == NA:
            return 5
        if v == DASH:
            return 6
        return int(v)

    def cell_text(v):
        if v == NA:
            return "N/A"
        if v == DASH:
            return "\u2013"
        return str(v)

    # Build colormap
    blues = plt.cm.Blues([0.2, 0.4, 0.65, 0.9])
    na_color   = np.array([0.75, 0.75, 0.75, 1.0])
    dash_color = np.array([0.9,  0.9,  0.9,  1.0])
    cmap_colors = list(blues) + [na_color, dash_color]
    cmap = ListedColormap(cmap_colors)
    bounds = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5]
    norm = BoundaryNorm(bounds, cmap.N)

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()
    subplot_titles = [
        "Config 1: 0.2vCPU/512MB",
        "Config 2: 0.5vCPU/1GB",
        "Config 3: 1vCPU/1GB",
        "Config 4: 2vCPU/1GB",
    ]

    for ax_idx, c in enumerate(CONFIGS):
        ax = axes[ax_idx]

        # Build matrix: rows=payloads (top=index 0), cols=rps
        matrix = np.zeros((len(PAYLOADS), len(rps_list)))
        text_matrix = []
        for row_i, p in enumerate(PAYLOADS):
            row_text = []
            for col_j, r in enumerate(rps_list):
                v = data[r][u][p][c]
                matrix[row_i, col_j] = encode(v)
                row_text.append(cell_text(v))
            text_matrix.append(row_text)

        im = ax.imshow(matrix, cmap=cmap, norm=norm, aspect='auto')

        # Cell annotations
        for row_i in range(len(PAYLOADS)):
            for col_j in range(len(rps_list)):
                val = matrix[row_i, col_j]
                txt = text_matrix[row_i][col_j]
                color = 'white' if val >= 3 else 'black'
                ax.text(col_j, row_i, txt, ha='center', va='center',
                        fontsize=9, color=color, fontweight='bold')

        ax.set_xticks(range(len(rps_list)))
        ax.set_xticklabels([str(r) for r in rps_list], fontsize=9)
        ax.set_yticks(range(len(PAYLOADS)))
        ax.set_yticklabels(PAYLOADS, fontsize=9)
        ax.set_xlabel("Target Throughput (RPS)", fontsize=10)
        ax.set_title(subplot_titles[ax_idx], fontsize=11, fontweight='bold')
        # Turn off grid for heatmap
        ax.grid(False)

    fig.suptitle(
        "Minimum Replicas Required (100 Users)\n"
        "N/A = Latency limited (cannot achieve throughput)",
        fontweight='bold',
        fontsize=13,
    )
    fig.tight_layout(rect=[0, 0, 1, 0.93])

    out = f"{OUTPUT_DIR}image{img_num}.png"
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f"Saved: {out}")


# ---------------------------------------------------------------------------
# Image 9: Line charts — payload impact
# ---------------------------------------------------------------------------
def make_line_chart(data, img_num):
    u = 100
    rps_subplots = [50, 100, 200, 500]
    viridis_colors = plt.cm.viridis([0, 0.33, 0.67, 1.0])

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    axes = axes.flatten()

    x_pos = np.arange(len(PAYLOADS))

    for ax_idx, rps in enumerate(rps_subplots):
        ax = axes[ax_idx]
        tested = TESTED_PAYLOADS[rps]

        for c_idx, c in enumerate(CONFIGS):
            y_vals = []
            for p in PAYLOADS:
                if p not in tested:
                    y_vals.append(np.nan)
                    continue
                v = data[rps][u][p][c]
                if v in (NA, DASH):
                    y_vals.append(np.nan)
                else:
                    y_vals.append(float(v))

            ax.plot(
                x_pos,
                y_vals,
                'o-',
                color=viridis_colors[c_idx],
                linewidth=2,
                markersize=6,
                label=c,
            )

        ax.set_ylim(0, 5)
        ax.set_xticks(x_pos)
        ax.set_xticklabels(PAYLOADS, fontsize=9)
        ax.set_xlabel("Payload Size", fontsize=10)
        ax.set_ylabel("Minimum Replicas", fontsize=10)
        ax.set_title(f"{rps} RPS", fontsize=11)
        ax.legend(fontsize=8, loc='upper left')

    fig.suptitle(
        "Impact of Payload Size on Minimum Replica Requirements (100 Users)",
        fontweight='bold',
        fontsize=13,
    )
    fig.tight_layout(rect=[0, 0, 1, 0.95])

    out = f"{OUTPUT_DIR}image{img_num}.png"
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f"Saved: {out}")


# ---------------------------------------------------------------------------
# Image 10: Concurrent users bar chart
# ---------------------------------------------------------------------------
def make_users_bar_chart(img_num):
    c = "0.5vCPU/1GB"
    p = "10KB"
    rps_list = [50, 100, 200, 500]
    n = len(rps_list)
    bar_width = 0.18
    offsets = (np.arange(n) - (n - 1) / 2) * bar_width
    tab10 = plt.cm.tab10.colors

    fig, ax = plt.subplots(figsize=(12, 5))
    x = np.arange(len(USERS))

    for r_idx, rps in enumerate(rps_list):
        heights = []
        for u in USERS:
            # Treat NA as 1.0 per spec
            heights.append(1.0)

        ax.bar(
            x + offsets[r_idx],
            heights,
            width=bar_width,
            color=tab10[r_idx],
            label=f"{rps} RPS",
            zorder=3,
        )

    ax.set_ylim(0, 1.2)
    ax.set_xticks(x)
    ax.set_xticklabels([str(u) for u in USERS])
    ax.set_xlabel("Concurrent Users", fontsize=11)
    ax.set_ylabel("Minimum Replicas", fontsize=11)
    ax.set_title(
        "Impact of Concurrent Users on Replica Requirements\n"
        "(0.5 CPU/1GB Configuration, 10KB Payload)",
        fontsize=12,
    )
    ax.legend(fontsize=9)

    out = f"{OUTPUT_DIR}image{img_num}.png"
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f"Saved: {out}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import os
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    data = build_data()

    # Images 1–7: one per RPS in order
    rps_order = [50, 100, 200, 500, 1000, 2000, 5000]
    for img_num, rps in enumerate(rps_order, start=1):
        make_bar_chart(rps, data, img_num)

    # Image 8: Heatmap
    make_heatmap(data, 8)

    # Image 9: Line charts
    make_line_chart(data, 9)

    # Image 10: Concurrent users
    make_users_bar_chart(10)

    print("All 10 images generated successfully.")
