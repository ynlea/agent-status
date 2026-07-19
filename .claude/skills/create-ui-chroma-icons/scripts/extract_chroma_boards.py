"""Normalize 2x2 green-screen boards and extract validated transparent icons."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image


DEFAULT_BOARD_SIZE = 2048
DEFAULT_ICON_SIZE = 512


@dataclass(frozen=True)
class BoardSpec:
    filename: str
    icons: tuple[str, str, str, str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Normalize 2x2 #00FF00 boards and extract transparent PNG icons."
    )
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--boards-dir", type=Path, required=True)
    parser.add_argument("--normalized-dir", type=Path, required=True)
    parser.add_argument("--icons-dir", type=Path, required=True)
    parser.add_argument("--qa-out", type=Path, required=True)
    parser.add_argument("--board-size", type=int, default=DEFAULT_BOARD_SIZE)
    parser.add_argument("--icon-size", type=int, default=DEFAULT_ICON_SIZE)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def safe_filename(value: Any, suffix: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("Board and icon filenames must be non-empty strings")
    filename = value.strip()
    if Path(filename).name != filename or filename in {".", ".."}:
        raise ValueError(f"Path traversal is not allowed in manifest filenames: {filename}")
    if Path(filename).suffix.lower() != suffix:
        raise ValueError(f"Expected a {suffix} filename: {filename}")
    return filename


def load_manifest(path: Path) -> list[BoardSpec]:
    data = json.loads(path.read_text(encoding="utf-8"))
    raw_boards = data.get("boards") if isinstance(data, dict) else None
    if not isinstance(raw_boards, list) or not raw_boards:
        raise ValueError("Manifest must contain a non-empty 'boards' array")

    boards: list[BoardSpec] = []
    seen_boards: set[str] = set()
    seen_icons: set[str] = set()
    for raw_board in raw_boards:
        if not isinstance(raw_board, dict):
            raise ValueError("Every board entry must be an object")
        filename = safe_filename(raw_board.get("file"), ".png")
        raw_icons = raw_board.get("icons")
        if not isinstance(raw_icons, list) or len(raw_icons) != 4:
            raise ValueError(f"Board {filename} must define exactly four icons")
        icons = tuple(safe_filename(item, ".png") for item in raw_icons)
        if filename in seen_boards:
            raise ValueError(f"Duplicate board filename: {filename}")
        duplicates = seen_icons.intersection(icons)
        if len(set(icons)) != 4 or duplicates:
            raise ValueError(f"Duplicate icon filename near board {filename}: {sorted(duplicates)}")
        seen_boards.add(filename)
        seen_icons.update(icons)
        boards.append(BoardSpec(filename, icons))
    return boards


def is_chroma_green(red: int, green: int, blue: int) -> bool:
    # Capture anti-aliased pixels where the #00FF00 board blends into an edge.
    return green >= 80 and green >= red + 35 and green >= blue + 35


def remove_chroma_key(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    cleaned: list[tuple[int, int, int, int]] = []
    for red, green, blue, alpha in rgba.get_flattened_data():
        if is_chroma_green(red, green, blue):
            cleaned.append((0, 0, 0, 0))
            continue
        if alpha and green >= 180 and green > max(red, blue) + 35:
            green = max(red, blue) + 15
        cleaned.append((red, green, blue, alpha))
    rgba.putdata(cleaned)
    return rgba


def trim_and_center(image: Image.Image, icon_size: int) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("No non-transparent content was found in a quadrant")

    left, top, right, bottom = bbox
    margin = max(8, round(min(image.size) * 0.035))
    left = max(0, left - margin)
    top = max(0, top - margin)
    right = min(image.width, right + margin)
    bottom = min(image.height, bottom + margin)
    trimmed = image.crop((left, top, right, bottom))
    content_limit = max(1, round(icon_size * 0.86))
    trimmed.thumbnail((content_limit, content_limit), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (icon_size, icon_size))
    offset = ((icon_size - trimmed.width) // 2, (icon_size - trimmed.height) // 2)
    canvas.alpha_composite(trimmed, offset)
    return canvas


def count_green_residue(image: Image.Image) -> int:
    return sum(
        alpha > 0 and is_chroma_green(red, green, blue)
        for red, green, blue, alpha in image.convert("RGBA").get_flattened_data()
    )


def validate_icon(image: Image.Image, filename: str) -> dict[str, int]:
    rgba = image.convert("RGBA")
    corners = (
        (0, 0),
        (rgba.width - 1, 0),
        (0, rgba.height - 1),
        (rgba.width - 1, rgba.height - 1),
    )
    if any(rgba.getpixel(point)[3] != 0 for point in corners):
        raise ValueError(f"Transparent corner check failed: {filename}")

    coverage = sum(alpha > 0 for _, _, _, alpha in rgba.get_flattened_data())
    if coverage == 0:
        raise ValueError(f"Empty icon: {filename}")
    green_residue = count_green_residue(rgba)
    if green_residue:
        raise ValueError(f"Green residue in {filename}: {green_residue}")
    return {
        "width": rgba.width,
        "height": rgba.height,
        "coverage": coverage,
        "greenResidue": green_residue,
    }


def ensure_writable(paths: list[Path], overwrite: bool) -> None:
    existing = [path for path in paths if path.exists()]
    if existing and not overwrite:
        preview = ", ".join(str(path) for path in existing[:5])
        raise FileExistsError(f"Outputs already exist; pass --overwrite to replace them: {preview}")


def main() -> None:
    args = parse_args()
    if args.board_size <= 0 or args.board_size % 2:
        raise ValueError("--board-size must be a positive even integer")
    if args.icon_size <= 0:
        raise ValueError("--icon-size must be a positive integer")

    boards = load_manifest(args.manifest)
    source_paths = [args.boards_dir / board.filename for board in boards]
    missing = [path for path in source_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"Missing board files: {missing}")

    normalized_paths = [args.normalized_dir / board.filename for board in boards]
    icon_paths = [args.icons_dir / icon for board in boards for icon in board.icons]
    ensure_writable([*normalized_paths, *icon_paths, args.qa_out], args.overwrite)
    args.normalized_dir.mkdir(parents=True, exist_ok=True)
    args.icons_dir.mkdir(parents=True, exist_ok=True)
    args.qa_out.parent.mkdir(parents=True, exist_ok=True)

    qa_icons: list[dict[str, object]] = []
    quadrant_size = args.board_size // 2
    positions = (
        ("top-left", 0, 0),
        ("top-right", quadrant_size, 0),
        ("bottom-left", 0, quadrant_size),
        ("bottom-right", quadrant_size, quadrant_size),
    )

    for board, source_path, normalized_path in zip(boards, source_paths, normalized_paths):
        with Image.open(source_path) as source:
            normalized = source.convert("RGBA").resize(
                (args.board_size, args.board_size), Image.Resampling.LANCZOS
            )
        normalized.save(normalized_path, "PNG", optimize=True)

        for icon_filename, (quadrant, left, top) in zip(board.icons, positions):
            crop = normalized.crop((left, top, left + quadrant_size, top + quadrant_size))
            icon = remove_chroma_key(trim_and_center(remove_chroma_key(crop), args.icon_size))
            qa = validate_icon(icon, icon_filename)
            icon.save(args.icons_dir / icon_filename, "PNG", optimize=True)
            qa_icons.append(
                {
                    "board": board.filename,
                    "quadrant": quadrant,
                    "icon": icon_filename,
                    **qa,
                }
            )

    report = {
        "boardCount": len(boards),
        "iconCount": len(qa_icons),
        "boardSize": [args.board_size, args.board_size],
        "iconSize": [args.icon_size, args.icon_size],
        "icons": qa_icons,
    }
    args.qa_out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Processed {report['boardCount']} boards and {report['iconCount']} icons; "
        f"all transparent-corner and green-residue checks passed"
    )
    print(f"QA report: {args.qa_out}")


if __name__ == "__main__":
    main()
