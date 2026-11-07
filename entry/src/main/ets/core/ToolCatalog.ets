/**
 * Built-in tool catalogue. Both the local and remote runtimes expose the same
 * surface, so switching sandbox backend does not change the model's prompt.
 */

import type { ToolDefinition } from './ToolTypes';

export function builtinToolDefinitions(): ToolDefinition[] {
  return [
    {
      name: 'list_dir',
      description: '列出工作区某个目录下的文件和子目录。path 是相对工作区根目录的路径，省略时为根目录。',
      parameters: {
        type: 'object',
        properties: {
          path: {
            type: 'string',
            description: '相对路径，例如 src 或 docs。省略表示工作区根目录。'
          }
        },
        required: []
      }
    },
    {
      name: 'read_file',
      description: '读取工作区内的文本文件。返回按行切片后的内容；大文件请用 offset/limit 分页。',
      parameters: {
        type: 'object',
        properties: {
          path: {
            type: 'string',
            description: '相对工作区根目录的文件路径。'
          },
          offset: {
            type: 'number',
            description: '起始行号，从 0 开始，默认 0。'
          },
          limit: {
            type: 'number',
            description: '最多读取的行数，默认 400，最大 2000。'
          }
        },
        required: ['path']
      }
    },
    {
      name: 'write_file',
      description: '在工作区内创建或覆盖一个文本文件。需要用户在设置中显式允许写入。',
      parameters: {
        type: 'object',
        properties: {
          path: {
            type: 'string',
            description: '相对工作区根目录的文件路径。'
          },
          content: {
            type: 'string',
            description: '要写入的完整文本。'
          }
        },
        required: ['path', 'content']
      }
    },
    {
      name: 'search_text',
      description: '在工作区文本文件中搜索字符串，返回 文件:行号:内容。默认跳过二进制、依赖和构建目录。',
      parameters: {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description: '要搜索的文本，大小写不敏感。'
          },
          path: {
            type: 'string',
            description: '限定搜索的相对目录，省略表示整个工作区。'
          },
          max_results: {
            type: 'number',
            description: '最多返回多少条，默认 40，最大 200。'
          }
        },
        required: ['query']
      }
    },
    {
      name: 'fetch_url',
      description: '发起一次 HTTP/HTTPS 请求并返回响应文本。用于查文档、拉取接口数据；响应会被截断。',
      parameters: {
        type: 'object',
        properties: {
          url: {
            type: 'string',
            description: '完整的 http:// 或 https:// 地址。'
          },
          method: {
            type: 'string',
            description: 'GET 或 POST，默认 GET。'
          },
          body: {
            type: 'string',
            description: 'POST 请求体，可选。'
          }
        },
        required: ['url']
      }
    },
    {
      name: 'now',
      description: '返回设备当前日期和时间。用于需要时间戳的任务。',
      parameters: {
        type: 'object',
        properties: {},
        required: []
      }
    }
  ];
}
