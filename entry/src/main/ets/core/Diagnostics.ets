/**
 * Diagnostics bundle: environment, non-secret settings summary, session counts,
 * crash records collected by `service/CrashLog.ets` and the existing redacted
 * event log. Everything here is pure so the shape and the redaction can be
 * tested without a device.
 *
 * Never include: API key, sandbox token, base URL, prompts, message bodies,
 * MCP headers or system prompt. Crash parameter text is re-redacted because it
 * comes from the OS and may quote an upstream error body.
 */

import { exportStamp } from './MarkdownExport';
import { redactSecrets } from './EventLog';

export const DIAGNOSTICS_KIND: string = 'diagnostics';
export const MAX_CRASH_PARAMS_CHARS: number = 2000;
export const MAX_DIAGNOSTIC_EVENT_LINES: number = 300;
export const MAX_DIAGNOSTIC_CRASH_LINES: number = 40;

export interface DiagnosticsSettingsSummary {
  preset: string;
  modelId: string;
  thinkingLevel: string;
  temperature: number;
  maxTokens: number;
  /** Count only; fallback ids are user configuration, not diagnostics. */
  fallbackModels: number;
  toolsEnabled: boolean;
  allowWriteTools: boolean;
  confirmWriteTools: boolean;
  imageToolsEnabled: boolean;
  imageGenEnabled: boolean;
  clipboardToolsEnabled: boolean;
  memoryEnabled: boolean;
  backgroundEnabled: boolean;
  remoteSandbox: boolean;
  mcpServers: number;
  disabledTools: string[];
  appLockEnabled: boolean;
  loggingEnabled: boolean;
}

export interface DiagnosticsEnvironment {
  versionName: string;
  versionCode: number;
  sdkApi: number;
  deviceModel: string;
  osVersion: string;
  locale: string;
}

export interface DiagnosticsCounts {
  sessions: number;
  messages: number;
}

export interface DiagnosticsInput {
  generatedAt: number;
  environment: DiagnosticsEnvironment;
  counts: DiagnosticsCounts;
  settings: DiagnosticsSettingsSummary;
  /** Newest first, already redacted JSONL strings. */
  crashLines: string[];
  /** Newest first, already redacted JSONL strings. */
  eventLines: string[];
}

interface DiagnosticsDocument {
  app: string;
  kind: string;
  generatedAt: string;
  environment: DiagnosticsEnvironment;
  counts: DiagnosticsCounts;
  settings: DiagnosticsSettingsSummary;
  crashes: string[];
  events: string[];
}

interface CrashRecord {
  ts: number;
  event: string;
  params: string;
}

export function diagnosticsFileName(now: Date): string {
  return 'minis-diagnostics-' + exportStamp(now) + '.json';
}

function trimLines(lines: string[], max: number): string[] {
  return lines.length <= max ? lines.slice(0) : lines.slice(0, max);
}

/**
 * One stored crash/freeze record. Received time and event name are metadata;
 * the OS parameter text is re-redacted and capped before it is written.
 */
export function crashLine(ts: number, event: string, paramsJson: string): string {
  const record: CrashRecord = {
    ts: ts,
    event: event,
    params: redactSecrets(paramsJson).substring(0, MAX_CRASH_PARAMS_CHARS)
  };
  return JSON.stringify(record);
}

export function buildDiagnostics(input: DiagnosticsInput): string {
  const document: DiagnosticsDocument = {
    app: 'MinisHarmony',
    kind: DIAGNOSTICS_KIND,
    generatedAt: new Date(input.generatedAt).toISOString(),
    environment: input.environment,
    counts: input.counts,
    settings: input.settings,
    crashes: trimLines(input.crashLines, MAX_DIAGNOSTIC_CRASH_LINES),
    events: trimLines(input.eventLines, MAX_DIAGNOSTIC_EVENT_LINES)
  };
  return JSON.stringify(document, null, 2);
}
