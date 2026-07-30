# 001 — Smooth sidebar collapse animation

- **Status**: DONE
- **Commit**: 9bf534f
- **Severity**: HIGH
- **Category**: Easing & duration / Performance
- **Estimated scope**: 1 file (assets/css/app.css), ~30 lines

## Problem

The sidebar collapse feels rocky because of three compounding issues:

**1. `display: none !important` causes an instant visual snap** (assets/css/app.css:221)
```css
/* current */
#sidebar-aside.sidebar-collapsed #sidebar-brand-text,
#sidebar-aside.sidebar-collapsed #site-switch-form,
#sidebar-aside.sidebar-collapsed #sidebar-portal-switch {
  opacity: 0;
  max-width: 0;
  display: none !important; /* <-- instantly removes element while sidebar is mid-animation */
  overflow: hidden;
}
```

**2. Layout properties animate on account card** (assets/css/app.css:255-258)
```css
/* current */
#sidebar-account-card {
  transition:
    background-color 200ms ease,
    padding 200ms ease,      /* layout property — triggers relayout every frame */
    border-radius 200ms ease; /* paint property */
}
```

**3. Weak `ease-in-out` on sidebar shell** (lib/thamani_dawa_web/components/layouts.ex:276)
```
class="... transition-[transform,width] duration-200 ease-in-out ..."
```
Tailwind's `ease-in-out` = `cubic-bezier(0.4, 0, 0.2, 1)` — symmetrical and mechanical, with a slow start that delays responsiveness. A drawer should start fast.

## Target

- Brand text and portal switch fade via `opacity` only — no `display` toggling
- Account card transitions `background-color` only
- Sidebar shell uses `cubic-bezier(0.32, 0.72, 0, 1)` (the iOS drawer curve from AUDIT.md)
- All durations unified at 220ms so every element settles simultaneously
- Asymmetric label timing: fast fade-out (80ms) when collapsing, delayed fade-in (100ms delay) when expanding — labels disappear before sidebar contracts, reappear after sidebar opens

## Steps

See implementation in this commit.
