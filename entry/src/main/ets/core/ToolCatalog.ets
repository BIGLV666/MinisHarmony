/**
 * Built-in tool catalogue. Both the local and remote runtimes expose the same
 * surface, so switching sandbox backend does not change the model's prompt.
 */

import { ToolDefinition, ToolParameters, ToolProperty } from './ToolTypes';

/**
 * ArkTS rejects an object literal whose target type is `Record<K, V>`, but it
 * does accept a `Record` built by indexed assignment. Tools are authored as
 * small field entries and folded into the schema object here.
 */
interface FieldEntry {
  name: string;
  property: ToolProperty;
}

function field(name: string, type: string, description: string): FieldEntry {
  const property: ToolProperty = { type: type, description: description };
  const entry: FieldEntry = { name: name, property: property };
  return entry;
}

function propertiesOf(entries: FieldEntry[]): Record<string, ToolProperty> {
  const properties: Record<string, ToolProperty> = {};
  for (let i = 0; i < entries.length; i++) {
    const entry: FieldEntry = entries[i];
    properties[entry.name] = entry.property;
  }
  return properties;
}

function parametersOf(entries: FieldEntry[], required: string[]): ToolParameters {
  const parameters: ToolParameters = {
    type: 'object',
    properties: propertiesOf(entries),
    required: required
  };
  return parameters;
}

export function builtinToolDefinitions(): ToolDefinition[] {
  const listDirFields: FieldEntry[] = [
    field('path', 'string', '相对路径，例如 src 或 docs。省略表示工作区根目录。')
  ];
  const readFileFields: FieldEntry[] = [
    field('path', 'string', '相对工作区根目录的文件路径。'),
    field('offset', 'number', '起始行号，从 0 开始，默认 0。'),
    field('limit', 'number', '最多读取的行数，默认 400，最大 2000。')
  ];
  const writeFileFields: FieldEntry[] = [
    field('path', 'string', '相对工作区根目录的文件路径。'),
    field('content', 'string', '要写入的完整文本。')
  ];
  const searchFields: FieldEntry[] = [
    field('query', 'string', '要搜索的文本，大小写不敏感。'),
    field('path', 'string', '限定搜索的相对目录，省略表示整个工作区。'),
    field('max_results', 'number', '最多返回多少条，默认 40，最大 200。')
  ];
  const fetchFields: FieldEntry[] = [
    field('url', 'string', '完整的 http:// 或 https:// 地址。'),
    field('method', 'string', 'GET 或 POST，默认 GET。'),
    field('body', 'string', 'POST 请求体，可选。')
  ];
  const noFields: FieldEntry[] = [];

  const definitions: ToolDefinition[] = [
    {
      name: 'list_dir',
      description: '列出工作区某个目录下的文件和子目录。path 是相对工作区根目录的路径，省略时为根目录。',
      parameters: parametersOf(listDirFields, [])
    },
    {
      name: 'read_file',
      description: '读取工作区内的文本文件。返回按行切片后的内容；大文件请用 offset/limit 分页。',
      parameters: parametersOf(readFileFields, ['path'])
    },
    {
      name: 'write_file',
      description: '在工作区内创建或覆盖一个文本文件。需要用户在设置中显式允许写入。',
      parameters: parametersOf(writeFileFields, ['path', 'content'])
    },
    {
      name: 'search_text',
      description: '在工作区文本文件中搜索字符串，返回 文件:行号:内容。默认跳过二进制、依赖和构建目录。',
      parameters: parametersOf(searchFields, ['query'])
    },
    {
      name: 'fetch_url',
      description: '发起一次 HTTP/HTTPS 请求并返回响应文本。用于查文档、拉取接口数据；响应会被截断。',
      parameters: parametersOf(fetchFields, ['url'])
    },
    {
      name: 'now',
      description: '返回设备当前日期和时间。用于需要时间戳的任务。',
      parameters: parametersOf(noFields, [])
    }
  ];
  return definitions;
}
