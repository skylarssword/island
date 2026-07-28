#!/usr/bin/env bash
# tide-video-convert.sh
# Converts videos in SRC to 1080p30 mp4, archives originals to ARCHIVE.
# Reads paths from ~/.config/tide-island/video-convert.conf — do not
# hardcode paths here. Run setup-video-converter.sh to generate that file.

set -euo pipefail

CONF="$HOME/.config/tide-island/video-convert.conf"

if [[ ! -f "$CONF" ]]; then
    echo "tide-video-convert: config not found at $CONF" >&2
    echo "Run setup-video-converter.sh to set up." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$CONF"

: "${SRC:?SRC not set in $CONF}"
: "${DST:?DST not set in $CONF}"
: "${ARCHIVE:?ARCHIVE not set in $CONF}"

mkdir -p "$DST" "$ARCHIVE"

shopt -s nullglob
for f in "$SRC"/*.{mp4,mov,mkv,webm,avi}; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    base="${name%.*}"
    out="$DST/${base}.mp4"

    if [[ -f "$out" ]]; then
        echo "tide-video-convert: skipping $name (already converted)"
        continue
    fi

    echo "tide-video-convert: converting $name → $out"
    ffmpeg -i "$f" \
        -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" \
        -r 30 \
        -c:v libx264 -crf 18 -preset fast \
        -c:a aac -b:a 192k \
        -movflags +faststart \
        "$out" \
        && mv "$f" "$ARCHIVE/$name" \
        || echo "tide-video-convert: failed on $name" >&2
done
