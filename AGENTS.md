# Diaspora Nearby — Workspace Rules

## UI & Visual Design Invariants

### 1. Strictly Borderless Containers & Controls (Opacity-Only Contrast)
- **No Borders Anywhere**: Never add borders, strokes, or outlines to buttons, pills, chips, badges, cards, sections, banners, modals, inputs, or any other containers across the Flutter app (`lib/`) or the website (`landing/`, `web/`).
  - **Flutter (`lib/`)**:
    - Do **not** use `Border.all(...)`, `Border(...)`, `BoxDecoration(border: ...)`, `RoundedRectangleBorder(side: BorderSide(...))`, `StadiumBorder(side: ...)`, or `OutlineInputBorder(borderSide: BorderSide(...))` with visible colors. Always use `BorderSide.none` or omit `border` / `side`.
    - Prefer `AppTheme.cardDecoration(context)`, `AppTheme.innerDecoration(context)`, `AppTheme.elevationColor(context, level)`, or a minimum background fill opacity (e.g. `color.withValues(alpha: 0.08)`–`0.15`) for contrast against the parent surface.
  - **Website (`landing/`, `web/`)**:
    - Do **not** use CSS `border`, `outline`, or inset border `box-shadow` rings on cards, pills, badges, buttons, sections, or banners.
    - Achieve separation and hierarchy exclusively through subtle background tinting / minimum background opacity (e.g. `background: rgba(255, 255, 255, 0.04)`–`0.08` or surface elevation tokens).

### 2. Popup Modals & Bottom Sheets (Max 8px Horizontal Margin & Blurred Backdrop)
- **Maximum 8px Horizontal Margin**: All popup modals (`Dialog`, `AlertDialog`, custom modal overlays, and floating bottom sheets) must have a horizontal margin of at most `8px` (`<= 8px`) so they sit close to the screen edges and maximize horizontal space.
  - **Flutter (`lib/`)**:
    - On every `Dialog` and `AlertDialog`, always set `insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24)` (never rely on Flutter's default `40px` horizontal `insetPadding`).
    - On `showModalBottomSheet`, use full width (`0px` horizontal margin) or at most `8px` horizontal margin.
  - **Website (`landing/`, `web/`)**:
    - On mobile viewports, modal overlays must use at most `8px` horizontal margin (`margin-inline: 8px` or `width: calc(100vw - 16px)`).
- **Blurred Screen Backdrop**: Every popup modal (`showDialog`, `showModalBottomSheet`, and web modals) must blur the underlying screen (`BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), ...)` in Flutter; `backdrop-filter: blur(10px)` on web) for a clean view.
