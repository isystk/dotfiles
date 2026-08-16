#!/usr/bin/env python3
import sys
from pathlib import Path
from PIL import Image

def images_to_pdf(directory_path, output_filename):
    path = Path(directory_path)
    
    extensions = {".jpg", ".jpeg", ".png", ".bmp"}
    image_files = sorted([
        f for f in path.iterdir() 
        if f.suffix.lower() in extensions
    ])

    if not image_files:
        print(f"No images found in {directory_path}")
        return

    try:
        first_image = Image.open(image_files[0]).convert("RGB")
        image_list = [
            Image.open(f).convert("RGB") 
            for f in image_files[1:]
        ]
        
        first_image.save(
            output_filename, 
            save_all=True, 
            append_images=image_list
        )
        print(f"✅ PDFを作成しました: {output_filename} ({len(image_files)}枚)")

    except Exception as e:
        print(f"❌ エラー: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py [directory_path]")
        sys.exit(1)
        
    target_dir = sys.argv[1]
    output_pdf = "output.pdf"
    
    images_to_pdf(target_dir, output_pdf)