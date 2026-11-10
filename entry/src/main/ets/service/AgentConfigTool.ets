import {
  AgentConfigOutcome,
  agentConfigKeyAllowed,
  agentConfigSnapshot,
  agentConfigValue,
  applyAgentConfig
} from '../core/AgentConfig';
import { ConfigHandler, ToolResult } from '../core/ToolTypes';
import { AppSettings } from '../core/Types';
import { t } from '../core/I18n';

interface ConfigArgs {
  action?: string;
  key?: string;
  value?: string;
}

/**
 * Bridges the model-facing `config` tool to the live settings. Validation and
 * the key whitelist live in core/AgentConfig; this class only parses the
 * argument JSON and hands an accepted clone to the page for saving/auditing.
 */
export class AgentConfigTool implements ConfigHandler {
  private read: () => AppSettings;
  private apply: (next: AppSettings) => void;

  constructor(read: () => AppSettings, apply: (next: AppSettings) => void) {
    this.read = read;
    this.apply = apply;
  }

  execute(argumentsJson: string): ToolResult {
    let args: ConfigArgs;
    try {
      args = JSON.parse(argumentsJson) as ConfigArgs;
    } catch (e) {
      return { ok: false, content: t('参数不是有效的 JSON。') };
    }
    const action: string = args.action !== undefined && args.action.length > 0
      ? args.action : 'get';
    const key: string = args.key !== undefined ? args.key.trim() : '';
    if (action === 'get') {
      const settings: AppSettings = this.read();
      if (key.length === 0) {
        return { ok: true, content: agentConfigSnapshot(settings) };
      }
      if (!agentConfigKeyAllowed(key)) {
        return {
          ok: false,
          content: t('这个配置项不允许由代理读取：') + key
        };
      }
      return { ok: true, content: key + ' = ' + agentConfigValue(settings, key) };
    }
    if (action !== 'set') {
      return {
        ok: false,
        content: t('action 只能是 get 或 set。')
      };
    }
    if (key.length === 0) {
      return { ok: false, content: t('set 需要 key。') };
    }
    const value: string = args.value !== undefined ? args.value : '';
    const outcome: AgentConfigOutcome =
      applyAgentConfig(this.read(), key, value);
    if (!outcome.ok) {
      return { ok: false, content: outcome.message };
    }
    if (outcome.changed) {
      this.apply(outcome.settings);
    }
    return { ok: true, content: outcome.message };
  }
}
