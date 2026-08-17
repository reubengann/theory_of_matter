"""Defaults loaded by IPython for the theory-of-matter distribution."""

import matplotlib as mpl
import matplotlib.pyplot as plt
import matplotlib_inline.backend_inline
import numpy as np

from matterlib import spp


def setup_matplotlib(
    *,
    backend: str = "inline",
    dark: bool = True,
    svg: bool = True,
) -> None:
    """Configure presentation-friendly matplotlib defaults."""
    try:
        from IPython.core.getipython import get_ipython

        ip = get_ipython()
        if ip and backend:
            ip.run_line_magic("matplotlib", backend)
    except Exception:
        pass

    formats = ["png"]
    if svg:
        formats.insert(0, "svg")
    matplotlib_inline.backend_inline.set_matplotlib_formats(*formats)

    if dark:
        plt.style.use(["dark_background"])

    mpl.rcParams.update(
        {
            "figure.figsize": (8, 5),
            "figure.dpi": 120,
            "font.size": 16,
            "axes.titlesize": 18,
            "axes.labelsize": 16,
            "xtick.labelsize": 14,
            "ytick.labelsize": 14,
            "legend.fontsize": 14,
            "lines.linewidth": 2,
            "lines.markersize": 8,
            "figure.autolayout": True,
        }
    )


setup_matplotlib()
