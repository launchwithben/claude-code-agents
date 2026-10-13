---
name: design-rules
description: >-
  This project's non-negotiable design rules: tokens, light/dark, icons, components, the visual register. Preloaded into role-ui and role-concept; use when designing or building any page or component.
---

# Design rules (distilled; the source is cited on every rule)

<!--
  Same instructions as build-rules: under ~900 words, orders not advice, cite the source.
  Everything below is an EXAMPLE. Replace it with your design system's real rules.
-->

## Tokens
1. Colours, spacing and radii come from design tokens only. No hex values, no inline `style=""`. (src/styles/tokens.css)
2. Every colour token has a light AND a dark value. Check both themes before handback. (DESIGN.md)

## Components
3. Search `src/components/` before building. Extend an existing component rather than forking it.
4. Icons come from the one icon set the project uses. Never paste an SVG from somewhere else. (DESIGN.md § Icons)

## Layout
5. Works at 375px wide with no horizontal scroll. Tap targets at least 44px.
6. One primary button per screen. Secondary actions look secondary.

## Register
7. Example: calm and premium. Fewer elements, more space, no badges or exclamation marks. (DESIGN.md § Voice)
