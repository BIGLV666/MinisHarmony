/**
 * Extension-based media classification for previews. Mirrors the attachment
 * picker's accepted types; anything unknown stays on the text/binary path.
 */

const VIDEO_EXT: string[] = ['mp4', 'webm', 'mov', 'm4v', 'mkv'];
const AUDIO_EXT: string[] = ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'flac'];
const IMAGE_EXT: string[] = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];

/** Returns `video`, `audio`, `image` or `''` for a name or relative path. */
export function mediaKindOf(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot === name.length - 1) {
    return '';
  }
  const ext: string = name.substring(dot + 1).toLowerCase();
  if (VIDEO_EXT.indexOf(ext) >= 0) {
    return 'video';
  }
  if (AUDIO_EXT.indexOf(ext) >= 0) {
    return 'audio';
  }
  if (IMAGE_EXT.indexOf(ext) >= 0) {
    return 'image';
  }
  return '';
}
