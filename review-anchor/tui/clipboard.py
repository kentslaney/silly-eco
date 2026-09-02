"""
Clipboard helper for macOS integration.
Uses pbcopy and pbpaste for system-wide clipboard sharing with Antigravity IDE.
"""

import subprocess
from typing import Optional


class Clipboard:
    @staticmethod
    def get_text() -> str:
        """Fetch text from system clipboard using pbpaste."""
        try:
            res = subprocess.run(["pbpaste"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
            if res.returncode == 0:
                return res.stdout
        except Exception:
            pass
        return ""

    @staticmethod
    def set_text(text: str) -> bool:
        """Copy text to system clipboard using pbcopy."""
        try:
            res = subprocess.run(["pbcopy"], input=text, text=True, check=False)
            return res.returncode == 0
        except Exception:
            return False
