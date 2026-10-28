#!/usr/bin/env python3
"""指定した画像をWeb表示用に最適化する（リサイズ + 圧縮 + EXIF削除）。"""
import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError:
    print("❌ Pillow が未インストールです。次のコマンドで導入してください:")
    print("   python3 -m pip install pillow")
    sys.exit(1)

TARGET_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
DEFAULT_MAX_WIDTH = 1200
DEFAULT_QUALITY = 82
SUFFIX = "_web"


def collect_images(paths):
    """ファイルとディレクトリ（直下のみ）から対象画像を集める。"""
    images = []
    for raw in paths:
        path = Path(raw).expanduser()
        if path.is_dir():
            found = sorted(
                p for p in path.iterdir()
                if p.is_file() and p.suffix.lower() in TARGET_SUFFIXES
                and not p.stem.endswith(SUFFIX)
            )
            if not found:
                print(f"⚠️  画像なし: {path}")
            images.extend(found)
        elif path.is_file():
            if path.suffix.lower() in TARGET_SUFFIXES:
                images.append(path)
            else:
                print(f"⚠️  対象外の形式: {path}")
        else:
            print(f"⚠️  見つかりません: {path}")
    return images


def optimize(path, out_dir, max_width, quality):
    """1枚を最適化して保存し、(元サイズ, 新サイズ) を返す。"""
    with Image.open(path) as img:
        img = ImageOps.exif_transpose(img)
        icc = img.info.get("icc_profile")
        src_width, src_height = img.size

        if src_width > max_width:
            ratio = max_width / src_width
            new_size = (max_width, max(1, round(src_height * ratio)))
            img = img.resize(new_size, Image.LANCZOS)

        dest = (out_dir or path.parent) / f"{path.stem}{SUFFIX}{path.suffix.lower()}"
        dest.parent.mkdir(parents=True, exist_ok=True)

        suffix = path.suffix.lower()
        save_args = {}
        if icc:
            save_args["icc_profile"] = icc

        if suffix in (".jpg", ".jpeg"):
            if img.mode not in ("RGB", "L"):
                img = img.convert("RGB")
            save_args.update(quality=quality, optimize=True, progressive=True)
        elif suffix == ".png":
            save_args.update(optimize=True, compress_level=9)
        elif suffix == ".webp":
            save_args.update(quality=quality, method=6)

        img.save(dest, **save_args)
        new_width, new_height = img.size

    return dest, (src_width, src_height), (new_width, new_height)


def human(num):
    for unit in ("B", "KB", "MB"):
        if num < 1024 or unit == "MB":
            return f"{num:.1f}{unit}" if unit != "B" else f"{num}B"
        num /= 1024


def main():
    parser = argparse.ArgumentParser(
        description="画像をWeb表示用に最適化します（既定: 最大幅1200px・品質82・EXIF削除）。"
    )
    parser.add_argument("paths", nargs="+", metavar="FILE|DIR",
                        help="画像ファイル、または画像を含むディレクトリ（直下のみ）")
    parser.add_argument("-w", "--max-width", type=int, default=DEFAULT_MAX_WIDTH,
                        help=f"最大幅（既定: {DEFAULT_MAX_WIDTH}px、小さい画像は拡大しない）")
    parser.add_argument("-q", "--quality", type=int, default=DEFAULT_QUALITY,
                        help=f"JPEG/WebP の品質 1-100（既定: {DEFAULT_QUALITY}）")
    parser.add_argument("-o", "--out-dir", metavar="DIR",
                        help="出力先ディレクトリ（既定: 元ファイルと同じフォルダ）")
    args = parser.parse_args()

    out_dir = Path(args.out_dir).expanduser() if args.out_dir else None

    images = collect_images(args.paths)
    if not images:
        print("❌ 対象画像がありません。")
        return 1

    before_total = 0
    after_total = 0
    for path in images:
        before = path.stat().st_size
        try:
            dest, src_size, new_size = optimize(path, out_dir, args.max_width, args.quality)
        except Exception as e:
            print(f"❌ 失敗: {path} ({e})")
            continue

        after = dest.stat().st_size
        before_total += before
        after_total += after

        rate = (1 - after / before) * 100 if before else 0
        resize_note = f"{src_size[0]}x{src_size[1]} → {new_size[0]}x{new_size[1]}"
        warn = " ⚠️ 元より大きい" if after > before else ""
        print(f"✅ {dest}")
        print(f"   {resize_note}  {human(before)} → {human(after)}  ({rate:.1f}% 削減){warn}")

    if len(images) > 1:
        rate = (1 - after_total / before_total) * 100 if before_total else 0
        print(f"\n合計 {len(images)}枚: {human(before_total)} → {human(after_total)}  ({rate:.1f}% 削減)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
