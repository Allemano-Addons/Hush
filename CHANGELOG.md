# Changelog

## 0.1.0 (in progress)

### Step 1 – Skeleton
- Addon skeleton: `Hush.toc` (Interface 16001), namespace, event dispatcher, callback system.
- `HushDB`: account-wide settings and quick replies, per-character conversations and categories, schema migrations.
- `Compat.lua` with feature detection, name normalization (`Ambiguate`), class colors, timers, screen size.
- `Theme.lua` with all colors, sizes, fonts (Barlow, OFL) and pixel-perfect helpers.
- Public module API stub (global `Hush`).
- `/hush`, `/hush debug`, `/hush version`.
