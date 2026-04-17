from __future__ import annotations

import csv
import logging
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import exposure, feature
import tifffile


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "outputs"
logging.getLogger("tifffile").setLevel(logging.ERROR)


def read_gray_image(path: Path) -> np.ndarray:
    suffix = path.suffix.lower()
    if suffix in {".bmp", ".pgm"}:
        return np.array(Image.open(path).convert("L"), dtype=np.uint8)
    if suffix in {".tif", ".tiff"}:
        arr = tifffile.imread(str(path))
        arr = np.asarray(arr)
        if arr.ndim == 3:
            # test4.tif contains a valid grayscale image in channel 0 and a broken extra channel.
            arr = arr[:, :, 0]
        if arr.dtype != np.uint8:
            arr = np.clip(arr, 0, 255).astype(np.uint8)
        return arr
    raise ValueError(f"Unsupported image format: {path.name}")


def ensure_u8(arr: np.ndarray) -> np.ndarray:
    return np.clip(np.round(arr), 0, 255).astype(np.uint8)


def gaussian_kernel(size: int, sigma: float = 1.5) -> np.ndarray:
    radius = size // 2
    y, x = np.mgrid[-radius : radius + 1, -radius : radius + 1]
    kernel = np.exp(-(x**2 + y**2) / (2 * sigma**2))
    kernel /= kernel.sum()
    return kernel


def gaussian_filter_manual(img: np.ndarray, size: int, sigma: float = 1.5) -> np.ndarray:
    kernel = gaussian_kernel(size, sigma)
    filtered = ndimage.convolve(img.astype(np.float32), kernel, mode="reflect")
    return ensure_u8(filtered)


def median_filter(img: np.ndarray, size: int) -> np.ndarray:
    filtered = ndimage.median_filter(img, size=size, mode="reflect")
    return ensure_u8(filtered)


def sobel_magnitude(img: np.ndarray) -> np.ndarray:
    img_f = img.astype(np.float32)
    gx = ndimage.sobel(img_f, axis=1, mode="reflect")
    gy = ndimage.sobel(img_f, axis=0, mode="reflect")
    mag = np.hypot(gx, gy)
    mag = exposure.rescale_intensity(mag, out_range=(0, 255))
    return mag.astype(np.uint8)


def laplace_abs(img: np.ndarray) -> np.ndarray:
    img_f = img.astype(np.float32)
    lap = ndimage.laplace(img_f, mode="reflect")
    lap = np.abs(lap)
    lap = exposure.rescale_intensity(lap, out_range=(0, 255))
    return lap.astype(np.uint8)


def unsharp_mask(img: np.ndarray, sigma: float = 1.5, amount: float = 1.5) -> np.ndarray:
    blurred = ndimage.gaussian_filter(img.astype(np.float32), sigma=sigma, mode="reflect")
    sharpened = img.astype(np.float32) + amount * (img.astype(np.float32) - blurred)
    return ensure_u8(sharpened)


def canny_edges(img: np.ndarray, sigma: float = 1.2) -> np.ndarray:
    edges = feature.canny(img.astype(np.float32) / 255.0, sigma=sigma)
    return (edges.astype(np.uint8) * 255)


def laplacian_variance(img: np.ndarray) -> float:
    lap = ndimage.laplace(img.astype(np.float32), mode="reflect")
    return float(lap.var())


def gradient_mean(img: np.ndarray) -> float:
    gx = ndimage.sobel(img.astype(np.float32), axis=1, mode="reflect")
    gy = ndimage.sobel(img.astype(np.float32), axis=0, mode="reflect")
    return float(np.mean(np.hypot(gx, gy)))


def save_gray(arr: np.ndarray, path: Path) -> None:
    Image.fromarray(ensure_u8(arr)).save(path)


def plot_kernel(kernel: np.ndarray, title: str, out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(3.4, 3.2))
    im = ax.imshow(kernel, cmap="viridis")
    ax.set_title(title)
    for i in range(kernel.shape[0]):
        for j in range(kernel.shape[1]):
            ax.text(j, i, f"{kernel[i, j]:.3f}", ha="center", va="center", color="white", fontsize=8)
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.tight_layout()
    fig.savefig(out_path, dpi=200)
    plt.close(fig)


def plot_lowpass_overview(
    original: np.ndarray,
    gaussian_results: dict[int, np.ndarray],
    median_results: dict[int, np.ndarray],
    title_prefix: str,
    out_path: Path,
) -> None:
    fig, axes = plt.subplots(2, 4, figsize=(16, 8))
    axes[0, 0].imshow(original, cmap="gray", vmin=0, vmax=255)
    axes[0, 0].set_title(f"{title_prefix}\nOriginal")
    axes[1, 0].axis("off")

    for idx, k in enumerate((3, 5, 7), start=1):
        axes[0, idx].imshow(gaussian_results[k], cmap="gray", vmin=0, vmax=255)
        axes[0, idx].set_title(f"Gaussian {k}x{k}")
        axes[1, idx].imshow(median_results[k], cmap="gray", vmin=0, vmax=255)
        axes[1, idx].set_title(f"Median {k}x{k}")

    for ax in axes.ravel():
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def plot_highpass_overview(original: np.ndarray, results: dict[str, np.ndarray], title: str, out_path: Path) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(13, 8))
    axes[0, 0].imshow(original, cmap="gray", vmin=0, vmax=255)
    axes[0, 0].set_title(f"{title}\nOriginal")
    method_order = ["unsharp", "sobel", "laplace", "canny"]
    positions = [(0, 1), (0, 2), (1, 0), (1, 1)]
    for method, pos in zip(method_order, positions):
        ax = axes[pos]
        ax.imshow(results[method], cmap="gray", vmin=0, vmax=255)
        ax.set_title(method.capitalize())
    axes[1, 2].axis("off")
    for ax in axes.ravel():
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def task_lowpass(images: dict[str, np.ndarray], out_dir: Path) -> list[dict]:
    tdir = out_dir / "task_lowpass"
    tdir.mkdir(parents=True, exist_ok=True)

    sigma = 1.5
    metric_rows: list[dict] = []

    for k in (3, 5, 7):
        plot_kernel(gaussian_kernel(k, sigma), f"Gaussian Kernel {k}x{k}\nσ={sigma}", tdir / f"gaussian_kernel_{k}x{k}.png")

    for name in ("test1.pgm", "test2.tif"):
        img = images[name]
        gaussian_results = {k: gaussian_filter_manual(img, k, sigma=sigma) for k in (3, 5, 7)}
        median_results = {k: median_filter(img, k) for k in (3, 5, 7)}

        plot_lowpass_overview(img, gaussian_results, median_results, name, tdir / f"{Path(name).stem}_lowpass_overview.png")

        for method, result_map in (("gaussian", gaussian_results), ("median", median_results)):
            for k, out in result_map.items():
                save_gray(out, tdir / f"{Path(name).stem}_{method}_{k}x{k}.png")
                metric_rows.append(
                    {
                        "image": name,
                        "method": method,
                        "kernel_size": f"{k}x{k}",
                        "sigma": sigma if method == "gaussian" else "",
                        "mean": float(out.mean()),
                        "std": float(out.std()),
                        "gradient_mean": gradient_mean(out),
                        "laplacian_var": laplacian_variance(out),
                    }
                )

        metric_rows.append(
            {
                "image": name,
                "method": "original",
                "kernel_size": "-",
                "sigma": "",
                "mean": float(img.mean()),
                "std": float(img.std()),
                "gradient_mean": gradient_mean(img),
                "laplacian_var": laplacian_variance(img),
            }
        )

    write_csv(
        tdir / "lowpass_metrics.csv",
        metric_rows,
        ["image", "method", "kernel_size", "sigma", "mean", "std", "gradient_mean", "laplacian_var"],
    )
    return metric_rows


def task_highpass(images: dict[str, np.ndarray], out_dir: Path) -> list[dict]:
    tdir = out_dir / "task_highpass"
    tdir.mkdir(parents=True, exist_ok=True)

    metric_rows: list[dict] = []

    for name in ("test3_corrupt.pgm", "test4.tif"):
        img = images[name]
        results = {
            "unsharp": unsharp_mask(img, sigma=1.5, amount=1.5),
            "sobel": sobel_magnitude(img),
            "laplace": laplace_abs(img),
            "canny": canny_edges(img, sigma=1.2),
        }

        plot_highpass_overview(img, results, name, tdir / f"{Path(name).stem}_highpass_overview.png")

        for method, out in results.items():
            save_gray(out, tdir / f"{Path(name).stem}_{method}.png")
            row = {
                "image": name,
                "method": method,
                "mean": float(out.mean()),
                "std": float(out.std()),
                "gradient_mean": gradient_mean(out),
                "laplacian_var": laplacian_variance(out),
                "edge_ratio": "",
            }
            if method == "canny":
                row["edge_ratio"] = float((out > 0).mean())
            metric_rows.append(row)

        metric_rows.append(
            {
                "image": name,
                "method": "original",
                "mean": float(img.mean()),
                "std": float(img.std()),
                "gradient_mean": gradient_mean(img),
                "laplacian_var": laplacian_variance(img),
                "edge_ratio": "",
            }
        )

    write_csv(
        tdir / "highpass_metrics.csv",
        metric_rows,
        ["image", "method", "mean", "std", "gradient_mean", "laplacian_var", "edge_ratio"],
    )
    return metric_rows


def write_explanation_doc(lowpass_rows: list[dict], highpass_rows: list[dict], out_path: Path) -> None:
    def find_row(rows: list[dict], image: str, method: str, kernel: str | None = None) -> dict:
        for row in rows:
            if row["image"] == image and row["method"] == method and (kernel is None or row.get("kernel_size") == kernel):
                return row
        raise KeyError((image, method, kernel))

    lines: list[str] = []
    lines.append("# 第四次作业讲解文档")
    lines.append("")
    lines.append("## 一、题目理解")
    lines.append("")
    lines.append("本次作业分为两大部分：")
    lines.append("1. 对 `test1.pgm` 和 `test2.tif` 做空域低通滤波，分别比较高斯滤波器和中值滤波器，在 `3x3 / 5x5 / 7x7` 模板下的平滑效果。")
    lines.append("2. 对 `test3_corrupt.pgm` 和 `test4.tif` 做高通或边缘增强处理，包括 `unsharp masking`、`Sobel`、`Laplace` 和 `Canny`。")
    lines.append("")
    lines.append("其中高斯滤波器按题目要求固定 `sigma = 1.5`，并显式生成不同尺寸的高斯核。")
    lines.append("")
    lines.append("## 二、实现思路")
    lines.append("")
    lines.append("### 1. 低通滤波部分")
    lines.append("")
    lines.append("- 高斯滤波：自己生成二维高斯核，再用卷积实现。")
    lines.append("- 中值滤波：直接在局部窗口内取中值，对脉冲噪声更鲁棒。")
    lines.append("- 对每张图都输出一张总览图：原图、Gaussian 3/5/7、Median 3/5/7。")
    lines.append("- 为了便于分析，还统计了 `std`、`gradient_mean` 和 `laplacian_var`：")
    lines.append("  - `std` 反映整体灰度分散程度；")
    lines.append("  - `gradient_mean` 越小，通常说明图像越平滑；")
    lines.append("  - `laplacian_var` 越小，通常说明高频细节被抑制得越明显。")
    lines.append("")
    lines.append("### 2. 高通/边缘部分")
    lines.append("")
    lines.append("- `Unsharp masking`：原图减去模糊图得到细节，再加回去实现锐化。")
    lines.append("- `Sobel`：计算一阶梯度，突出边缘强度。")
    lines.append("- `Laplace`：计算二阶导，更敏感于细小边缘，但也更容易放大噪声。")
    lines.append("- `Canny`：更完整的边缘检测流程，边缘通常最细、最连续。")
    lines.append("")
    lines.append("## 三、实验中需要重点观察什么")
    lines.append("")
    lines.append("### 1. 高斯滤波 vs 中值滤波")
    lines.append("")
    lines.append("- 高斯滤波更适合抑制高斯型随机噪声，结果更自然，但边缘会逐渐变软。")
    lines.append("- 中值滤波对椒盐噪声更有效，能保边缘，但窗口太大时也会造成块状或纹理损失。")
    lines.append("- 模板从 `3x3` 增大到 `7x7` 时，平滑更强，但细节损失也更大。")
    lines.append("")
    lines.append("### 2. 四种高通方法怎么写优缺点")
    lines.append("")
    lines.append("- `Unsharp masking`：更像“增强图像”，结果仍保留原始外观；适合锐化，不适合直接拿来做二值边缘图。")
    lines.append("- `Sobel`：实现简单，边缘明显；但边缘通常比较粗，对噪声敏感。")
    lines.append("- `Laplace`：对细节变化非常敏感，轮廓强化明显；但噪声也容易被放大。")
    lines.append("- `Canny`：边缘细、连续性好、抗噪性更好；缺点是参数更多、流程更复杂。")
    lines.append("")
    lines.append("## 四、结果解读")
    lines.append("")

    for image in ("test1.pgm", "test2.tif"):
        orig = find_row(lowpass_rows, image, "original")
        g3 = find_row(lowpass_rows, image, "gaussian", "3x3")
        g7 = find_row(lowpass_rows, image, "gaussian", "7x7")
        m3 = find_row(lowpass_rows, image, "median", "3x3")
        m7 = find_row(lowpass_rows, image, "median", "7x7")
        lines.append(f"### 低通滤波：{image}")
        lines.append("")
        lines.append(
            f"- 原图 `gradient_mean={orig['gradient_mean']:.3f}`，`laplacian_var={orig['laplacian_var']:.3f}`。"
        )
        lines.append(
            f"- Gaussian 3x3 降到 `gradient_mean={g3['gradient_mean']:.3f}`，Gaussian 7x7 进一步降到 `{g7['gradient_mean']:.3f}`，说明窗口越大平滑越强。"
        )
        lines.append(
            f"- Median 3x3 为 `gradient_mean={m3['gradient_mean']:.3f}`，Median 7x7 为 `{m7['gradient_mean']:.3f}`，同样表现出随窗口增大而更强的平滑效果。"
        )
        lines.append(
            "- 写报告时可以强调：Gaussian 输出更柔和，中值滤波更偏向去除突发噪声并保持较硬的边缘。"
        )
        lines.append("")

    for image in ("test3_corrupt.pgm", "test4.tif"):
        orig = find_row(highpass_rows, image, "original")
        unsharp = find_row(highpass_rows, image, "unsharp")
        sobel = find_row(highpass_rows, image, "sobel")
        laplace = find_row(highpass_rows, image, "laplace")
        canny = find_row(highpass_rows, image, "canny")
        lines.append(f"### 高通/边缘：{image}")
        lines.append("")
        lines.append(
            f"- 原图 `laplacian_var={orig['laplacian_var']:.3f}`；Unsharp 后变为 `{unsharp['laplacian_var']:.3f}`，说明锐化增强了高频细节。"
        )
        lines.append(
            f"- Sobel 输出 `mean={sobel['mean']:.3f}`，适合观察边缘强度分布；Laplace 输出 `mean={laplace['mean']:.3f}`，对细小轮廓更敏感。"
        )
        lines.append(
            f"- Canny 的边缘像素占比约为 `{float(canny['edge_ratio']):.4f}`，可以用来说明它提取的是较稀疏、较干净的边缘。"
        )
        lines.append(
            "- 写报告时可以强调：Unsharp 是增强图像细节，Sobel/Laplace/Canny 更偏向提取边缘信息，其中 Canny 通常边缘最细、最连续。"
        )
        lines.append("")

    lines.append("## 五、最后写报告时的结论建议")
    lines.append("")
    lines.append("1. 低通滤波中，模板越大，平滑越明显，但模糊也越强。")
    lines.append("2. 高斯滤波适合连续型噪声；中值滤波适合脉冲噪声。")
    lines.append("3. Unsharp masking 适合锐化；Sobel/Laplace/Canny 更适合边缘检测。")
    lines.append("4. Canny 在边缘连续性和抗噪方面通常优于 Sobel 和 Laplace，但实现复杂度更高。")
    lines.append("")
    lines.append("## 六、结果文件位置")
    lines.append("")
    lines.append("- 低通滤波：`outputs/task_lowpass/`")
    lines.append("- 高通与边缘：`outputs/task_highpass/`")
    lines.append("- 指标汇总：`outputs/task_lowpass/lowpass_metrics.csv`、`outputs/task_highpass/highpass_metrics.csv`")

    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    images = {
        "test1.pgm": read_gray_image(ROOT / "test1.pgm"),
        "test2.tif": read_gray_image(ROOT / "test2.tif"),
        "test3_corrupt.pgm": read_gray_image(ROOT / "test3_corrupt.pgm"),
        "test4.tif": read_gray_image(ROOT / "test4.tif"),
        "test4 copy.bmp": read_gray_image(ROOT / "test4 copy.bmp"),
    }

    lowpass_rows = task_lowpass(images, OUT_DIR)
    highpass_rows = task_highpass(images, OUT_DIR)
    write_explanation_doc(lowpass_rows, highpass_rows, ROOT / "第四次作业讲解文档.md")

    print("Done.")
    print(f"Lowpass outputs: {OUT_DIR / 'task_lowpass'}")
    print(f"Highpass outputs: {OUT_DIR / 'task_highpass'}")


if __name__ == "__main__":
    main()
