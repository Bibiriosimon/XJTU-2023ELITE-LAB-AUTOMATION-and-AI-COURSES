from __future__ import annotations

import math
import struct
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "outputs"


def parse_bmp_header(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 54:
        raise ValueError(f"{path.name} is too small to be a valid BMP file.")

    file_header = struct.unpack("<2sIHHI", data[:14])
    dib_size = struct.unpack("<I", data[14:18])[0]
    if dib_size < 40:
        raise ValueError(f"Unsupported DIB header size: {dib_size}")
    dib_header = struct.unpack("<IiiHHIIiiII", data[14:54])

    return {
        "signature": file_header[0].decode("ascii", errors="ignore"),
        "file_size": file_header[1],
        "pixel_offset": file_header[4],
        "dib_size": dib_header[0],
        "width": dib_header[1],
        "height": dib_header[2],
        "planes": dib_header[3],
        "bits_per_pixel": dib_header[4],
        "compression": dib_header[5],
        "image_size": dib_header[6],
        "x_pixels_per_meter": dib_header[7],
        "y_pixels_per_meter": dib_header[8],
        "colors_used": dib_header[9],
        "important_colors": dib_header[10],
    }


def write_task1_report(path_7bmp: Path, out_txt: Path) -> None:
    header = parse_bmp_header(path_7bmp)
    lines = [
        "题1：BMP图像格式简介（以7.bmp为例）",
        "",
        "BMP文件通常由三部分组成：",
        "1) 文件头（14字节）：文件标识、文件大小、像素数据起始偏移。",
        "2) 信息头DIB（常见40字节）：宽高、位深、压缩方式、分辨率等。",
        "3) 颜色表与像素数据：",
        "   - 当位深 <= 8 时，通常有颜色表（调色板）；",
        "   - 像素数据按行存储，每行按4字节对齐。",
        "",
        "7.bmp解析结果：",
        f"- 文件标识(signature): {header['signature']}",
        f"- 文件大小(file_size): {header['file_size']} bytes",
        f"- 像素数据偏移(pixel_offset): {header['pixel_offset']} bytes",
        f"- DIB头大小(dib_size): {header['dib_size']} bytes",
        f"- 宽度(width): {header['width']}",
        f"- 高度(height): {header['height']}",
        f"- 位平面(planes): {header['planes']}",
        f"- 位深(bits_per_pixel): {header['bits_per_pixel']}",
        f"- 压缩(compression): {header['compression']}",
        f"- 图像数据大小(image_size): {header['image_size']} bytes",
        f"- 水平分辨率(x_pixels_per_meter): {header['x_pixels_per_meter']}",
        f"- 垂直分辨率(y_pixels_per_meter): {header['y_pixels_per_meter']}",
        f"- 调色板颜色数(colors_used): {header['colors_used']}",
        f"- 重要颜色数(important_colors): {header['important_colors']}",
    ]
    out_txt.write_text("\n".join(lines), encoding="utf-8")


def quantize_to_bits(gray: np.ndarray, bits: int) -> np.ndarray:
    if bits < 1 or bits > 8:
        raise ValueError("bits must be in [1, 8]")
    if bits == 8:
        return gray.astype(np.uint8)
    levels = 2**bits
    # Uniform quantization by bins over [0, 256), so 1-bit becomes a meaningful black/white split.
    quantized_index = np.floor(gray.astype(np.float32) * levels / 256.0)
    quantized_index = np.clip(quantized_index, 0, levels - 1)
    restored = np.round(quantized_index * 255.0 / (levels - 1))
    return restored.astype(np.uint8)


def write_task2_gray_levels(lena_path: Path, out_dir: Path) -> None:
    img = Image.open(lena_path).convert("L")
    arr = np.array(img)
    task2_dir = out_dir / "task2_gray_levels"
    task2_dir.mkdir(parents=True, exist_ok=True)

    fig, axes = plt.subplots(2, 4, figsize=(16, 8))
    for idx, bits in enumerate(range(8, 0, -1)):
        reduced = quantize_to_bits(arr, bits)
        Image.fromarray(reduced).save(task2_dir / f"lena_{bits}bit.png")
        ax = axes[idx // 4, idx % 4]
        ax.imshow(reduced, cmap="gray", vmin=0, vmax=255)
        ax.set_title(f"{bits}-bit ({2**bits} levels)")
        ax.axis("off")

    fig.suptitle("Lena Gray-Level Reduction: 8-bit -> 1-bit", fontsize=14)
    fig.tight_layout()
    fig.savefig(out_dir / "task2_gray_levels_overview.png", dpi=200)
    plt.close(fig)


def write_task3_stats(lena_path: Path, out_txt: Path) -> None:
    img = Image.open(lena_path).convert("L")
    arr = np.array(img, dtype=np.float64)
    mean = float(arr.mean())
    var = float(arr.var())
    lines = [
        "题3：Lena图像均值和方差（灰度图）",
        f"Mean = {mean:.6f}",
        f"Variance = {var:.6f}",
    ]
    out_txt.write_text("\n".join(lines), encoding="utf-8")


def resize_to_2048(img: Image.Image, method_name: str) -> Image.Image:
    method_map = {
        "nearest": Image.Resampling.NEAREST,
        "bilinear": Image.Resampling.BILINEAR,
        "bicubic": Image.Resampling.BICUBIC,
    }
    return img.resize((2048, 2048), resample=method_map[method_name])


def write_task4_zoom(lena_path: Path, out_dir: Path) -> None:
    img = Image.open(lena_path).convert("L")
    task4_dir = out_dir / "task4_zoom"
    task4_dir.mkdir(parents=True, exist_ok=True)
    for method in ("nearest", "bilinear", "bicubic"):
        resized = resize_to_2048(img, method)
        resized.save(task4_dir / f"lena_2048_{method}.png")


def shear_horizontal(img: Image.Image, k: float, resample: int) -> Image.Image:
    w, h = img.size
    corners_x = [0.0, w - 1.0, k * (h - 1.0), (w - 1.0) + k * (h - 1.0)]
    min_x = min(corners_x)
    max_x = max(corners_x)
    out_w = int(math.ceil(max_x - min_x + 1))

    # x' = x + k*y, y' = y
    # inverse mapping used by PIL: x = x' + min_x - k*y'
    matrix = (1.0, -k, min_x, 0.0, 1.0, 0.0)
    return img.transform((out_w, h), Image.Transform.AFFINE, matrix, resample=resample)


def write_task5_transform_and_zoom(lena_path: Path, elain_path: Path, out_dir: Path) -> None:
    task5_dir = out_dir / "task5_transform_zoom"
    task5_dir.mkdir(parents=True, exist_ok=True)

    imgs = {
        "lena": Image.open(lena_path).convert("L"),
        "elain1": Image.open(elain_path).convert("L"),
    }
    zoom_methods = {
        "nearest": Image.Resampling.NEAREST,
        "bilinear": Image.Resampling.BILINEAR,
        "bicubic": Image.Resampling.BICUBIC,
    }

    for name, img in imgs.items():
        sheared = shear_horizontal(img, k=1.5, resample=Image.Resampling.BICUBIC)
        rotated = img.rotate(30, resample=Image.Resampling.BICUBIC, expand=True)
        transformed = {
            "shear_k1.5": sheared,
            "rotate_30deg": rotated,
        }

        for trans_name, trans_img in transformed.items():
            trans_img.save(task5_dir / f"{name}_{trans_name}.png")
            for method_name, method in zoom_methods.items():
                out = trans_img.resize((2048, 2048), resample=method)
                out.save(task5_dir / f"{name}_{trans_name}_2048_{method_name}.png")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    bmp7 = ROOT / "7.bmp"
    lena = ROOT / "lena.bmp"
    elain = ROOT / "elain1.bmp"

    write_task1_report(bmp7, OUT_DIR / "task1_bmp_report.txt")
    write_task2_gray_levels(lena, OUT_DIR)
    write_task3_stats(lena, OUT_DIR / "task3_lena_stats.txt")
    write_task4_zoom(lena, OUT_DIR)
    write_task5_transform_and_zoom(lena, elain, OUT_DIR)

    print("All tasks finished. Outputs written to:", OUT_DIR)


if __name__ == "__main__":
    main()
