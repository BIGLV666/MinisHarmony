/**
 * Clock labels for the inline audio player. Kept pure so the Node harness can
 * cover negative, missing and long values without constructing an AVPlayer.
 */

/** `m:ss` for a millisecond position; negatives and NaN floor to `0:00`. */
export function mediaClock(ms: number): string {
  const safe: number = Number.isFinite(ms) && ms > 0 ? ms : 0;
  const total: number = Math.floor(safe / 1000);
  const minutes: number = Math.floor(total / 60);
  const seconds: number = total % 60;
  return minutes.toString() + ':' + (seconds < 10 ? '0' : '') + seconds.toString();
}
