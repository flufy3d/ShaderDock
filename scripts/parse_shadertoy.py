#!/usr/bin/env python3
"""
Utility for repackaging ShaderToy JSON dumps into the local ShaderDock layout.

The script expects the raw ShaderToy JSON (as returned by the POST request to
https://www.shadertoy.com/shadertoy) and produces:
  * One GLSL file per render pass (based on the pass name).
  * A cleaned, easy-to-read demo.json payload with trimmed fields and local paths.
  * A grouped text file containing resource download URLs for textures/cubemaps.

All artefacts are written into assets/demos/<shader_name_with_underscores>.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Dict, List, Optional


SHADERTOY_BASE_URL = "https://www.shadertoy.com"
TEXTURE_TYPES = {"texture", "cubemap"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Repackage ShaderToy JSON dumps for ShaderDock."
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Path to the raw ShaderToy JSON file that was downloaded manually.",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=None,
        help=(
            "Root folder where demo assets will be written. "
            "Defaults to <repo>/assets/demos."
        ),
    )
    parser.add_argument(
        "--base-url",
        default=SHADERTOY_BASE_URL,
        help="Base URL to prepend to resource filepaths (default: %(default)s).",
    )
    return parser.parse_args()


def load_payload(path: Path) -> Dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(raw, list):
        if len(raw) != 1:
            raise ValueError("Expected the top-level list to contain a single entry.")
        return raw[0]
    if isinstance(raw, dict):
        return raw
    raise TypeError("Unexpected JSON structure. Expected dict or single-item list.")


def sanitize_demo_name(name: str, fallback: str) -> str:
    replaced = name.strip().replace(" ", "_")
    cleaned = re.sub(r"[^\w]+", "_", replaced)
    cleaned = re.sub(r"_+", "_", cleaned).strip("_")
    return cleaned or fallback


def sanitize_pass_name(name: str, fallback: str, used: set) -> str:
    lowered = name.strip().lower().replace(" ", "_")
    cleaned = re.sub(r"[^\w]+", "_", lowered)
    cleaned = re.sub(r"_+", "_", cleaned).strip("_") or fallback
    candidate = f"{cleaned}.glsl"
    counter = 1
    while candidate in used:
        candidate = f"{cleaned}_{counter}.glsl"
        counter += 1
    used.add(candidate)
    return candidate


def rewrite_filepath(resource_type: str, filepath: Optional[str]) -> Optional[str]:
    if not filepath or resource_type not in TEXTURE_TYPES:
        return None if resource_type == "buffer" else filepath
    filename = Path(filepath).name
    prefix = "/textures" if resource_type == "texture" else "/cubemaps"
    return f"{prefix}/{filename}"


class ResourceCollector:
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")
        self._entries: Dict[str, List[str]] = {}
        self._seen: set[str] = set()

    def add(self, filepath: Optional[str], resource_type: str) -> None:
        if not filepath or resource_type not in TEXTURE_TYPES:
            return
        self._push_entry(filepath, resource_type)
        if resource_type == "cubemap":
            stem, ext = os.path.splitext(filepath)
            for idx in range(1, 6):
                extra_path = f"{stem}_{idx}{ext}"
                self._push_entry(extra_path, resource_type)

    def _push_entry(self, filepath: str, resource_type: str) -> None:
        normalized = filepath if filepath.startswith("/") else f"/{filepath}"
        url = f"{self.base_url}{normalized}"
        if url in self._seen:
            return
        self._seen.add(url)
        self._entries.setdefault(resource_type, []).append(url)

    def write(self, destination: Path) -> None:
        order = ["texture", "cubemap"]
        lines: List[str] = []
        for resource_type in order:
            entries = self._entries.get(resource_type)
            if not entries:
                continue
            header = "TEXTURES" if resource_type == "texture" else "CUBEMAPS"
            lines.append(f"[{header}]")
            lines.append("[")
            for idx, url in enumerate(entries):
                suffix = "," if idx < len(entries) - 1 else ""
                lines.append(f'  "{url}"{suffix}')
            lines.append("].forEach(url => window.open(url));")
            lines.append("")
        content = "\n".join(lines).rstrip() + ("\n" if lines else "")
        destination.write_text(content, encoding="utf-8")


def ensure_trailing_newline(text: str) -> str:
    return text if text.endswith("\n") else f"{text}\n"


def clean_info(info: Dict) -> Dict:
    keep_keys = (
        "id",
        "name",
        "username",
        "description",
        "tags",
        "likes",
        "published",
    )
    return {key: info.get(key) for key in keep_keys if key in info}


def process_shader(
    payload: Dict, demo_dir: Path, resource_collector: ResourceCollector
) -> Dict:
    cleaned = {
        "ver": payload.get("ver"),
        "info": clean_info(payload.get("info", {})),
        "renderpass": [],
    }
    used_filenames: set[str] = set()

    for render_pass in payload.get("renderpass", []):
        filename = sanitize_pass_name(
            render_pass.get("name", "pass"),
            fallback="renderpass",
            used=used_filenames,
        )
        shader_code = render_pass.get("code", "")
        (demo_dir / filename).write_text(
            ensure_trailing_newline(shader_code), encoding="utf-8"
        )

        # Inputs
        cleaned_inputs = []
        for input_entry in render_pass.get("inputs", []):
            resource_type = input_entry.get("type") or ""
            filepath = input_entry.get("filepath")
            remapped = rewrite_filepath(resource_type, filepath)
            resource_collector.add(filepath, resource_type)
            cleaned_inputs.append(
                {
                    "id": input_entry.get("id"),
                    "type": resource_type,
                    "channel": input_entry.get("channel"),
                    "filepath": remapped,
                    "sampler": input_entry.get("sampler"),
                    "published": input_entry.get("published"),
                }
            )

        # Outputs (for DAG construction)
        cleaned_outputs = []
        for output_entry in render_pass.get("outputs", []):
            cleaned_outputs.append(
                {
                    "id": output_entry.get("id"),
                    "channel": output_entry.get("channel"),
                }
            )

        cleaned["renderpass"].append(
            {
                "name": render_pass.get("name"),
                "type": render_pass.get("type"),
                "source": filename,
                "inputs": cleaned_inputs,
                "outputs": cleaned_outputs,
            }
        )
    return cleaned


def main() -> None:
    args = parse_args()

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    output_root = (
        args.output_root if args.output_root is not None else repo_root / "assets" / "demos"
    )
    output_root.mkdir(parents=True, exist_ok=True)

    payload = load_payload(args.input)

    shader_info = payload.get("info", {})
    demo_folder_name = sanitize_demo_name(
        shader_info.get("name", "demo"),
        fallback=shader_info.get("id", "demo"),
    )
    demo_dir = output_root / demo_folder_name
    demo_dir.mkdir(parents=True, exist_ok=True)

    resources = ResourceCollector(args.base_url)
    cleaned_payload = process_shader(payload, demo_dir, resources)

    json_path = demo_dir / "demo.json"
    json_path.write_text(
        json.dumps(cleaned_payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    resource_list_path = demo_dir / "resource_urls.txt"
    resources.write(resource_list_path)

    print(f"Wrote GLSL files, {json_path.name}, and {resource_list_path.name} to {demo_dir}")


if __name__ == "__main__":
    main()
