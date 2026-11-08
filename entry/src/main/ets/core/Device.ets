/**
 * Pure helpers behind the device-data tools (calendar / contacts / location /
 * weather). Keeping parsing and formatting here lets them run under Node.
 */

/** Open-Meteo needs no key, so weather works offline-first without settings. */
export const GEOCODE_ENDPOINT: string = 'https://geocoding-api.open-meteo.com/v1/search';
export const WEATHER_ENDPOINT: string = 'https://api.open-meteo.com/v1/forecast';
export const MAX_WEATHER_DAYS: number = 7;
export const MAX_LISTED_EVENTS: number = 50;
export const MAX_LISTED_CONTACTS: number = 20;

export interface GeoPlace {
  name: string;
  country: string;
  admin1: string;
  latitude: number;
  longitude: number;
}

export interface WeatherNow {
  time: string;
  temperature: number;
  apparent: number;
  humidity: number;
  wind: number;
  precipitation: number;
  code: number;
}

export interface WeatherDay {
  date: string;
  code: number;
  max: number;
  min: number;
  precipitationProbability: number;
}

export interface WeatherReport {
  current: WeatherNow | null;
  days: WeatherDay[];
}

export function weatherCodeText(code: number): string {
  if (code === 0) {
    return '晴';
  }
  if (code === 1) {
    return '大部晴朗';
  }
  if (code === 2) {
    return '多云';
  }
  if (code === 3) {
    return '阴';
  }
  if (code === 45 || code === 48) {
    return '雾';
  }
  if (code === 51 || code === 53 || code === 55) {
    return '毛毛雨';
  }
  if (code === 56 || code === 57) {
    return '冻毛毛雨';
  }
  if (code === 61) {
    return '小雨';
  }
  if (code === 63) {
    return '中雨';
  }
  if (code === 65) {
    return '大雨';
  }
  if (code === 66 || code === 67) {
    return '冻雨';
  }
  if (code === 71) {
    return '小雪';
  }
  if (code === 73) {
    return '中雪';
  }
  if (code === 75) {
    return '大雪';
  }
  if (code === 77) {
    return '米雪';
  }
  if (code === 80 || code === 81 || code === 82) {
    return '阵雨';
  }
  if (code === 85 || code === 86) {
    return '阵雪';
  }
  if (code === 95) {
    return '雷暴';
  }
  if (code === 96 || code === 99) {
    return '雷暴伴冰雹';
  }
  return '未知天气';
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** `YYYY-MM-DD HH:mm` in local time; used in tool output and event lists. */
export function formatDateTime(ms: number): string {
  const date: Date = new Date(ms);
  return date.getFullYear().toString() + '-' + pad2(date.getMonth() + 1) + '-' +
    pad2(date.getDate()) + ' ' + pad2(date.getHours()) + ':' +
    pad2(date.getMinutes());
}

/**
 * Accepts `YYYY-MM-DD [HH:mm[:ss]]`, ISO 8601, or epoch seconds/milliseconds.
 * Returns -1 when the text cannot be understood.
 */
export function parseTimeArg(text: string, now: number): number {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return -1;
  }
  if (/^\d{13}$/.test(trimmed)) {
    return Number(trimmed);
  }
  if (/^\d{10}$/.test(trimmed)) {
    return Number(trimmed) * 1000;
  }
  const basic: RegExpMatchArray | null =
    trimmed.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$/);
  if (basic !== null) {
    const year: number = Number(basic[1]);
    const month: number = Number(basic[2]);
    const day: number = Number(basic[3]);
    const hour: number = basic[4] !== undefined ? Number(basic[4]) : 0;
    const minute: number = basic[5] !== undefined ? Number(basic[5]) : 0;
    const second: number = basic[6] !== undefined ? Number(basic[6]) : 0;
    if (month < 1 || month > 12 || day < 1 || day > 31 ||
      hour > 23 || minute > 59 || second > 59) {
      return -1;
    }
    const parsed: number = new Date(year, month - 1, day, hour, minute, second).getTime();
    return Number.isNaN(parsed) ? -1 : parsed;
  }
  const fallback: number = Date.parse(trimmed);
  if (!Number.isNaN(fallback) && fallback > 0) {
    return fallback;
  }
  // A bare time today, e.g. "09:30".
  const timeOnly: RegExpMatchArray | null = trimmed.match(/^(\d{1,2}):(\d{2})$/);
  if (timeOnly !== null) {
    const date: Date = new Date(now);
    const hour: number = Number(timeOnly[1]);
    const minute: number = Number(timeOnly[2]);
    if (hour > 23 || minute > 59) {
      return -1;
    }
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(),
      hour, minute, 0).getTime();
  }
  return -1;
}

export function clampWeatherDays(days: number): number {
  if (!Number.isFinite(days) || days < 1) {
    return 1;
  }
  const whole: number = Math.floor(days);
  return whole > MAX_WEATHER_DAYS ? MAX_WEATHER_DAYS : whole;
}

export function geocodeUrl(city: string): string {
  return GEOCODE_ENDPOINT + '?name=' + encodeURIComponent(city.trim()) +
    '&count=1&language=zh&format=json';
}

export function weatherUrl(lat: number, lon: number, days: number): string {
  return WEATHER_ENDPOINT +
    '?latitude=' + lat.toString() + '&longitude=' + lon.toString() +
    '&current=temperature_2m,relative_humidity_2m,apparent_temperature,' +
    'precipitation,weather_code,wind_speed_10m' +
    '&daily=weather_code,temperature_2m_max,temperature_2m_min,' +
    'precipitation_probability_max' +
    '&timezone=auto&forecast_days=' + clampWeatherDays(days).toString();
}

interface RawGeoResult {
  name?: string;
  country?: string;
  admin1?: string;
  latitude?: number;
  longitude?: number;
}

interface RawGeoResponse {
  results?: RawGeoResult[];
}

export function parseGeoJson(text: string): GeoPlace | null {
  let raw: RawGeoResponse;
  try {
    raw = JSON.parse(text) as RawGeoResponse;
  } catch (e) {
    return null;
  }
  if (raw === null || raw === undefined || raw.results === undefined ||
    !Array.isArray(raw.results) || raw.results.length === 0) {
    return null;
  }
  const first: RawGeoResult = raw.results[0];
  if (first === null || first === undefined || typeof first.latitude !== 'number' ||
    typeof first.longitude !== 'number') {
    return null;
  }
  return {
    name: typeof first.name === 'string' ? first.name : '',
    country: typeof first.country === 'string' ? first.country : '',
    admin1: typeof first.admin1 === 'string' ? first.admin1 : '',
    latitude: first.latitude,
    longitude: first.longitude
  };
}

interface RawCurrent {
  time?: string;
  temperature_2m?: number;
  apparent_temperature?: number;
  relative_humidity_2m?: number;
  wind_speed_10m?: number;
  precipitation?: number;
  weather_code?: number;
}

interface RawDaily {
  time?: string[];
  weather_code?: number[];
  temperature_2m_max?: number[];
  temperature_2m_min?: number[];
  precipitation_probability_max?: number[];
}

interface RawWeatherResponse {
  current?: RawCurrent;
  daily?: RawDaily;
}

function numberOr(value: number | undefined, fallback: number): number {
  return typeof value === 'number' ? value : fallback;
}

export function parseWeatherJson(text: string): WeatherReport {
  let raw: RawWeatherResponse;
  try {
    raw = JSON.parse(text) as RawWeatherResponse;
  } catch (e) {
    return { current: null, days: [] };
  }
  if (raw === null || raw === undefined) {
    return { current: null, days: [] };
  }
  let current: WeatherNow | null = null;
  if (raw.current !== undefined && raw.current !== null) {
    current = {
      time: typeof raw.current.time === 'string' ? raw.current.time : '',
      temperature: numberOr(raw.current.temperature_2m, 0),
      apparent: numberOr(raw.current.apparent_temperature, 0),
      humidity: numberOr(raw.current.relative_humidity_2m, 0),
      wind: numberOr(raw.current.wind_speed_10m, 0),
      precipitation: numberOr(raw.current.precipitation, 0),
      code: numberOr(raw.current.weather_code, -1)
    };
  }
  const days: WeatherDay[] = [];
  const daily: RawDaily | undefined = raw.daily;
  if (daily !== undefined && daily !== null && Array.isArray(daily.time)) {
    const count: number = daily.time.length;
    for (let i = 0; i < count; i++) {
      days.push({
        date: daily.time[i],
        code: daily.weather_code !== undefined && i < daily.weather_code.length
          ? daily.weather_code[i]
          : -1,
        max: daily.temperature_2m_max !== undefined && i < daily.temperature_2m_max.length
          ? daily.temperature_2m_max[i]
          : 0,
        min: daily.temperature_2m_min !== undefined && i < daily.temperature_2m_min.length
          ? daily.temperature_2m_min[i]
          : 0,
        precipitationProbability: daily.precipitation_probability_max !== undefined &&
          i < daily.precipitation_probability_max.length
          ? daily.precipitation_probability_max[i]
          : 0
      });
    }
  }
  return { current: current, days: days };
}

export function placeLabel(place: GeoPlace | null, lat: number, lon: number): string {
  if (place === null) {
    return lat.toFixed(3) + ', ' + lon.toFixed(3);
  }
  const parts: string[] = [];
  if (place.name.length > 0) {
    parts.push(place.name);
  }
  if (place.admin1.length > 0 && place.admin1 !== place.name) {
    parts.push(place.admin1);
  }
  if (place.country.length > 0) {
    parts.push(place.country);
  }
  if (parts.length === 0) {
    return lat.toFixed(3) + ', ' + lon.toFixed(3);
  }
  return parts.join(' · ');
}

export function formatWeatherText(place: string, report: WeatherReport): string {
  const lines: string[] = [];
  lines.push('地点：' + place);
  const current: WeatherNow | null = report.current;
  if (current !== null) {
    lines.push('当前：' + weatherCodeText(current.code) +
      '，' + current.temperature.toFixed(1) + '°C' +
      '（体感 ' + current.apparent.toFixed(1) + '°C）');
    lines.push('湿度 ' + current.humidity.toString() + '%' +
      '，风速 ' + current.wind.toFixed(1) + ' km/h' +
      '，降水 ' + current.precipitation.toFixed(1) + ' mm');
    if (current.time.length > 0) {
      lines.push('观测时间：' + current.time);
    }
  }
  if (report.days.length > 0) {
    lines.push('');
    lines.push('预报：');
    for (let i = 0; i < report.days.length; i++) {
      const day: WeatherDay = report.days[i];
      lines.push(day.date + '  ' + weatherCodeText(day.code) +
        '  ' + day.min.toFixed(0) + '~' + day.max.toFixed(0) + '°C' +
        '  降水概率 ' + day.precipitationProbability.toString() + '%');
    }
  }
  return lines.join('\n');
}

/** One calendar event as `id | 时间 | 标题 | 地点`. */
export function formatEventLine(
  id: number,
  title: string,
  start: number,
  end: number,
  location: string
): string {
  const time: string = formatDateTime(start) + '–' +
    (end > start ? formatDateTime(end).substring(11) : '');
  const suffix: string = location.length > 0 ? ' | ' + location : '';
  return id.toString() + ' | ' + time + ' | ' + title + suffix;
}

/** Name + phones + emails, one contact per line block. */
export function formatContactBlock(
  name: string,
  phones: string[],
  emails: string[]
): string {
  const parts: string[] = [];
  parts.push(name.length > 0 ? name : '（未命名）');
  if (phones.length > 0) {
    parts.push(phones.slice(0, 3).join(' / '));
  }
  if (emails.length > 0) {
    parts.push(emails.slice(0, 2).join(' / '));
  }
  return parts.join(' · ');
}
