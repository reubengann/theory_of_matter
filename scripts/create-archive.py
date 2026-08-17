"""Create a ZIP while preserving executable mode bits on POSIX."""

from __future__ import annotations

import pathlib
import sys
import zipfile


def create_archive(source: pathlib.Path, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(
        destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(source).as_posix())


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: create-archive.py SOURCE DESTINATION")
    create_archive(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
