#!/usr/bin/env python3
"""WCAG contrast check for the PlusPlus palette (2026-07-28 colour audit).

Run after ANY palette change: `python3 scripts/contrast-check.py`.
Exit code is the number of failures, so a hook or CI job can gate on it.

⚠️ Values are mirrored BY HAND from PlusPlusShared/BrandPalette.swift and
PlusPlus/Theme/Theme.swift. The duplication is deliberate — the point is to
catch a hex moving without anyone re-measuring it, which a script that read
the source automatically would not do. When a check fails after an intended
change, update BOTH sides and say so in the decision entry.

Floors (WCAG 2.2 AA, the level Apple's HIG checklist cites):
  4.5:1  normal text (under 18 pt, or under 14 pt bold)
  3.0:1  large text, and non-text UI components / state indicators
"""
import sys

# ── Palette, light / dark ────────────────────────────────────────────────
LIGHT = dict(
    bg=0xFFFFFF, surface=0xF4F3F1, raised=0xEAE8E4, borderStrong=0xC2C0BA,
    ink=0x232220, ink2=0x6B6965, faint=0x6F6C68,
    accent=0x17914B, done=0x8250DF, selected=0x1668D2, selectedInk=0x0E4FA3,
    notes=0x8F5F00, destructive=0xCF222E, primaryFill=0x232220, onPrimary=0xFFFFFF,
    tintAlpha=0.12,
)
DARK = dict(
    bg=0x201F1D, surface=0x2A2925, raised=0x34322D, borderStrong=0x4E4B43,
    ink=0xF0EDE6, ink2=0x9D9B96, faint=0x949089,
    accent=0x46D17C, done=0xA371F7, selected=0x5CA8F5, selectedInk=0x8CC4FA,
    notes=0xCFA14A, destructive=0xE5534B, primaryFill=0xF0EDE6, onPrimary=0x161616,
    tintAlpha=0.16,
)
# Swipe blocks are FIXED in both schemes: the system draws their label white
# whatever the tint, so the fill is chosen for white rather than for the page.
SWIPE = dict(add=0x0E7A3D, delete=0xCF222E, neutral=0x5F5C58)
RING_ALPHA = 0.8


def _channel(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hexv):
    r, g, b = (hexv >> 16) & 255, (hexv >> 8) & 255, hexv & 255
    return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b)


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(fg, bg, alpha):
    """`fg` composited on `bg` at `alpha`, as a flat hex."""
    out = 0
    for shift in (16, 8, 0):
        f, b = (fg >> shift) & 255, (bg >> shift) & 255
        out |= int(round(f * alpha + b * (1 - alpha))) << shift
    return out


def checks(p):
    """(label, measured, floor) for every pairing the app actually renders."""
    wash_page = over(p["selected"], p["bg"], p["tintAlpha"])
    wash_surface = over(p["selected"], p["surface"], p["tintAlpha"])
    return [
        # Selection: a tinted ground, a ring, and bright text (2026-07-28).
        ("selected label on wash · page", ratio(p["selectedInk"], wash_page), 4.5),
        ("selected label on wash · surface", ratio(p["selectedInk"], wash_surface), 4.5),
        ("selection ring vs surface", ratio(over(p["selected"], p["surface"], RING_ALPHA), p["surface"]), 3.0),
        ("selection ring vs page", ratio(over(p["selected"], p["bg"], RING_ALPHA), p["bg"]), 3.0),
        # Text tiers on the two grounds copy actually sits on.
        ("textPrimary on surface", ratio(p["ink"], p["surface"]), 4.5),
        ("textSecondary on surface", ratio(p["ink2"], p["surface"]), 4.5),
        ("textFaint on surface", ratio(p["faint"], p["surface"]), 4.5),
        ("advisory amber on surface", ratio(p["notes"], p["surface"]), 4.5),
        ("advisory amber on page", ratio(p["notes"], p["bg"]), 4.5),
        ("kit tag ink on surfaceRaised", ratio(p["ink"], p["raised"]), 4.5),
        ("onPrimary on primaryFill", ratio(p["onPrimary"], p["primaryFill"]), 4.5),
        # Status colours as non-text indicators (set bar, rail nodes, pips).
        ("done vs page", ratio(p["done"], p["bg"]), 3.0),
        ("accent vs page", ratio(p["accent"], p["bg"]), 3.0),
    ]


def main():
    failures = 0
    for name, palette in (("light", LIGHT), ("dark", DARK)):
        print("── " + name.upper())
        for label, measured, floor in checks(palette):
            ok = measured >= floor
            failures += 0 if ok else 1
            print("   {:<34} {:5.2f}:1  (>= {})  {}".format(
                label, measured, floor, "PASS" if ok else "FAIL"))
        print()

    print("── SWIPE BLOCKS (fixed both schemes, system-drawn white label)")
    for key, value in SWIPE.items():
        measured = ratio(0xFFFFFF, value)
        ok = measured >= 4.5
        failures += 0 if ok else 1
        print("   white on swipe{:<9} {:5.2f}:1  (>= 4.5)  {}".format(
            key.capitalize(), measured, "PASS" if ok else "FAIL"))

    # ⚠️ Not a contrast rule, but the reason BlockBar honours Differentiate
    # Without Color: the two status hues are a luminance near-tie, so those
    # states are separable by hue alone unless shape carries them (WCAG 1.4.1).
    print("\n── HUE-ONLY DISTINCTIONS (need a shape cue; no ratio can pass them)")
    for name, p in (("light", LIGHT), ("dark", DARK)):
        print("   {:<5} set bar done vs live  {:5.2f}:1  → Differentiate Without"
              " Color gives solid / hollow / taller".format(name, ratio(p["done"], p["accent"])))

    print("\n{} failure(s)".format(failures))
    return failures


if __name__ == "__main__":
    sys.exit(main())
