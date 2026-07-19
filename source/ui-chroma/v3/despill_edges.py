from pathlib import Path

from PIL import Image


def despill(path: Path) -> int:
    image = Image.open(path).convert("RGBA")
    pixels = []
    changed = 0

    for red, green, blue, alpha in image.get_flattened_data():
        if 0 < alpha < 255 and green > max(red, blue) + 5:
            green = max(red, blue)
            changed += 1
        pixels.append((red, green, blue, alpha))

    image.putdata(pixels)
    image.save(path)
    return changed


def main() -> None:
    icons_dir = Path(__file__).with_name("icons")
    for path in sorted(icons_dir.glob("*.png")):
        print(f"{path.name}: {despill(path)} edge pixels adjusted")


if __name__ == "__main__":
    main()
