import { t } from './I18n';
/** Accent presets offered in Settings; any `#RRGGBB` value is accepted. */
export interface AccentPreset {
  name: string;
  value: string;
}

export const ACCENT_PRESETS: AccentPreset[] = [
  { name: '蓝', value: '#2F6BFF' },
  { name: '青', value: '#0EA5A4' },
  { name: '绿', value: '#16A34A' },
  { name: '紫', value: '#7C3AED' },
  { name: '橙', value: '#EA580C' },
  { name: '红', value: '#DC2626' }
];

export const FONT_SCALE_OPTIONS: number[] = [0.9, 1, 1.15, 1.3];

export function fontScaleLabel(scale: number): string {
  if (scale < 0.95) {
    return t('小');
  }
  if (scale < 1.08) {
    return t('标准');
  }
  if (scale < 1.22) {
    return t('大');
  }
  return t('特大');
}
