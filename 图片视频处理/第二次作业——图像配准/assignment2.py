from __future__ import annotations

import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
from skimage import feature, transform
from skimage.measure import ransac


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "outputs"


def load_image_rgb(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGB"), dtype=np.uint8)


def to_gray_float01(img_rgb: np.ndarray) -> np.ndarray:
    img = img_rgb.astype(np.float32)
    gray = 0.299 * img[..., 0] + 0.587 * img[..., 1] + 0.114 * img[..., 2]
    return gray / 255.0


def detect_and_match_points(
    fixed_gray: np.ndarray,
    moving_gray: np.ndarray,
    n_keypoints: int = 3000,
    fast_threshold: float = 0.07,
) -> tuple[np.ndarray, np.ndarray]:
    # ORB keypoints in (row, col); convert to (x, y) = (col, row) for homography.
    orb_fixed = feature.ORB(n_keypoints=n_keypoints, fast_threshold=fast_threshold)
    orb_moving = feature.ORB(n_keypoints=n_keypoints, fast_threshold=fast_threshold)
    orb_fixed.detect_and_extract(fixed_gray)
    orb_moving.detect_and_extract(moving_gray)

    matches = feature.match_descriptors(
        orb_fixed.descriptors,
        orb_moving.descriptors,
        cross_check=True,
        max_ratio=0.8,
    )
    if len(matches) < 7:
        raise RuntimeError(f"Matched points are not enough: {len(matches)} < 7")

    fixed_pts = np.fliplr(orb_fixed.keypoints[matches[:, 0]])
    moving_pts = np.fliplr(orb_moving.keypoints[matches[:, 1]])
    return fixed_pts, moving_pts


def ransac_filter(
    fixed_pts: np.ndarray,
    moving_pts: np.ndarray,
    residual_threshold: float = 3.0,
    max_trials: int = 5000,
) -> tuple[transform.ProjectiveTransform, np.ndarray]:
    model, inliers = ransac(
        (moving_pts, fixed_pts),
        transform.ProjectiveTransform,
        min_samples=4,
        residual_threshold=residual_threshold,
        max_trials=max_trials,
    )
    if inliers is None or int(inliers.sum()) < 7:
        raise RuntimeError("RANSAC inliers are not enough to sample 7 points.")
    return model, inliers


def estimate_h_with_random_7(
    fixed_inlier_pts: np.ndarray,
    moving_inlier_pts: np.ndarray,
    seed: int = 2026,
) -> tuple[np.ndarray, np.ndarray, float]:
    rng = np.random.default_rng(seed)
    n = len(fixed_inlier_pts)
    best_h = None
    best_idx = None
    best_rmse = math.inf

    # Try random subsets, keep the one with minimum inlier RMSE.
    for _ in range(400):
        idx = rng.choice(n, size=7, replace=False)
        m = transform.ProjectiveTransform()
        ok = m.estimate(moving_inlier_pts[idx], fixed_inlier_pts[idx])
        if not ok:
            continue

        pred = m(moving_inlier_pts)
        err = np.linalg.norm(pred - fixed_inlier_pts, axis=1)
        rmse = float(np.sqrt(np.mean(err**2)))
        if np.isfinite(rmse) and rmse < best_rmse:
            best_rmse = rmse
            best_idx = idx
            best_h = m.params.copy()

    if best_h is None or best_idx is None:
        raise RuntimeError("Failed to estimate homography from random 7-point subsets.")
    return best_h, best_idx, best_rmse


def warp_moving_to_fixed(
    moving_rgb: np.ndarray,
    h_moving_to_fixed: np.ndarray,
    output_shape_hw: tuple[int, int],
) -> np.ndarray:
    model = transform.ProjectiveTransform(h_moving_to_fixed)
    warped = transform.warp(
        moving_rgb,
        inverse_map=model.inverse,
        output_shape=output_shape_hw,
        preserve_range=True,
    )
    return np.clip(warped, 0, 255).astype(np.uint8)


def save_selected_points(
    path: Path,
    fixed_pts: np.ndarray,
    moving_pts: np.ndarray,
) -> None:
    lines = ["index,fixed_x,fixed_y,moving_x,moving_y"]
    for i, (pf, pm) in enumerate(zip(fixed_pts, moving_pts), start=1):
        lines.append(f"{i},{pf[0]:.3f},{pf[1]:.3f},{pm[0]:.3f},{pm[1]:.3f}")
    path.write_text("\n".join(lines), encoding="utf-8")


def save_homography(path: Path, h: np.ndarray, rmse: float, n_inliers: int, n_matches: int) -> None:
    lines = [
        "Homography H (mapping moving Image B -> fixed Image A):",
        np.array2string(h, precision=10, suppress_small=False),
        "",
        f"Inlier RMSE (evaluated on all RANSAC inliers): {rmse:.6f} pixels",
        f"RANSAC inliers: {n_inliers}",
        f"Raw matched pairs: {n_matches}",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def plot_selected_points(
    fixed_rgb: np.ndarray,
    moving_rgb: np.ndarray,
    fixed_pts7: np.ndarray,
    moving_pts7: np.ndarray,
    out_png: Path,
) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(16, 7))
    axes[0].imshow(fixed_rgb)
    axes[0].set_title("Image A (Fixed) - 7 points")
    axes[1].imshow(moving_rgb)
    axes[1].set_title("Image B (Moving) - 7 points")
    for i, (pf, pm) in enumerate(zip(fixed_pts7, moving_pts7), start=1):
        # High-contrast markers: red ring + white center
        axes[0].scatter(
            pf[0], pf[1], s=220, facecolors="none", edgecolors="red", linewidths=2.4, zorder=3
        )
        axes[0].scatter(pf[0], pf[1], s=28, c="white", edgecolors="black", linewidths=0.6, zorder=4)
        axes[0].text(
            pf[0] + 14,
            pf[1] - 12,
            str(i),
            color="white",
            fontsize=11,
            weight="bold",
            bbox=dict(facecolor="black", edgecolor="white", boxstyle="round,pad=0.18", alpha=0.85),
            zorder=5,
        )

        axes[1].scatter(
            pm[0], pm[1], s=220, facecolors="none", edgecolors="red", linewidths=2.4, zorder=3
        )
        axes[1].scatter(pm[0], pm[1], s=28, c="white", edgecolors="black", linewidths=0.6, zorder=4)
        axes[1].text(
            pm[0] + 14,
            pm[1] - 12,
            str(i),
            color="white",
            fontsize=11,
            weight="bold",
            bbox=dict(facecolor="black", edgecolor="white", boxstyle="round,pad=0.18", alpha=0.85),
            zorder=5,
        )
    for ax in axes:
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_png, dpi=260)
    plt.close(fig)


def plot_registration_results(
    fixed_rgb: np.ndarray,
    warped_moving_rgb: np.ndarray,
    out_overlay_png: Path,
    out_diff_png: Path,
) -> None:
    overlay = np.clip(
        0.5 * fixed_rgb.astype(np.float32) + 0.5 * warped_moving_rgb.astype(np.float32),
        0,
        255,
    ).astype(np.uint8)
    Image.fromarray(overlay).save(out_overlay_png)

    diff = np.mean(
        np.abs(fixed_rgb.astype(np.float32) - warped_moving_rgb.astype(np.float32)),
        axis=2,
    )
    fig = plt.figure(figsize=(8, 6))
    plt.imshow(diff, cmap="inferno")
    plt.title("Absolute Difference Heatmap (A vs warped B)")
    plt.colorbar(fraction=0.046, pad=0.04)
    plt.axis("off")
    plt.tight_layout()
    fig.savefig(out_diff_png, dpi=180)
    plt.close(fig)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    fixed_path = ROOT / "Image A.jpg"
    moving_path = ROOT / "Image B.jpg"

    fixed_rgb = load_image_rgb(fixed_path)
    moving_rgb = load_image_rgb(moving_path)
    fixed_gray = to_gray_float01(fixed_rgb)
    moving_gray = to_gray_float01(moving_rgb)

    fixed_pts, moving_pts = detect_and_match_points(fixed_gray, moving_gray)
    _, inliers = ransac_filter(fixed_pts, moving_pts)
    fixed_inlier_pts = fixed_pts[inliers]
    moving_inlier_pts = moving_pts[inliers]

    h, idx7, rmse = estimate_h_with_random_7(fixed_inlier_pts, moving_inlier_pts, seed=2026)
    fixed_pts7 = fixed_inlier_pts[idx7]
    moving_pts7 = moving_inlier_pts[idx7]

    warped = warp_moving_to_fixed(moving_rgb, h, fixed_rgb.shape[:2])

    Image.fromarray(warped).save(OUT_DIR / "registered_B_to_A.png")
    plot_selected_points(
        fixed_rgb,
        moving_rgb,
        fixed_pts7,
        moving_pts7,
        OUT_DIR / "selected_7_points.png",
    )
    plot_registration_results(
        fixed_rgb,
        warped,
        OUT_DIR / "overlay_A_and_registered_B.png",
        OUT_DIR / "difference_heatmap.png",
    )
    save_selected_points(OUT_DIR / "selected_7_points.csv", fixed_pts7, moving_pts7)
    save_homography(
        OUT_DIR / "homography_H.txt",
        h,
        rmse,
        int(inliers.sum()),
        len(fixed_pts),
    )

    print("Done.")
    print(f"Raw matches: {len(fixed_pts)}")
    print(f"RANSAC inliers: {int(inliers.sum())}")
    print(f"RMSE on inliers: {rmse:.6f} px")
    print("Outputs:", OUT_DIR)


if __name__ == "__main__":
    main()
