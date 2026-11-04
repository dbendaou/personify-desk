#!/usr/bin/env python3
"""Build the Personify Desk app icon from the approved squircle artwork.

The master is a 1024px PNG with transparent corners. --iconset writes the
sizes iconutil expects (16 through 1024, @1x and @2x).
"""

from __future__ import annotations

import argparse
import math
import struct
import zlib
from pathlib import Path

MASTER = 1024
ICONSET_SIZES = (
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
)


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    rows = bytearray()
    stride = width * 4
    for y in range(height):
        rows.append(0)
        rows.extend(rgba[y * stride : (y + 1) * stride])
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def mix(a: tuple[int, int, int, int], b: tuple[int, int, int, int], t: float) -> tuple[int, int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))  # type: ignore[return-value]


def over(dst: tuple[int, int, int, int], src: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    sa = src[3] / 255
    if sa <= 0:
        return dst
    da = dst[3] / 255
    out_a = sa + da * (1 - sa)
    if out_a <= 0:
        return (0, 0, 0, 0)
    rgb = []
    for i in range(3):
        rgb.append(int((src[i] * sa + dst[i] * da * (1 - sa)) / out_a))
    return (rgb[0], rgb[1], rgb[2], int(out_a * 255))


def in_squircle(x: float, y: float) -> float:
    ax = abs(x)
    ay = abs(y)
    value = ax ** 5 + ay ** 5
    if value < 0.90:
        return 1.0
    if value > 1.04:
        return 0.0
    return max(0.0, min(1.0, (1.04 - value) / 0.14))


def sd_round_box(nx: float, ny: float, cx: float, cy: float, half_w: float, half_h: float, radius: float) -> float:
    dx = abs(nx - cx) - half_w + radius
    dy = abs(ny - cy) - half_h + radius
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def coverage(distance: float, edge: float = 0.012) -> float:
    return max(0.0, min(1.0, 0.5 - distance / (edge * 2)))


def render(size: int) -> bytes:
    pixels = bytearray(size * size * 4)
    blue = (18, 92, 214, 255)
    teal = (32, 196, 206, 255)
    white = (255, 255, 255, 255)
    yellow = (255, 196, 48, 255)
    fan = (186, 230, 245, 255)
    for y in range(size):
        ny = ((y + 0.5) / size) * 2 - 1
        for x in range(size):
            nx = ((x + 0.5) / size) * 2 - 1
            cover = in_squircle(nx / 0.90, ny / 0.90)
            if cover <= 0:
                continue
            gradient = (nx * 0.42 + ny * 0.72 + 1) / 2
            color = mix(blue, teal, gradient)
            color = mix(color, (255, 255, 255, 255), max(0.0, 0.16 - ny * 0.08) * 0.22)
            color = (color[0], color[1], color[2], int(255 * cover))
            composed = color
            shadow = coverage(sd_round_box(nx, ny - 0.018, 0.0, 0.02, 0.52, 0.47, 0.11), 0.02)
            frame_here = frame_coverage(nx, ny)
            if shadow > 0 and frame_here < 0.2:
                composed = over(composed, (6, 32, 70, int(90 * shadow * cover)))
            frame = frame_here
            if frame > 0:
                composed = over(composed, (white[0], white[1], white[2], int(255 * frame)))
            slat = slat_coverage(nx, ny)
            if slat > 0:
                composed = over(composed, (white[0], white[1], white[2], int(255 * slat)))
            sensor = coverage(math.hypot(nx - 0.38, ny + 0.40) - 0.022)
            if sensor > 0:
                composed = over(composed, (255, 255, 255, int(235 * sensor)))
            led = math.hypot(nx + 0.38, ny + 0.40)
            glow = max(0.0, 1.0 - led / 0.07)
            if glow > 0:
                composed = over(composed, (yellow[0], yellow[1], yellow[2], int(150 * glow * glow)))
            if led < 0.032:
                composed = over(composed, yellow)
            blade = fan_coverage(nx, ny)
            if blade > 0:
                composed = over(composed, (fan[0], fan[1], fan[2], int(255 * blade)))
            i = (y * size + x) * 4
            pixels[i : i + 4] = bytes(composed)
    return bytes(pixels)


def frame_coverage(nx: float, ny: float) -> float:
    outer = sd_round_box(nx, ny, 0.0, 0.0, 0.52, 0.47, 0.10)
    inner = sd_round_box(nx, ny, 0.0, 0.01, 0.455, 0.405, 0.07)
    outer_in = coverage(outer)
    inner_in = coverage(inner)
    return max(0.0, outer_in * (1.0 - inner_in))


def slat_coverage(nx: float, ny: float) -> float:
    # Only inside the window opening.
    if sd_round_box(nx, ny, 0.0, 0.01, 0.44, 0.39, 0.06) > 0:
        return 0.0
    total = 0.0
    for index, sy in enumerate((-0.30, -0.21, -0.12, -0.03, 0.06)):
        half = 0.022
        distance = abs(ny - sy) - half
        span = abs(nx) - 0.34
        cap = math.hypot(max(span, 0.0), max(distance, 0.0)) + min(max(span, distance), 0.0)
        total = max(total, coverage(cap, 0.008))
        if index == 4:
            break
    return total


def fan_coverage(nx: float, ny: float) -> float:
    cx, cy = 0.26, 0.26
    dx, dy = nx - cx, ny - cy
    radius = math.hypot(dx, dy)
    if radius > 0.12 or radius < 0.022:
        return 0.0
    angle = math.atan2(dy, dx)
    # Five curved arms. The phase shifts with radius so the blades sweep.
    phase = angle * 5 - radius * 18
    arm = math.cos(phase)
    if arm < 0.35:
        return 0.0
    edge = (arm - 0.35) / 0.65
    hub = 1.0 if radius < 0.045 else edge
    return max(0.0, min(1.0, hub))


def downsample(src: bytes, src_size: int, dst_size: int) -> bytes:
    if dst_size == src_size:
        return src
    scale = src_size // dst_size
    out = bytearray(dst_size * dst_size * 4)
    for y in range(dst_size):
        for x in range(dst_size):
            acc = [0, 0, 0, 0]
            count = scale * scale
            for oy in range(scale):
                for ox in range(scale):
                    sx = x * scale + ox
                    sy = y * scale + oy
                    i = (sy * src_size + sx) * 4
                    for channel in range(4):
                        acc[channel] += src[i + channel]
            o = (y * dst_size + x) * 4
            out[o : o + 4] = bytes(value // count for value in acc)
    return bytes(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--master", type=Path, default=Path("packaging/AppIcon-1024.png"))
    parser.add_argument("--iconset", type=Path, default=None)
    args = parser.parse_args()
    master = render(MASTER)
    write_png(args.master, MASTER, MASTER, master)
    if args.iconset:
        args.iconset.mkdir(parents=True, exist_ok=True)
        for name, size in ICONSET_SIZES:
            image = master if size == MASTER else downsample(master, MASTER, size)
            write_png(args.iconset / name, size, size, image)


if __name__ == "__main__":
    main()
