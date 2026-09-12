"""Refresh only the generated deployment paths in the isolated Codex config.

Project trust must exist before Codex loads project configuration; a CLI trust
override is too late. Leave all user-managed settings outside this block alone.
"""

import json
import os
from pathlib import Path
import re
import sys
import tempfile


def refresh(config: Path, root: Path) -> None:
    start = "# BEGIN Danus generated paths"
    end = "# END Danus generated paths"
    original = config.read_text() if config.exists() else ""
    def preserve_user_tables(match: re.Match) -> str:
        # Codex can append a new table before our END comment. Remove only
        # generated path tables, preserving e.g. tui.model_availability_nux.
        sections = re.split(r"(?m)(?=^\[)", match.group(1))
        return "".join(section for section in sections if not section.startswith(
            ("[projects.", "[permissions.danus-only.workspace_roots]")
        ))

    body = re.sub(rf"(?m)^{start}\n(.*?)^{end}\n?", preserve_user_tables,
                  original, flags=re.S)
    key = json.dumps(str(root.resolve()), ensure_ascii=False)
    lines = [start]
    if f'[projects.{key}]' not in body:
        lines += [f'[projects.{key}]', 'trust_level = "trusted"']
    if "[permissions.danus-only]" in body:
        lines += ['[permissions.danus-only.workspace_roots]', f'{key} = true']
    updated = body.rstrip() + "\n\n" + "\n".join(lines + [end, ""])
    if updated == original:
        return
    with tempfile.NamedTemporaryFile(mode="w", dir=config.parent, delete=False) as tmp:
        tmp.write(updated)
        if config.exists():
            os.fchmod(tmp.fileno(), config.stat().st_mode & 0o777)
    os.replace(tmp.name, config)


if __name__ == "__main__":
    refresh(Path(sys.argv[1]), Path(sys.argv[2]))
