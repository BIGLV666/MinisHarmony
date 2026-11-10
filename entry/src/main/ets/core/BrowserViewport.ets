/**
 * Numeric viewport for the in-app browser. ArkWeb has no direct
 * "set viewport size" call, but a Web component's CSS viewport follows its
 * layout size, so the page surface can be given a fixed width/height and
 * centered in a scrollable area. 0 means "fill the panel".
 */
export const VIEWPORT_MIN: number = 200;
export const VIEWPORT_MAX: number = 2000;

/** Parse a user-entered size; empty or invalid input returns 0 (auto). */
export function parseViewportSize(raw: string): number {
  const text: string = raw.trim();
  if (text.length === 0) {
    return 0;
  }
  const value: number = Number(text);
  if (!Number.isFinite(value) || value < VIEWPORT_MIN || value > VIEWPORT_MAX) {
    return 0;
  }
  return Math.round(value);
}

/** True when both sides were filled; the custom surface needs both. */
export function customViewport(width: number, height: number): boolean {
  return width >= VIEWPORT_MIN && width <= VIEWPORT_MAX &&
    height >= VIEWPORT_MIN && height <= VIEWPORT_MAX;
}
