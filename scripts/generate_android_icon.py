from pathlib import Path

from PIL import Image, ImageOps

root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'iconn.png').convert('RGBA')
side = min(source.size)
left = (source.width - side) // 2
top = (source.height - side) // 2
source = source.crop((left, top, left + side, top + side))

densities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}
for density, size in densities.items():
    directory = root / 'android/app/src/main/res' / f'mipmap-{density}'
    directory.mkdir(parents=True, exist_ok=True)
    ImageOps.fit(source, (size, size), method=Image.Resampling.LANCZOS).save(
        directory / 'ic_launcher.png'
    )

foreground_dir = root / 'android/app/src/main/res/mipmap-xxxhdpi'
foreground = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
logo = ImageOps.contain(source, (288, 288), method=Image.Resampling.LANCZOS)
foreground.alpha_composite(logo, ((432 - logo.width) // 2, (432 - logo.height) // 2))
foreground.save(foreground_dir / 'ic_launcher_foreground.png')

adaptive_dir = root / 'android/app/src/main/res/mipmap-anydpi-v26'
adaptive_dir.mkdir(parents=True, exist_ok=True)
(adaptive_dir / 'ic_launcher.xml').write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@android:color/black"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n',
    encoding='utf-8',
)
print('Generated Android launcher icons from iconn.png')
