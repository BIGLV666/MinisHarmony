import { Permissions, abilityAccessCtrl, common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { contact } from '@kit.ContactsKit';
import { geoLocationManager } from '@kit.LocationKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  DeviceToolsHandler,
  ToolResult
} from '../core/ToolTypes';
import { AppSettings } from '../core/Types';
import {
  MAX_LISTED_CONTACTS,
  MAX_LISTED_EVENTS,
  GeoPlace,
  WeatherDay,
  WeatherReport,
  clampWeatherDays,
  formatContactBlock,
  formatDateTime,
  formatEventLine,
  formatWeatherText,
  geocodeUrl,
  parseGeoJson,
  parseTimeArg,
  parseWeatherJson,
  placeLabel,
  weatherUrl
} from '../core/Device';
import { truncateText } from '../core/Workspace';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const MAX_HTTP_CHARS: number = 1024 * 1024;

interface CalendarArgs {
  action?: string;
  start?: string;
  end?: string;
  title?: string;
  location?: string;
  description?: string;
}

interface ContactsArgs {
  action?: string;
  query?: string;
  limit?: number;
}

interface WeatherArgs {
  action?: string;
  city?: string;
  days?: number;
}

function stringArg(value: string | undefined): string {
  return value !== undefined ? value.trim() : '';
}

/**
 * Implements the calendar / contacts / location / weather tools on top of the
 * HarmonyOS kits. Every capability is opt-in through settings and still asks
 * the system for its user-granted permission the first time it is used.
 */
export class DeviceTools implements DeviceToolsHandler {
  private context: common.UIAbilityContext;
  private settings: AppSettings;

  constructor(context: common.UIAbilityContext, settings: AppSettings) {
    this.context = context;
    this.settings = settings;
  }

  enabled(name: string): boolean {
    if (name === 'calendar') {
      return this.settings.calendarToolsEnabled;
    }
    if (name === 'contacts') {
      return this.settings.contactsToolsEnabled;
    }
    if (name === 'location') {
      return this.settings.locationToolsEnabled;
    }
    if (name === 'weather') {
      return this.settings.weatherToolsEnabled;
    }
    return false;
  }

  async execute(name: string, argumentsJson: string): Promise<ToolResult> {
    if (!this.enabled(name)) {
      return { ok: false, content: '该设备工具已在设置中关闭：' + name };
    }
    try {
      if (name === 'calendar') {
        return await this.calendar(argumentsJson);
      }
      if (name === 'contacts') {
        return await this.contacts(argumentsJson);
      }
      if (name === 'location') {
        return await this.location();
      }
      if (name === 'weather') {
        return await this.weather(argumentsJson);
      }
      return { ok: false, content: '未知设备工具：' + name };
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      return { ok: false, content: '设备工具执行失败：' + error.message };
    }
  }

  /** '' when every permission was granted, otherwise a user-facing reason. */
  private async ensurePermissions(permissions: Permissions[]): Promise<string> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(this.context, permissions);
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) {
          return '用户未授予所需权限：' + result.permissions[i];
        }
      }
      return '';
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      return '无法请求系统权限：' + error.message;
    }
  }

  private async calendar(argumentsJson: string): Promise<ToolResult> {
    const args: CalendarArgs = JSON.parse(argumentsJson) as CalendarArgs;
    const action: string = stringArg(args.action).length > 0
      ? stringArg(args.action).toLowerCase()
      : 'list';
    if (action !== 'list' && action !== 'create') {
      return { ok: false, content: 'calendar 的 action 只支持 list 或 create。' };
    }
    const now: number = Date.now();
    if (action === 'create') {
      return await this.createEvent(args, now);
    }
    const start: number = stringArg(args.start).length > 0
      ? parseTimeArg(stringArg(args.start), now)
      : this.startOfToday(now);
    if (start < 0) {
      return { ok: false, content: 'start 时间无法识别，请用 YYYY-MM-DD HH:mm。' };
    }
    const end: number = stringArg(args.end).length > 0
      ? parseTimeArg(stringArg(args.end), now)
      : start + 7 * DAY_MS;
    if (end < 0 || end <= start) {
      return { ok: false, content: 'end 必须晚于 start。' };
    }
    const denied: string = await this.ensurePermissions(
      ['ohos.permission.READ_CALENDAR'] as Permissions[]);
    if (denied.length > 0) {
      return { ok: false, content: denied };
    }
    const manager: calendarManager.CalendarManager =
      calendarManager.getCalendarManager(this.context);
    const calendar: calendarManager.Calendar = await manager.getCalendar();
    const events: calendarManager.Event[] = await calendar.getEvents(
      calendarManager.EventFilter.filterByTime(start, end));
    events.sort((a: calendarManager.Event, b: calendarManager.Event) =>
      a.startTime - b.startTime);
    const lines: string[] = [];
    for (let i = 0; i < events.length && i < MAX_LISTED_EVENTS; i++) {
      const event: calendarManager.Event = events[i];
      const place: string = event.location !== undefined &&
        event.location.location !== undefined ? event.location.location : '';
      lines.push(formatEventLine(
        event.id !== undefined ? event.id : 0,
        event.title !== undefined ? event.title : '（无标题）',
        event.startTime,
        event.endTime,
        place
      ));
    }
    if (lines.length === 0) {
      return {
        ok: true,
        content: '此范围内没有日历事件（' + formatDateTime(start) + ' – ' +
          formatDateTime(end) + '）。'
      };
    }
    if (events.length > MAX_LISTED_EVENTS) {
      lines.push('…还有 ' + (events.length - MAX_LISTED_EVENTS).toString() + ' 条未显示。');
    }
    return { ok: true, content: lines.join('\n') };
  }

  private startOfToday(now: number): number {
    const date: Date = new Date(now);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  }

  private async createEvent(args: CalendarArgs, now: number): Promise<ToolResult> {
    const title: string = stringArg(args.title);
    if (title.length === 0) {
      return { ok: false, content: 'create 需要非空的 title。' };
    }
    const start: number = parseTimeArg(stringArg(args.start), now);
    if (start < 0) {
      return { ok: false, content: 'start 时间无法识别，请用 YYYY-MM-DD HH:mm。' };
    }
    const endText: string = stringArg(args.end);
    const end: number = endText.length > 0
      ? parseTimeArg(endText, now)
      : start + 60 * 60 * 1000;
    if (end < 0 || end <= start) {
      return { ok: false, content: 'end 必须晚于 start。' };
    }
    const denied: string = await this.ensurePermissions(
      ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'] as Permissions[]);
    if (denied.length > 0) {
      return { ok: false, content: denied };
    }
    const manager: calendarManager.CalendarManager =
      calendarManager.getCalendarManager(this.context);
    const calendar: calendarManager.Calendar = await manager.getCalendar();
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: title,
      startTime: start,
      endTime: end
    };
    if (stringArg(args.location).length > 0) {
      const place: calendarManager.Location = { location: stringArg(args.location) };
      event.location = place;
    }
    if (stringArg(args.description).length > 0) {
      event.description = stringArg(args.description);
    }
    const id: number = await calendar.addEvent(event);
    return {
      ok: true,
      content: '已创建日历事件 #' + id.toString() + '：' + title +
        '（' + formatDateTime(start) + ' – ' + formatDateTime(end) + '）'
    };
  }

  private async contacts(argumentsJson: string): Promise<ToolResult> {
    const args: ContactsArgs = JSON.parse(argumentsJson) as ContactsArgs;
    const limiter: number = args.limit !== undefined && args.limit > 0
      ? Math.floor(args.limit)
      : 10;
    const limit: number = limiter > MAX_LISTED_CONTACTS ? MAX_LISTED_CONTACTS : limiter;
    const query: string = stringArg(args.query).toLowerCase();
    const denied: string = await this.ensurePermissions(
      ['ohos.permission.READ_CONTACTS'] as Permissions[]);
    if (denied.length > 0) {
      return { ok: false, content: denied };
    }
    const all: contact.Contact[] = await contact.queryContacts();
    const blocks: string[] = [];
    for (let i = 0; i < all.length && blocks.length < limit; i++) {
      const item: contact.Contact = all[i];
      const phones: string[] = [];
      if (item.phoneNumbers !== undefined) {
        for (let p = 0; p < item.phoneNumbers.length; p++) {
          phones.push(item.phoneNumbers[p].phoneNumber);
        }
      }
      const emails: string[] = [];
      if (item.emails !== undefined) {
        for (let e = 0; e < item.emails.length; e++) {
          emails.push(item.emails[e].email);
        }
      }
      const name: string = item.name !== undefined ? item.name.fullName : '';
      if (query.length > 0) {
        const haystack: string = (name + ' ' + phones.join(' ') + ' ' +
          emails.join(' ')).toLowerCase();
        if (haystack.indexOf(query) < 0) {
          continue;
        }
      }
      blocks.push(formatContactBlock(name, phones, emails));
    }
    if (blocks.length === 0) {
      return {
        ok: true,
        content: query.length > 0
          ? '没有匹配「' + query + '」的联系人。'
          : '通讯录为空，或没有可读取的联系人。'
      };
    }
    return { ok: true, content: blocks.join('\n') };
  }

  private async location(): Promise<ToolResult> {
    const denied: string = await this.ensurePermissions(
      ['ohos.permission.APPROXIMATELY_LOCATION'] as Permissions[]);
    if (denied.length > 0) {
      return { ok: false, content: denied };
    }
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      timeoutMs: 10000
    };
    const position: geoLocationManager.Location =
      await geoLocationManager.getCurrentLocation(request);
    return {
      ok: true,
      content: '纬度：' + position.latitude.toFixed(6) + '\n经度：' +
        position.longitude.toFixed(6) + '\n精度：约 ' +
        position.accuracy.toFixed(0) + ' 米'
    };
  }

  private async weather(argumentsJson: string): Promise<ToolResult> {
    const args: WeatherArgs = JSON.parse(argumentsJson) as WeatherArgs;
    const action: string = stringArg(args.action).length > 0
      ? stringArg(args.action).toLowerCase()
      : 'current';
    if (action !== 'current' && action !== 'forecast') {
      return { ok: false, content: 'weather 的 action 只支持 current 或 forecast。' };
    }
    const days: number = clampWeatherDays(
      action === 'forecast' ? (args.days !== undefined ? args.days : 3) : 1);
    const city: string = stringArg(args.city);
    let lat: number = 0;
    let lon: number = 0;
    let place: GeoPlace | null = null;
    if (city.length > 0) {
      const geoBody: string = await this.get(geocodeUrl(city));
      if (geoBody.length === 0) {
        return { ok: false, content: '无法解析城市「' + city + '」，请换一个名称。' };
      }
      place = parseGeoJson(geoBody);
      if (place === null) {
        return { ok: false, content: '找不到城市「' + city + '」。' };
      }
      lat = place.latitude;
      lon = place.longitude;
    } else {
      const denied: string = await this.ensurePermissions(
        ['ohos.permission.APPROXIMATELY_LOCATION'] as Permissions[]);
      if (denied.length > 0) {
        return { ok: false, content: denied + '（也可以传 city 参数按城市查询。）' };
      }
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        timeoutMs: 10000
      };
      const position: geoLocationManager.Location =
        await geoLocationManager.getCurrentLocation(request);
      lat = position.latitude;
      lon = position.longitude;
    }
    const body: string = await this.get(weatherUrl(lat, lon, days));
    if (body.length === 0) {
      return { ok: false, content: '天气服务暂时不可用。' };
    }
    const report: WeatherReport = parseWeatherJson(body);
    if (report.current === null && report.days.length === 0) {
      return { ok: false, content: '天气响应无法解析。' };
    }
    return { ok: true, content: formatWeatherText(placeLabel(place, lat, lon), report) };
  }

  /** GET text through the network kit; '' on any failure. */
  private async get(url: string): Promise<string> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'MinisHarmony/1.0 (HarmonyOS tablet)'
        },
        connectTimeout: 15000,
        readTimeout: 20000,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode >= 400) {
        return '';
      }
      return truncateText(response.result as string, MAX_HTTP_CHARS);
    } catch (e) {
      return '';
    } finally {
      request.destroy();
    }
  }
}
