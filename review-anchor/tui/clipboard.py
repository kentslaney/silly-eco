"""
System clipboard access.

macOS ``pbcopy``/``pbpaste`` first, since that is where the copy/paste loop with
the Antigravity IDE actually happens; X11 / Wayland fallbacks so the tool is
usable over ssh or in a Linux VM.  Everything degrades to a file under the repo
(``.review_clipboard``) rather than failing, so the workflow never dead-ends.
"""

import os
import shutil
import subprocess
from typing import List, Optional

FALLBACK = ".review_clipboard"

_COPY: List[List[str]] = [
    ["pbcopy"],
    ["wl-copy"],
    ["xclip", "-selection", "clipboard"],
    ["xsel", "--clipboard", "--input"],
]
_PASTE: List[List[str]] = [
    ["pbpaste"],
    ["wl-paste", "--no-newline"],
    ["xclip", "-selection", "clipboard", "-o"],
    ["xsel", "--clipboard", "--output"],
]


class Clipboard:
    fallback_dir: Optional[str] = None

    @classmethod
    def _fallback_path(cls) -> str:
        return os.path.join(cls.fallback_dir or os.getcwd(), FALLBACK)

    @staticmethod
    def _first(candidates: List[List[str]]) -> Optional[List[str]]:
        for cmd in candidates:
            if shutil.which(cmd[0]):
                return cmd
        return None

    @classmethod
    def set_text(cls, text: str) -> str:
        cmd = cls._first(_COPY)
        if cmd:
            try:
                subprocess.run(cmd, input=text, text=True, check=True)
                return cmd[0]
            except (OSError, subprocess.SubprocessError):
                pass
        path = cls._fallback_path()
        try:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            return os.path.basename(path)
        except OSError:
            return ""

    @classmethod
    def get_text(cls) -> str:
        cmd = cls._first(_PASTE)
        if cmd:
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, check=False)
                if res.returncode == 0:
                    return res.stdout
            except (OSError, subprocess.SubprocessError):
                pass
        try:
            with open(cls._fallback_path(), "r", encoding="utf-8") as fh:
                return fh.read()
        except OSError:
            return ""
