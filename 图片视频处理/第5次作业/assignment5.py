from __future__ import annotations

import csv
import logging
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import exposure
import tifffile


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "outputs"
logging.getLogger("tifffile").setLevel(logging.ERROR)


LOWPASS_CONFIG = {
    "test1.pgm": {"radius": 25, "order": 2},
    "test2.tif": {"radius": 50, "order": 2},
}

HIGHPASS_CONFIG = {
    "test3_corrupt.pgm": {"radius": 10, "order": 2},
    "test4.tif": {"radius": 30, "order": 2},
}


def read_gray_image(path: Path) -> np.ndarray:
    suffix = path.suffix.lower()
    if suffix in {".bmp", ".pgm"}:
        return np.array(Image.open(path).convert("L"), dtype=np.uint8)
    if suffix in {".tif", ".tiff"}:
        arr = tifffile.imread(str(path))
        arr = np.asarray(arr)
        if arr.ndim == 3:
            arr = arr[:, :, 0]
        return np.clip(arr, 0, 255).astype(np.uint8)
    raise ValueError(f"Unsupported image format: {path.name}")


def save_gray(arr: np.ndarray, path: Path) -> None:
    Image.fromarray(np.clip(np.round(arr), 0, 255).astype(np.uint8)).save(path)


def fft2_shift(img: np.ndarray) -> np.ndarray:
    return np.fft.fftshift(np.fft.fft2(img.astype(np.float32)))


def ifft2_shift(F_shift: np.ndarray) -> np.ndarray:
    return np.fft.ifft2(np.fft.ifftshift(F_shift))


def distance_grid(shape: tuple[int, int]) -> np.ndarray:
    h, w = shape
    y, x = np.indices((h, w))
    cy, cx = h // 2, w // 2
    return np.sqrt((y - cy) ** 2 + (x - cx) ** 2)


def gaussian_lowpass(shape: tuple[int, int], d0: float) -> np.ndarray:
    D = distance_grid(shape)
    return np.exp(-(D**2) / (2 * (d0**2)))


def butterworth_lowpass(shape: tuple[int, int], d0: float, n: int = 2) -> np.ndarray:
    D = distance_grid(shape)
    D = np.maximum(D, 1e-8)
    return 1.0 / (1.0 + (D / d0) ** (2 * n))


def gaussian_highpass(shape: tuple[int, int], d0: float) -> np.ndarray:
    return 1.0 - gaussian_lowpass(shape, d0)


def butterworth_highpass(shape: tuple[int, int], d0: float, n: int = 2) -> np.ndarray:
    return 1.0 - butterworth_lowpass(shape, d0, n=n)


def normalized_log_spectrum(F_shift: np.ndarray) -> np.ndarray:
    mag = np.log1p(np.abs(F_shift))
    mag = exposure.rescale_intensity(mag, out_range=(0, 255))
    return mag.astype(np.uint8)


def apply_frequency_filter(img: np.ndarray, H: np.ndarray, edge_mode: bool = False) -> tuple[np.ndarray, float, np.ndarray]:
    F = fft2_shift(img)
    G = H * F
    g = ifft2_shift(G)
    spatial = np.real(g)
    if edge_mode:
        spatial = np.abs(spatial)
        spatial = exposure.rescale_intensity(spatial, out_range=(0, 255))
    else:
        spatial = np.clip(spatial, 0, 255)
    power_ratio = float(np.sum(np.abs(G) ** 2) / np.sum(np.abs(F) ** 2))
    return spatial.astype(np.uint8), power_ratio, normalized_log_spectrum(G)


def laplacian_highpass(img: np.ndarray) -> np.ndarray:
    lap = ndimage.laplace(img.astype(np.float32), mode="reflect")
    lap = np.abs(lap)
    lap = exposure.rescale_intensity(lap, out_range=(0, 255))
    return lap.astype(np.uint8)


def unsharp_mask(img: np.ndarray, sigma: float = 1.5, amount: float = 1.5) -> np.ndarray:
    blurred = ndimage.gaussian_filter(img.astype(np.float32), sigma=sigma, mode="reflect")
    sharp = img.astype(np.float32) + amount * (img.astype(np.float32) - blurred)
    return np.clip(np.round(sharp), 0, 255).astype(np.uint8)


def gradient_mean(img: np.ndarray) -> float:
    gx = ndimage.sobel(img.astype(np.float32), axis=1, mode="reflect")
    gy = ndimage.sobel(img.astype(np.float32), axis=0, mode="reflect")
    return float(np.mean(np.hypot(gx, gy)))


def laplacian_var(img: np.ndarray) -> float:
    lap = ndimage.laplace(img.astype(np.float32), mode="reflect")
    return float(lap.var())


def plot_filter(H: np.ndarray, title: str, out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(4, 4))
    im = ax.imshow(H, cmap="viridis")
    ax.set_title(title)
    ax.axis("off")
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def plot_frequency_overview(
    original: np.ndarray,
    original_spec: np.ndarray,
    filt1: np.ndarray,
    spec1: np.ndarray,
    filt2: np.ndarray,
    spec2: np.ndarray,
    title: str,
    out_path: Path,
) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(13, 8))
    axes[0, 0].imshow(original, cmap="gray", vmin=0, vmax=255)
    axes[0, 0].set_title(f"{title}\nOriginal")
    axes[0, 1].imshow(filt1, cmap="gray", vmin=0, vmax=255)
    axes[0, 1].set_title("Butterworth")
    axes[0, 2].imshow(filt2, cmap="gray", vmin=0, vmax=255)
    axes[0, 2].set_title("Gaussian")
    axes[1, 0].imshow(original_spec, cmap="gray", vmin=0, vmax=255)
    axes[1, 0].set_title("Original Spectrum")
    axes[1, 1].imshow(spec1, cmap="gray", vmin=0, vmax=255)
    axes[1, 1].set_title("Butterworth Spectrum")
    axes[1, 2].imshow(spec2, cmap="gray", vmin=0, vmax=255)
    axes[1, 2].set_title("Gaussian Spectrum")
    for ax in axes.ravel():
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def plot_other_highpass_overview(original: np.ndarray, laplace: np.ndarray, unsharp: np.ndarray, title: str, out_path: Path) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(12, 4))
    axes[0].imshow(original, cmap="gray", vmin=0, vmax=255)
    axes[0].set_title(f"{title}\nOriginal")
    axes[1].imshow(laplace, cmap="gray", vmin=0, vmax=255)
    axes[1].set_title("Laplacian")
    axes[2].imshow(unsharp, cmap="gray", vmin=0, vmax=255)
    axes[2].set_title("Unsharp")
    for ax in axes:
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def task_frequency_lowpass(images: dict[str, np.ndarray], out_dir: Path) -> list[dict]:
    tdir = out_dir / "task1_freq_lowpass"
    tdir.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []

    for name, cfg in LOWPASS_CONFIG.items():
        img = images[name]
        F = fft2_shift(img)
        spec = normalized_log_spectrum(F)
        d0 = cfg["radius"]
        n = cfg["order"]
        H_b = butterworth_lowpass(img.shape, d0, n=n)
        H_g = gaussian_lowpass(img.shape, d0)
        out_b, ratio_b, spec_b = apply_frequency_filter(img, H_b, edge_mode=False)
        out_g, ratio_g, spec_g = apply_frequency_filter(img, H_g, edge_mode=False)

        save_gray(out_b, tdir / f"{Path(name).stem}_butterworth_lp.png")
        save_gray(out_g, tdir / f"{Path(name).stem}_gaussian_lp.png")
        plot_filter(H_b, f"Butterworth LP\nD0={d0}, n={n}", tdir / f"{Path(name).stem}_butterworth_lp_filter.png")
        plot_filter(H_g, f"Gaussian LP\nD0={d0}", tdir / f"{Path(name).stem}_gaussian_lp_filter.png")
        plot_frequency_overview(img, spec, out_b, spec_b, out_g, spec_g, f"{name} Frequency Lowpass", tdir / f"{Path(name).stem}_freq_lowpass_overview.png")

        rows.append({
            "image": name,
            "method": "butterworth_lowpass",
            "radius": d0,
            "order": n,
            "power_ratio": ratio_b,
            "mean": float(out_b.mean()),
            "std": float(out_b.std()),
            "gradient_mean": gradient_mean(out_b),
            "laplacian_var": laplacian_var(out_b),
        })
        rows.append({
            "image": name,
            "method": "gaussian_lowpass",
            "radius": d0,
            "order": "",
            "power_ratio": ratio_g,
            "mean": float(out_g.mean()),
            "std": float(out_g.std()),
            "gradient_mean": gradient_mean(out_g),
            "laplacian_var": laplacian_var(out_g),
        })
        rows.append({
            "image": name,
            "method": "original",
            "radius": "",
            "order": "",
            "power_ratio": 1.0,
            "mean": float(img.mean()),
            "std": float(img.std()),
            "gradient_mean": gradient_mean(img),
            "laplacian_var": laplacian_var(img),
        })

    write_csv(
        tdir / "freq_lowpass_metrics.csv",
        rows,
        ["image", "method", "radius", "order", "power_ratio", "mean", "std", "gradient_mean", "laplacian_var"],
    )
    return rows


def task_frequency_highpass(images: dict[str, np.ndarray], out_dir: Path) -> list[dict]:
    tdir = out_dir / "task2_freq_highpass"
    tdir.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []

    for name, cfg in HIGHPASS_CONFIG.items():
        img = images[name]
        F = fft2_shift(img)
        spec = normalized_log_spectrum(F)
        d0 = cfg["radius"]
        n = cfg["order"]
        H_b = butterworth_highpass(img.shape, d0, n=n)
        H_g = gaussian_highpass(img.shape, d0)
        out_b, ratio_b, spec_b = apply_frequency_filter(img, H_b, edge_mode=True)
        out_g, ratio_g, spec_g = apply_frequency_filter(img, H_g, edge_mode=True)

        save_gray(out_b, tdir / f"{Path(name).stem}_butterworth_hp.png")
        save_gray(out_g, tdir / f"{Path(name).stem}_gaussian_hp.png")
        plot_filter(H_b, f"Butterworth HP\nD0={d0}, n={n}", tdir / f"{Path(name).stem}_butterworth_hp_filter.png")
        plot_filter(H_g, f"Gaussian HP\nD0={d0}", tdir / f"{Path(name).stem}_gaussian_hp_filter.png")
        plot_frequency_overview(img, spec, out_b, spec_b, out_g, spec_g, f"{name} Frequency Highpass", tdir / f"{Path(name).stem}_freq_highpass_overview.png")

        rows.append({
            "image": name,
            "method": "butterworth_highpass",
            "radius": d0,
            "order": n,
            "power_ratio": ratio_b,
            "mean": float(out_b.mean()),
            "std": float(out_b.std()),
            "gradient_mean": gradient_mean(out_b),
            "laplacian_var": laplacian_var(out_b),
        })
        rows.append({
            "image": name,
            "method": "gaussian_highpass",
            "radius": d0,
            "order": "",
            "power_ratio": ratio_g,
            "mean": float(out_g.mean()),
            "std": float(out_g.std()),
            "gradient_mean": gradient_mean(out_g),
            "laplacian_var": laplacian_var(out_g),
        })
        rows.append({
            "image": name,
            "method": "original",
            "radius": "",
            "order": "",
            "power_ratio": 1.0,
            "mean": float(img.mean()),
            "std": float(img.std()),
            "gradient_mean": gradient_mean(img),
            "laplacian_var": laplacian_var(img),
        })

    write_csv(
        tdir / "freq_highpass_metrics.csv",
        rows,
        ["image", "method", "radius", "order", "power_ratio", "mean", "std", "gradient_mean", "laplacian_var"],
    )
    return rows


def task_other_highpass(images: dict[str, np.ndarray], out_dir: Path) -> list[dict]:
    tdir = out_dir / "task3_other_highpass"
    tdir.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []

    for name in ("test3_corrupt.pgm", "test4.tif"):
        img = images[name]
        lap = laplacian_highpass(img)
        unsharp = unsharp_mask(img, sigma=1.5, amount=1.5)

        save_gray(lap, tdir / f"{Path(name).stem}_laplacian.png")
        save_gray(unsharp, tdir / f"{Path(name).stem}_unsharp.png")
        plot_other_highpass_overview(img, lap, unsharp, name, tdir / f"{Path(name).stem}_other_highpass_overview.png")

        rows.append({
            "image": name,
            "method": "laplacian",
            "mean": float(lap.mean()),
            "std": float(lap.std()),
            "gradient_mean": gradient_mean(lap),
            "laplacian_var": laplacian_var(lap),
        })
        rows.append({
            "image": name,
            "method": "unsharp",
            "mean": float(unsharp.mean()),
            "std": float(unsharp.std()),
            "gradient_mean": gradient_mean(unsharp),
            "laplacian_var": laplacian_var(unsharp),
        })
        rows.append({
            "image": name,
            "method": "original",
            "mean": float(img.mean()),
            "std": float(img.std()),
            "gradient_mean": gradient_mean(img),
            "laplacian_var": laplacian_var(img),
        })

    write_csv(
        tdir / "other_highpass_metrics.csv",
        rows,
        ["image", "method", "mean", "std", "gradient_mean", "laplacian_var"],
    )
    return rows


def write_learning_doc(low_rows: list[dict], high_rows: list[dict], other_rows: list[dict], out_path: Path) -> None:
    def row(rows: list[dict], image: str, method: str) -> dict:
        for r in rows:
            if r["image"] == image and r["method"] == method:
                return r
        raise KeyError((image, method))

    lines: list[str] = []
    lines.append("# 第五次作业学习文档")
    lines.append("")
    lines.append("## 一、题目在做什么")
    lines.append("")
    lines.append("这次作业的核心不是再做空域卷积，而是把图像变换到频域之后再设计滤波器。")
    lines.append("题目分成三部分：")
    lines.append("1. 频域低通：对 `test1`、`test2` 用 Butterworth 和 Gaussian 低通滤波器做平滑。")
    lines.append("2. 频域高通：对 `test3`、`test4` 用 Butterworth 和 Gaussian 高通滤波器增强边缘。")
    lines.append("3. 其他高通：对 `test3`、`test4` 再做 Laplacian 和 Unsharp，并和频域高通结果对比。")
    lines.append("")
    lines.append("## 二、为什么要看功率谱比")
    lines.append("")
    lines.append("频域滤波器本质上是在保留或抑制某些频率分量。")
    lines.append("为了量化“保留了多少频域能量”，这里定义功率谱比：")
    lines.append("")
    lines.append("`power_ratio = sum(|G(u,v)|^2) / sum(|F(u,v)|^2)`")
    lines.append("")
    lines.append("其中 `F` 是原图频谱，`G` 是滤波后频谱。")
    lines.append("- 低通滤波：功率谱比越接近 1，说明保留的总能量越多；越小则说明平滑更强。")
    lines.append("- 高通滤波：功率谱比通常比较小，因为高频本来只占总能量的一部分。")
    lines.append("")
    lines.append("## 三、参数怎么选")
    lines.append("")
    lines.append("这次我给每张图选择了一个相对合适的截止半径：")
    lines.append("- `test1.pgm`：低通半径 `D0=25`")
    lines.append("- `test2.tif`：低通半径 `D0=50`")
    lines.append("- `test3_corrupt.pgm`：高通半径 `D0=10`")
    lines.append("- `test4.tif`：高通半径 `D0=30`")
    lines.append("")
    lines.append("原则是：")
    lines.append("- 半径太小：低通会过模糊，高通会过于激进，只剩很少边缘。")
    lines.append("- 半径太大：低通效果不明显，高通也难以突出边缘。")
    lines.append("")
    lines.append("## 四、实验结果怎么读")
    lines.append("")
    for image in ("test1.pgm", "test2.tif"):
        o = row(low_rows, image, "original")
        b = row(low_rows, image, "butterworth_lowpass")
        g = row(low_rows, image, "gaussian_lowpass")
        lines.append(f"### 频域低通：{image}")
        lines.append("")
        lines.append(f"- 原图 `gradient_mean={o['gradient_mean']:.3f}`。")
        lines.append(f"- Butterworth 低通后为 `{b['gradient_mean']:.3f}`，功率谱比为 `{b['power_ratio']:.4f}`。")
        lines.append(f"- Gaussian 低通后为 `{g['gradient_mean']:.3f}`，功率谱比为 `{g['power_ratio']:.4f}`。")
        lines.append("- 这说明两者都削弱了高频细节，图像变得更平滑。")
        lines.append("- 一般来说，Gaussian 低通过渡更平滑，不容易产生振铃；Butterworth 截止更明确，但更容易带来边缘附近的轻微振荡。")
        lines.append("")

    for image in ("test3_corrupt.pgm", "test4.tif"):
        o = row(high_rows, image, "original")
        b = row(high_rows, image, "butterworth_highpass")
        g = row(high_rows, image, "gaussian_highpass")
        lap = row(other_rows, image, "laplacian")
        un = row(other_rows, image, "unsharp")
        lines.append(f"### 高频增强：{image}")
        lines.append("")
        lines.append(f"- 原图 `laplacian_var={o['laplacian_var']:.3f}`。")
        lines.append(f"- Butterworth 高频结果功率谱比 `{b['power_ratio']:.4f}`，更强调高频边缘。")
        lines.append(f"- Gaussian 高频结果功率谱比 `{g['power_ratio']:.4f}`，输出更平滑，边缘更自然。")
        lines.append(f"- Laplacian 输出 `laplacian_var={lap['laplacian_var']:.3f}`，对细节和噪声都很敏感。")
        lines.append(f"- Unsharp 输出 `laplacian_var={un['laplacian_var']:.3f}`，更适合锐化原图而不是直接生成边缘图。")
        lines.append("")

    lines.append("## 五、每种方法怎么写优缺点")
    lines.append("")
    lines.append("### 1. Butterworth 低通")
    lines.append("- 优点：截止特性比 Gaussian 更明显，平滑作用较强。")
    lines.append("- 缺点：在截止区域过渡不如 Gaussian 平滑，可能有轻微振铃。")
    lines.append("")
    lines.append("### 2. Gaussian 低通")
    lines.append("- 优点：频域响应平滑，结果自然，边缘过渡柔和。")
    lines.append("- 缺点：抑制高频时没有那么“硬”，某些噪声残留会更多。")
    lines.append("")
    lines.append("### 3. Butterworth 高频")
    lines.append("- 优点：边缘增强更明显，高频保留更直接。")
    lines.append("- 缺点：对噪声也更敏感。")
    lines.append("")
    lines.append("### 4. Gaussian 高频")
    lines.append("- 优点：增强较平滑，不容易产生明显伪影。")
    lines.append("- 缺点：边缘强化程度通常比 Butterworth 略弱。")
    lines.append("")
    lines.append("### 5. Laplacian")
    lines.append("- 优点：对灰度突变非常敏感，轮廓突出。")
    lines.append("- 缺点：噪声会被同步放大。")
    lines.append("")
    lines.append("### 6. Unsharp")
    lines.append("- 优点：更适合做锐化增强，保留原图外观。")
    lines.append("- 缺点：不是纯边缘图，参数不当会过锐。")
    lines.append("")
    lines.append("## 六、空域与频域的关系，报告里该怎么写")
    lines.append("")
    lines.append("题目最后要求讨论空域和频域滤波的关系，这里可以这样写：")
    lines.append("")
    lines.append("1. 理论上，空域卷积等价于频域乘法。")
    lines.append("2. 如果频域滤波器 `H(u,v)` 恰好是某个空域冲激响应 `h(x,y)` 的傅里叶变换，那么两者是等效的。")
    lines.append("3. 但在实际离散图像处理中，它们往往不会完全一致，原因包括：")
    lines.append("- 图像尺寸有限；")
    lines.append("- 边界处理方式不同；")
    lines.append("- 空域滤波器通常是有限模板，而频域滤波器常是理想化连续函数采样；")
    lines.append("- 参数之间不一定一一对应。")
    lines.append("4. 因此，空域低通/高通与频域低通/高通在趋势上是一致的，但数值和细节结果未必完全相同。")
    lines.append("")
    lines.append("## 七、本次结果文件")
    lines.append("")
    lines.append("- 任务1：`outputs/task1_freq_lowpass/`")
    lines.append("- 任务2：`outputs/task2_freq_highpass/`")
    lines.append("- 任务3：`outputs/task3_other_highpass/`")
    lines.append("- 代码：`assignment5.py`")

    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    images = {
        "test1.pgm": read_gray_image(ROOT / "test1.pgm"),
        "test2.tif": read_gray_image(ROOT / "test2.tif"),
        "test3_corrupt.pgm": read_gray_image(ROOT / "test3_corrupt.pgm"),
        "test4.tif": read_gray_image(ROOT / "test4.tif"),
    }

    low_rows = task_frequency_lowpass(images, OUT_DIR)
    high_rows = task_frequency_highpass(images, OUT_DIR)
    other_rows = task_other_highpass(images, OUT_DIR)
    write_learning_doc(low_rows, high_rows, other_rows, ROOT / "第五次作业学习文档.md")

    print("Done.")
    print(f"Lowpass outputs: {OUT_DIR / 'task1_freq_lowpass'}")
    print(f"Highpass outputs: {OUT_DIR / 'task2_freq_highpass'}")
    print(f"Other outputs: {OUT_DIR / 'task3_other_highpass'}")


if __name__ == "__main__":
    main()
