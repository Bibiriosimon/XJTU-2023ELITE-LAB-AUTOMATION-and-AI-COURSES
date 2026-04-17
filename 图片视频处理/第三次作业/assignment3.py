from __future__ import annotations

import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from PIL import Image
from skimage import exposure, filters
from skimage.filters.rank import equalize as rank_equalize
from skimage.morphology import footprint_rectangle


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "outputs"


def list_bmp_files(root: Path) -> list[Path]:
    files = [p for p in root.iterdir() if p.is_file() and p.suffix.lower() == ".bmp"]
    return sorted(files, key=lambda p: p.name.lower())


def read_gray_u8(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("L"), dtype=np.uint8)


def save_gray_u8(arr: np.ndarray, path: Path) -> None:
    Image.fromarray(arr.astype(np.uint8)).save(path)


def hist_entropy(img_u8: np.ndarray) -> float:
    hist = np.bincount(img_u8.ravel(), minlength=256).astype(np.float64)
    p = hist / hist.sum()
    p = p[p > 0]
    return float(-(p * np.log2(p)).sum())


def render_img_and_hist(img_u8: np.ndarray, title: str, out_png: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    axes[0].imshow(img_u8, cmap="gray", vmin=0, vmax=255)
    axes[0].set_title(title)
    axes[0].axis("off")

    axes[1].hist(img_u8.ravel(), bins=256, range=(0, 255), color="steelblue")
    axes[1].set_title(f"Histogram: {title}")
    axes[1].set_xlabel("Gray Level")
    axes[1].set_ylabel("Pixel Count")
    axes[1].grid(alpha=0.2)

    fig.tight_layout()
    fig.savefig(out_png, dpi=180)
    plt.close(fig)


def task1_draw_histograms(images: dict[str, np.ndarray], out_dir: Path) -> None:
    tdir = out_dir / "task1_histograms"
    tdir.mkdir(parents=True, exist_ok=True)
    for name, img in images.items():
        render_img_and_hist(img, name, tdir / f"{name}_img_hist.png")


def equalize_global(img_u8: np.ndarray) -> np.ndarray:
    out = exposure.equalize_hist(img_u8)
    return np.clip(np.round(out * 255.0), 0, 255).astype(np.uint8)


def task2_equalization(images: dict[str, np.ndarray], out_dir: Path) -> pd.DataFrame:
    tdir = out_dir / "task2_equalization"
    tdir.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []
    for name, img in images.items():
        eq = equalize_global(img)
        save_gray_u8(eq, tdir / f"{name}_equalized.png")

        fig, axes = plt.subplots(2, 2, figsize=(12, 8))
        axes[0, 0].imshow(img, cmap="gray", vmin=0, vmax=255)
        axes[0, 0].set_title(f"Original: {name}")
        axes[0, 0].axis("off")
        axes[0, 1].imshow(eq, cmap="gray", vmin=0, vmax=255)
        axes[0, 1].set_title(f"Equalized: {name}")
        axes[0, 1].axis("off")
        axes[1, 0].hist(img.ravel(), bins=256, range=(0, 255), color="tab:blue", alpha=0.9)
        axes[1, 0].set_title("Original Histogram")
        axes[1, 1].hist(eq.ravel(), bins=256, range=(0, 255), color="tab:orange", alpha=0.9)
        axes[1, 1].set_title("Equalized Histogram")
        for ax in axes[1]:
            ax.set_xlabel("Gray Level")
            ax.set_ylabel("Pixel Count")
            ax.grid(alpha=0.2)
        fig.tight_layout()
        fig.savefig(tdir / f"{name}_comparison.png", dpi=170)
        plt.close(fig)

        rows.append(
            {
                "image": name,
                "orig_mean": float(img.mean()),
                "orig_std": float(img.std()),
                "orig_entropy": hist_entropy(img),
                "eq_mean": float(eq.mean()),
                "eq_std": float(eq.std()),
                "eq_entropy": hist_entropy(eq),
            }
        )

    df = pd.DataFrame(rows).sort_values("image")
    df.to_csv(tdir / "equalization_metrics.csv", index=False, encoding="utf-8-sig")
    return df


def guess_base_name(name: str, available: set[str]) -> str | None:
    stem = Path(name).stem
    m = re.match(r"^(.*?)(\d+)$", stem)
    if not m:
        return None
    base_stem = m.group(1)
    for candidate in (f"{base_stem}.bmp", f"{base_stem}.BMP"):
        if candidate in available:
            return candidate
    return None


def task3_hist_match(images: dict[str, np.ndarray], out_dir: Path) -> pd.DataFrame:
    tdir = out_dir / "task3_hist_matching"
    tdir.mkdir(parents=True, exist_ok=True)

    available = set(images.keys())
    rows: list[dict] = []

    for src_name, src in images.items():
        base_name = guess_base_name(src_name, available)
        if base_name is None:
            continue
        ref = images[base_name]
        matched = exposure.match_histograms(src, ref, channel_axis=None)
        matched_u8 = np.clip(np.round(matched), 0, 255).astype(np.uint8)
        save_gray_u8(matched_u8, tdir / f"{Path(src_name).stem}_matched_to_{Path(base_name).stem}.png")

        fig, axes = plt.subplots(2, 3, figsize=(14, 8))
        axes[0, 0].imshow(src, cmap="gray", vmin=0, vmax=255)
        axes[0, 0].set_title(f"Source: {src_name}")
        axes[0, 1].imshow(ref, cmap="gray", vmin=0, vmax=255)
        axes[0, 1].set_title(f"Reference: {base_name}")
        axes[0, 2].imshow(matched_u8, cmap="gray", vmin=0, vmax=255)
        axes[0, 2].set_title("Matched Output")
        for ax in axes[0]:
            ax.axis("off")

        axes[1, 0].hist(src.ravel(), bins=256, range=(0, 255), color="tab:blue")
        axes[1, 0].set_title("Source Histogram")
        axes[1, 1].hist(ref.ravel(), bins=256, range=(0, 255), color="tab:green")
        axes[1, 1].set_title("Reference Histogram")
        axes[1, 2].hist(matched_u8.ravel(), bins=256, range=(0, 255), color="tab:orange")
        axes[1, 2].set_title("Matched Histogram")
        for ax in axes[1]:
            ax.set_xlabel("Gray Level")
            ax.set_ylabel("Pixel Count")
            ax.grid(alpha=0.2)

        fig.tight_layout()
        fig.savefig(tdir / f"{Path(src_name).stem}_to_{Path(base_name).stem}_comparison.png", dpi=170)
        plt.close(fig)

        rows.append(
            {
                "source": src_name,
                "reference": base_name,
                "source_mean": float(src.mean()),
                "matched_mean": float(matched_u8.mean()),
                "reference_mean": float(ref.mean()),
                "source_std": float(src.std()),
                "matched_std": float(matched_u8.std()),
                "reference_std": float(ref.std()),
            }
        )

    df = pd.DataFrame(rows).sort_values(["reference", "source"])
    df.to_csv(tdir / "hist_match_metrics.csv", index=False, encoding="utf-8-sig")
    return df


def local_hist_7x7(img_u8: np.ndarray) -> np.ndarray:
    return rank_equalize(img_u8, footprint=footprint_rectangle((7, 7)))


def task4_local_enhance(images: dict[str, np.ndarray], out_dir: Path) -> pd.DataFrame:
    tdir = out_dir / "task4_local_7x7"
    tdir.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []
    for name in ("elain.bmp", "lena.bmp"):
        if name not in images:
            continue
        src = images[name]
        out = local_hist_7x7(src)
        save_gray_u8(out, tdir / f"{Path(name).stem}_local7x7.png")

        fig, axes = plt.subplots(1, 2, figsize=(10, 4))
        axes[0].imshow(src, cmap="gray", vmin=0, vmax=255)
        axes[0].set_title(f"Original: {name}")
        axes[0].axis("off")
        axes[1].imshow(out, cmap="gray", vmin=0, vmax=255)
        axes[1].set_title("Local Histogram Equalization (7x7)")
        axes[1].axis("off")
        fig.tight_layout()
        fig.savefig(tdir / f"{Path(name).stem}_local7x7_compare.png", dpi=170)
        plt.close(fig)

        rows.append(
            {
                "image": name,
                "orig_mean": float(src.mean()),
                "orig_std": float(src.std()),
                "orig_entropy": hist_entropy(src),
                "local_mean": float(out.mean()),
                "local_std": float(out.std()),
                "local_entropy": hist_entropy(out),
            }
        )

    df = pd.DataFrame(rows)
    df.to_csv(tdir / "local7x7_metrics.csv", index=False, encoding="utf-8-sig")
    return df


def task5_hist_segmentation(images: dict[str, np.ndarray], out_dir: Path) -> pd.DataFrame:
    tdir = out_dir / "task5_segmentation"
    tdir.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []

    # elain: binary segmentation by Otsu threshold.
    if "elain.bmp" in images:
        img = images["elain.bmp"]
        th = filters.threshold_otsu(img)
        mask = (img >= th).astype(np.uint8) * 255
        save_gray_u8(mask, tdir / "elain_otsu_mask.png")

        fig, axes = plt.subplots(1, 3, figsize=(14, 4))
        axes[0].imshow(img, cmap="gray", vmin=0, vmax=255)
        axes[0].set_title("elain.bmp")
        axes[0].axis("off")
        axes[1].hist(img.ravel(), bins=256, range=(0, 255), color="tab:blue")
        axes[1].axvline(th, color="red", linewidth=2, label=f"Otsu={th:.1f}")
        axes[1].set_title("Histogram + Otsu Threshold")
        axes[1].legend()
        axes[2].imshow(mask, cmap="gray", vmin=0, vmax=255)
        axes[2].set_title("Binary Segmentation")
        axes[2].axis("off")
        fig.tight_layout()
        fig.savefig(tdir / "elain_segmentation_overview.png", dpi=180)
        plt.close(fig)

        rows.append(
            {
                "image": "elain.bmp",
                "method": "Otsu(binary)",
                "threshold_1": float(th),
                "threshold_2": np.nan,
                "foreground_ratio": float((mask > 0).mean()),
            }
        )

    # woman: multi-level segmentation by Multi-Otsu.
    woman_name = "woman.BMP" if "woman.BMP" in images else ("woman.bmp" if "woman.bmp" in images else None)
    if woman_name is not None:
        img = images[woman_name]
        ths = filters.threshold_multiotsu(img, classes=3)
        seg = np.digitize(img, bins=ths).astype(np.uint8)  # 0/1/2
        seg_vis = (seg * 127).astype(np.uint8)
        save_gray_u8(seg_vis, tdir / "woman_multiotsu_3class.png")

        fig, axes = plt.subplots(1, 3, figsize=(15, 5))
        axes[0].imshow(img, cmap="gray", vmin=0, vmax=255)
        axes[0].set_title(woman_name)
        axes[0].axis("off")
        axes[1].hist(img.ravel(), bins=256, range=(0, 255), color="tab:green")
        axes[1].axvline(ths[0], color="red", linewidth=2, label=f"T1={ths[0]:.1f}")
        axes[1].axvline(ths[1], color="orange", linewidth=2, label=f"T2={ths[1]:.1f}")
        axes[1].set_title("Histogram + Multi-Otsu Thresholds")
        axes[1].legend()
        axes[2].imshow(seg, cmap="viridis", vmin=0, vmax=2)
        axes[2].set_title("3-Class Segmentation")
        axes[2].axis("off")
        fig.tight_layout()
        fig.savefig(tdir / "woman_segmentation_overview.png", dpi=180)
        plt.close(fig)

        rows.append(
            {
                "image": woman_name,
                "method": "Multi-Otsu(3 classes)",
                "threshold_1": float(ths[0]),
                "threshold_2": float(ths[1]),
                "foreground_ratio": float((seg == 2).mean()),
            }
        )

    df = pd.DataFrame(rows)
    df.to_csv(tdir / "segmentation_metrics.csv", index=False, encoding="utf-8-sig")
    return df


def write_summary_report(
    out_dir: Path,
    eq_df: pd.DataFrame,
    match_df: pd.DataFrame,
    local_df: pd.DataFrame,
    seg_df: pd.DataFrame,
) -> None:
    lines: list[str] = []
    lines.append("第三次作业结果摘要")
    lines.append("")
    lines.append("任务1：所有BMP图像直方图已输出到 outputs/task1_histograms")
    lines.append("任务2：所有BMP图像全局直方图均衡已输出到 outputs/task2_equalization")
    lines.append("任务3：编号图像按同名前缀匹配到原图，结果输出到 outputs/task3_hist_matching")
    lines.append("任务4：elain/lena 7x7局部直方图增强输出到 outputs/task4_local_7x7")
    lines.append("任务5：elain/woman 直方图分割输出到 outputs/task5_segmentation")
    lines.append("")

    lines.append("任务2（均衡）统计：")
    for _, r in eq_df.iterrows():
        lines.append(
            f"- {r['image']}: std {r['orig_std']:.3f} -> {r['eq_std']:.3f}, "
            f"entropy {r['orig_entropy']:.3f} -> {r['eq_entropy']:.3f}"
        )
    lines.append("")

    lines.append("任务3（直方图匹配）统计：")
    for _, r in match_df.iterrows():
        lines.append(
            f"- {r['source']} -> {r['reference']}: mean {r['source_mean']:.3f} -> {r['matched_mean']:.3f} "
            f"(ref {r['reference_mean']:.3f})"
        )
    lines.append("")

    lines.append("任务4（7x7局部增强）统计：")
    for _, r in local_df.iterrows():
        lines.append(
            f"- {r['image']}: std {r['orig_std']:.3f} -> {r['local_std']:.3f}, "
            f"entropy {r['orig_entropy']:.3f} -> {r['local_entropy']:.3f}"
        )
    lines.append("")

    lines.append("任务5（分割）统计：")
    for _, r in seg_df.iterrows():
        if pd.isna(r["threshold_2"]):
            lines.append(
                f"- {r['image']} [{r['method']}]: T={r['threshold_1']:.3f}, foreground_ratio={r['foreground_ratio']:.4f}"
            )
        else:
            lines.append(
                f"- {r['image']} [{r['method']}]: T1={r['threshold_1']:.3f}, T2={r['threshold_2']:.3f}, "
                f"high_class_ratio={r['foreground_ratio']:.4f}"
            )

    (out_dir / "summary_report.txt").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    bmp_files = list_bmp_files(ROOT)
    images = {p.name: read_gray_u8(p) for p in bmp_files}
    print(f"Loaded {len(images)} BMP images.")

    task1_draw_histograms(images, OUT_DIR)
    print("Task1 done.")

    eq_df = task2_equalization(images, OUT_DIR)
    print("Task2 done.")

    match_df = task3_hist_match(images, OUT_DIR)
    print("Task3 done.")

    local_df = task4_local_enhance(images, OUT_DIR)
    print("Task4 done.")

    seg_df = task5_hist_segmentation(images, OUT_DIR)
    print("Task5 done.")

    write_summary_report(OUT_DIR, eq_df, match_df, local_df, seg_df)
    print("All done. Outputs:", OUT_DIR)


if __name__ == "__main__":
    main()
