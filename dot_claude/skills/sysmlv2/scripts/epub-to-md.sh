#!/usr/bin/env bash
set -euo pipefail

# ePub to Markdown converter
# Usage: ./epub-to-md.sh <input.epub> [output.md]

INPUT="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$INPUT" ]]; then
    echo "Usage: $0 <input.epub> [output.md]"
    echo "Example: $0 sysmlv2_202601.epub sysmlv2_202601.md"
    exit 1
fi

if [[ ! -f "$INPUT" ]]; then
    echo "Error: Input file '$INPUT' not found"
    exit 1
fi

# Default output filename: replace .epub with .md
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="${INPUT%.epub}.md"
fi

# Check for pandoc
if ! command -v pandoc &> /dev/null; then
    echo "Error: pandoc not installed"
    echo "Install with: brew install pandoc"
    exit 1
fi

echo "Converting $INPUT -> $OUTPUT"
pandoc "$INPUT" -f epub -t markdown -o "$OUTPUT" --wrap=none

echo "✓ Conversion complete: $OUTPUT"
echo "  Size: $(du -h "$OUTPUT" | cut -f1)"
