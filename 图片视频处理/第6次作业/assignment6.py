from __future__ import annotations

import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
from scipy import ndimage, signal
from scipy.signal import wiener as scipy_wiener


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "outputs"
RNG = np.random.default_rng(2026)


def read_gray(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("L"), dtype=np.float32)


def save_gray(arr: np.ndarray, path: Path) -> None:
    Image.fromarray(np.clip(np.round(arr), 0, 255).astype(np.uint8)).save(path)


def mse(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    m = mse(a, b)
    if m == 0:
        return float("inf")
    return float(10 * np.log10((255.0**2) / m))


def add_gaussian_noise(img: np.ndarray, mean: float = 0.0, var: float = 20.0) -> np.ndarray:
    noise = RNG.normal(mean, np.sqrt(var), img.shape)
    return np.clip(img + noise, 0, 255).astype(np.float32)


def add_salt_pepper_noise(img: np.ndarray, pepper_density: float = 0.1, salt_density: float = 0.1) -> np.ndarray:
    out = img.copy()
    rnd = RNG.random(img.shape)
    out[rnd < pepper_density] = 0
    out[rnd > 1 - salt_density] = 255
    return out.astype(np.float32)


def arithmetic_mean_filter(img: np.ndarray, size: int = 3) -> np.ndarray:
    kernel = np.ones((size, size), dtype=np.float32) / (size * size)
    return signal.convolve2d(img, kernel, boundary="symm", mode="same")


def median_filter(img: np.ndarray, size: int = 3) -> np.ndarray:
    return ndimage.median_filter(img, size=size, mode="reflect").astype(np.float32)


def gaussian_filter(img: np.ndarray, sigma: float = 1.0, size: int = 5) -> np.ndarray:
    truncate = ((size - 1) / 2) / sigma
    return ndimage.gaussian_filter(img, sigma=sigma, mode="reflect", truncate=truncate).astype(np.float32)


def adaptive_wiener_filter(img: np.ndarray, size: int = 5) -> np.ndarray:
    return scipy_wiener(img, mysize=(size, size)).astype(np.float32)


def contra_harmonic_mean_filter(img: np.ndarray, size: int = 3, q: float = 1.5) -> np.ndarray:
    eps = 1e-8
    num = ndimage.uniform_filter(np.power(img + eps, q + 1), size=size, mode="reflect") * (size * size)
    den = ndimage.uniform_filter(np.power(img + eps, q), size=size, mode="reflect") * (size * size)
    out = num / (den + eps)
    return np.clip(out, 0, 255).astype(np.float32)


def motion_psf(length: int = 21, angle_deg: float = 45.0) -> np.ndarray:
    psf = np.zeros((length, length), dtype=np.float32)
    center = (length - 1) / 2.0
    theta = np.deg2rad(angle_deg)
    dx = np.cos(theta)
    dy = np.sin(theta)
    for t in np.linspace(-center, center, length * 4):
        x = center + t * dx
        y = center + t * dy
        xi = int(round(x))
        yi = int(round(y))
        if 0 <= xi < length and 0 <= yi < length:
            psf[yi, xi] = 1.0
    psf_sum = psf.sum()
    if psf_sum == 0:
        psf[int(center), int(center)] = 1.0
        psf_sum = 1.0
    return psf / psf_sum


def blur_with_psf(img: np.ndarray, psf: np.ndarray) -> np.ndarray:
    return signal.convolve2d(img, psf, boundary="symm", mode="same").astype(np.float32)


def psf2otf(psf: np.ndarray, shape: tuple[int, int]) -> np.ndarray:
    out = np.zeros(shape, dtype=np.float32)
    ph, pw = psf.shape
    out[:ph, :pw] = psf
    out = np.roll(out, -ph // 2, axis=0)
    out = np.roll(out, -pw // 2, axis=1)
    return np.fft.fft2(out)


def inverse_filter(degraded: np.ndarray, H: np.ndarray, eps: float = 1e-3) -> np.ndarray:
    G = np.fft.fft2(degraded)
    F_hat = G / (H + eps)
    out = np.real(np.fft.ifft2(F_hat))
    return np.clip(out, 0, 255).astype(np.float32)


def wiener_filter_known_noise(degraded: np.ndarray, H: np.ndarray, K: float) -> np.ndarray:
    G = np.fft.fft2(degraded)
    H_conj = np.conj(H)
    F_hat = (H_conj / (np.abs(H) ** 2 + K)) * G
    out = np.real(np.fft.ifft2(F_hat))
    return np.clip(out, 0, 255).astype(np.float32)


def cls_filter(degraded: np.ndarray, H: np.ndarray, gamma: float = 0.01) -> np.ndarray:
    # constrained least squares style restoration using Laplacian regularization
    p = np.array([[0, -1, 0], [-1, 4, -1], [0, -1, 0]], dtype=np.float32)
    P = psf2otf(p, degraded.shape)
    G = np.fft.fft2(degraded)
    H_conj = np.conj(H)
    F_hat = (H_conj / (np.abs(H) ** 2 + gamma * (np.abs(P) ** 2))) * G
    out = np.real(np.fft.ifft2(F_hat))
    return np.clip(out, 0, 255).astype(np.float32)


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def plot_grid(images: list[tuple[str, np.ndarray]], title: str, out_path: Path, cols: int = 3) -> None:
    n = len(images)
    rows = int(np.ceil(n / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(4 * cols, 4 * rows))
    axes = np.array(axes).reshape(rows, cols)
    for ax in axes.ravel():
        ax.axis("off")
    for ax, (name, img) in zip(axes.ravel(), images):
        ax.imshow(np.clip(img, 0, 255), cmap="gray", vmin=0, vmax=255)
        ax.set_title(name)
        ax.axis("off")
    fig.suptitle(title, fontsize=14)
    fig.tight_layout()
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def task1_gaussian_noise_restore(img: np.ndarray, out_dir: Path) -> list[dict]:
    tdir = out_dir / "task1_gaussian_noise"
    tdir.mkdir(parents=True, exist_ok=True)
    noisy = add_gaussian_noise(img, mean=0.0, var=20.0)

    results = {
        "Arithmetic Mean 3x3": arithmetic_mean_filter(noisy, size=3),
        "Median 3x3": median_filter(noisy, size=3),
        "Gaussian 5x5": gaussian_filter(noisy, sigma=1.0, size=5),
        "Adaptive Wiener 5x5": adaptive_wiener_filter(noisy, size=5),
    }

    save_gray(noisy, tdir / "lena_gaussian_noisy.png")
    for name, arr in results.items():
        save_gray(arr, tdir / f"{name.lower().replace(' ', '_').replace('5x5','5x5').replace('3x3','3x3')}.png")

    plot_grid(
        [("Original", img), ("Gaussian Noise", noisy)] + list(results.items()),
        "Task1: Gaussian Noise and Restoration",
        tdir / "task1_overview.png",
        cols=3,
    )

    rows = [{
        "method": "Noisy",
        "mse": mse(img, noisy),
        "psnr": psnr(img, noisy),
    }]
    for name, arr in results.items():
        rows.append({"method": name, "mse": mse(img, arr), "psnr": psnr(img, arr)})
    write_csv(tdir / "task1_metrics.csv", rows, ["method", "mse", "psnr"])
    return rows


def task2_salt_pepper_restore(img: np.ndarray, out_dir: Path) -> list[dict]:
    tdir = out_dir / "task2_salt_pepper"
    tdir.mkdir(parents=True, exist_ok=True)
    noisy = add_salt_pepper_noise(img, pepper_density=0.1, salt_density=0.1)

    results = {
        "Arithmetic Mean 3x3": arithmetic_mean_filter(noisy, size=3),
        "Median 3x3": median_filter(noisy, size=3),
        "Contra-harmonic Q=1.5": contra_harmonic_mean_filter(noisy, size=3, q=1.5),
        "Contra-harmonic Q=-1.5": contra_harmonic_mean_filter(noisy, size=3, q=-1.5),
    }

    save_gray(noisy, tdir / "lena_salt_pepper_noisy.png")
    for name, arr in results.items():
        save_gray(arr, tdir / f"{name.lower().replace(' ', '_').replace('=','').replace('.','_')}.png")

    plot_grid(
        [("Original", img), ("Salt-Pepper Noise", noisy)] + list(results.items()),
        "Task2: Salt-Pepper Noise and Restoration",
        tdir / "task2_overview.png",
        cols=3,
    )

    rows = [{
        "method": "Noisy",
        "mse": mse(img, noisy),
        "psnr": psnr(img, noisy),
    }]
    for name, arr in results.items():
        rows.append({"method": name, "mse": mse(img, arr), "psnr": psnr(img, arr)})
    write_csv(tdir / "task2_metrics.csv", rows, ["method", "mse", "psnr"])
    return rows


def task3_motion_blur_wiener(img: np.ndarray, out_dir: Path) -> list[dict]:
    tdir = out_dir / "task3_motion_blur_wiener"
    tdir.mkdir(parents=True, exist_ok=True)

    psf = motion_psf(length=21, angle_deg=45.0)
    H = psf2otf(psf, img.shape)
    blurred = blur_with_psf(img, psf)
    degraded = add_gaussian_noise(blurred, mean=0.0, var=10.0)

    inverse = inverse_filter(degraded, H, eps=1e-2)
    wiener_known = wiener_filter_known_noise(degraded, H, K=0.01)
    cls = cls_filter(degraded, H, gamma=0.01)

    save_gray(blurred, tdir / "lena_motion_blurred.png")
    save_gray(degraded, tdir / "lena_motion_blur_plus_noise.png")
    save_gray(inverse, tdir / "inverse_filter_result.png")
    save_gray(wiener_known, tdir / "wiener_filter_result.png")
    save_gray(cls, tdir / "cls_filter_result.png")

    plot_grid(
        [
            ("Original", img),
            ("Motion Blur", blurred),
            ("Blur + Noise", degraded),
            ("Inverse Filter", inverse),
            ("Wiener Filter", wiener_known),
            ("CLS Filter", cls),
        ],
        "Task3: Motion Blur and Restoration",
        tdir / "task3_overview.png",
        cols=3,
    )

    fig, ax = plt.subplots(figsize=(4, 4))
    ax.imshow(psf, cmap="gray")
    ax.set_title("Motion PSF (45 degree, T=1)")
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(tdir / "motion_psf.png", dpi=180)
    plt.close(fig)

    rows = [
        {"method": "Blurred", "mse": mse(img, blurred), "psnr": psnr(img, blurred)},
        {"method": "Blurred + Gaussian Noise", "mse": mse(img, degraded), "psnr": psnr(img, degraded)},
        {"method": "Inverse Filter", "mse": mse(img, inverse), "psnr": psnr(img, inverse)},
        {"method": "Wiener Filter", "mse": mse(img, wiener_known), "psnr": psnr(img, wiener_known)},
        {"method": "CLS Filter", "mse": mse(img, cls), "psnr": psnr(img, cls)},
    ]
    write_csv(tdir / "task3_metrics.csv", rows, ["method", "mse", "psnr"])
    return rows


def write_learning_doc(task1_rows: list[dict], task2_rows: list[dict], task3_rows: list[dict], out_path: Path) -> None:
    def metric(rows: list[dict], method: str) -> dict:
        for r in rows:
            if r["method"] == method:
                return r
        raise KeyError(method)

    lines: list[str] = []
    lines.append("# 第六次作业学习文档")
    lines.append("")
    lines.append("## 一、题目在做什么")
    lines.append("")
    lines.append("这次作业的核心是“图像退化与恢复”。")
    lines.append("前两问是先人为加入噪声，再用不同滤波器恢复；第三问是先加入运动模糊，再加噪声，然后用逆滤波和维纳类方法做复原。")
    lines.append("")
    lines.append("## 二、任务1：高斯噪声恢复")
    lines.append("")
    lines.append("这一步给 Lena 加入高斯噪声，均值设为 0，方差设为 20。")
    lines.append("然后分别用了：")
    lines.append("- 算术均值滤波")
    lines.append("- 中值滤波")
    lines.append("- 高斯滤波")
    lines.append("- 自适应维纳滤波")
    lines.append("")
    lines.append("为什么这些方法能用：")
    lines.append("- 高斯噪声是连续型随机噪声，均值滤波和高斯滤波对它最自然。")
    lines.append("- 中值滤波更适合椒盐噪声，所以在高斯噪声场景下不一定最好。")
    lines.append("- 维纳滤波会根据局部统计特性调整恢复强度，通常能更平衡噪声抑制和细节保留。")
    lines.append("")
    lines.append(f"当前实验里，噪声图 PSNR 为 `{metric(task1_rows, 'Noisy')['psnr']:.3f}` dB。")
    for name in ["Arithmetic Mean 3x3", "Median 3x3", "Gaussian 5x5", "Adaptive Wiener 5x5"]:
        lines.append(f"- {name}: PSNR = `{metric(task1_rows, name)['psnr']:.3f}` dB")
    lines.append("")
    lines.append("写报告时可以说：对于高斯噪声，均值类和平滑类滤波器更合适，其中维纳滤波通常在去噪与保细节之间更平衡。")
    lines.append("")
    lines.append("## 三、任务2：椒盐噪声恢复")
    lines.append("")
    lines.append("这一步给 Lena 加入椒盐噪声，椒和盐的密度都为 0.1。")
    lines.append("然后分别用了：")
    lines.append("- 算术均值滤波")
    lines.append("- 中值滤波")
    lines.append("- 反谐波均值滤波（Q=1.5）")
    lines.append("- 反谐波均值滤波（Q=-1.5）")
    lines.append("")
    lines.append("反谐波的关键理解：")
    lines.append("- `Q > 0` 时，更擅长去除椒噪声（黑点）。")
    lines.append("- `Q < 0` 时，更擅长去除盐噪声（白点）。")
    lines.append("因为公式中高次或负次幂会对大像素值或小像素值更敏感。")
    lines.append("")
    lines.append(f"当前实验里，椒盐噪声图 PSNR 为 `{metric(task2_rows, 'Noisy')['psnr']:.3f}` dB。")
    for name in ["Arithmetic Mean 3x3", "Median 3x3", "Contra-harmonic Q=1.5", "Contra-harmonic Q=-1.5"]:
        lines.append(f"- {name}: PSNR = `{metric(task2_rows, name)['psnr']:.3f}` dB")
    lines.append("")
    lines.append("写报告时可以强调：中值滤波通常是椒盐噪声恢复中最稳妥的选择；反谐波滤波的优势在于可以有针对性地抑制椒噪声或盐噪声。")
    lines.append("")
    lines.append("## 四、任务3：运动模糊 + 维纳恢复")
    lines.append("")
    lines.append("这一步是最核心的。流程是：")
    lines.append("1. 构造 45 度方向的运动模糊 PSF。")
    lines.append("2. 用它对 Lena 做模糊。")
    lines.append("3. 在模糊图中再加入均值 0、方差 10 的高斯噪声。")
    lines.append("4. 分别用逆滤波、维纳滤波、约束最小二乘类恢复。")
    lines.append("")
    lines.append("它们的区别：")
    lines.append("- 逆滤波：最直接，但对噪声非常敏感。")
    lines.append("- 维纳滤波：显式考虑噪声与信号的折中，通常更稳定。")
    lines.append("- 约束最小二乘（CLS 风格）：加入平滑约束，对噪声放大更克制。")
    lines.append("")
    for name in ["Blurred", "Blurred + Gaussian Noise", "Inverse Filter", "Wiener Filter", "CLS Filter"]:
        lines.append(f"- {name}: PSNR = `{metric(task3_rows, name)['psnr']:.3f}` dB")
    lines.append("")
    lines.append("报告里可以这样总结：")
    lines.append("- 逆滤波在知道模糊函数时理论最直接，但一旦有噪声就很容易失稳。")
    lines.append("- 维纳滤波更适合带噪模糊图像恢复。")
    lines.append("- CLS 恢复更强调平滑约束，通常视觉上更稳定，但可能牺牲部分锐利边缘。")
    lines.append("")
    lines.append("## 五、这次实验里每种滤波器怎么理解")
    lines.append("")
    lines.append("### 1. 算术均值滤波")
    lines.append("- 优点：简单，对高斯噪声有一定抑制作用。")
    lines.append("- 缺点：容易模糊边缘，对椒盐噪声不够鲁棒。")
    lines.append("")
    lines.append("### 2. 中值滤波")
    lines.append("- 优点：对椒盐噪声效果好，能较好保边缘。")
    lines.append("- 缺点：对高斯噪声不一定最优。")
    lines.append("")
    lines.append("### 3. 高斯滤波")
    lines.append("- 优点：适合抑制高斯噪声，输出自然。")
    lines.append("- 缺点：会带来一定模糊。")
    lines.append("")
    lines.append("### 4. 反谐波均值滤波")
    lines.append("- 优点：可以针对性去除椒噪声或盐噪声。")
    lines.append("- 缺点：参数 Q 选错时效果会变差。")
    lines.append("")
    lines.append("### 5. 维纳滤波")
    lines.append("- 优点：考虑噪声和模糊，是恢复问题里很经典的方法。")
    lines.append("- 缺点：依赖噪声估计和模型假设。")
    lines.append("")
    lines.append("## 六、结果文件位置")
    lines.append("")
    lines.append("- 任务1：`outputs/task1_gaussian_noise/`")
    lines.append("- 任务2：`outputs/task2_salt_pepper/`")
    lines.append("- 任务3：`outputs/task3_motion_blur_wiener/`")
    lines.append("- 代码：`assignment6.py`")

    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img = read_gray(ROOT / "lena.bmp")

    task1_rows = task1_gaussian_noise_restore(img, OUT_DIR)
    task2_rows = task2_salt_pepper_restore(img, OUT_DIR)
    task3_rows = task3_motion_blur_wiener(img, OUT_DIR)

    write_learning_doc(task1_rows, task2_rows, task3_rows, ROOT / "第六次作业学习文档.md")

    print("Done.")
    print(f"Task1 outputs: {OUT_DIR / 'task1_gaussian_noise'}")
    print(f"Task2 outputs: {OUT_DIR / 'task2_salt_pepper'}")
    print(f"Task3 outputs: {OUT_DIR / 'task3_motion_blur_wiener'}")


if __name__ == "__main__":
    main()
