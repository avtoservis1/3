from pathlib import Path
from PIL import Image

src = Path('android/app/src/main/res/mipmap-hdpi/photo_2026-07-16_13-44-28.jpg')
if not src.exists():
    raise FileNotFoundError(f'Missing source image: {src}')

img = Image.open(src).convert('RGBA')
width, height = img.size
size = max(width, height)
canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
canvas.paste(img, ((size - width) // 2, (size - height) // 2), img if img.mode == 'RGBA' else None)

# Save full-size asset
assets_dir = Path('assets')
assets_dir.mkdir(parents=True, exist_ok=True)
asset_icon = assets_dir / 'app_icon.png'
canvas.resize((1024, 1024), Image.LANCZOS).save(asset_icon)

android_densities = {
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
}
for path, size_px in android_densities.items():
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((size_px, size_px), Image.LANCZOS).save(p)

foreground = Path('android/app/src/main/res/drawable/ic_launcher_foreground_image.png')
foreground.parent.mkdir(parents=True, exist_ok=True)
canvas.resize((432, 432), Image.LANCZOS).save(foreground)

web_icons = {
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
}
for path, size_px in web_icons.items():
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((size_px, size_px), Image.LANCZOS).save(p)

print('ICON_FILES_CREATED')
