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
  const editFileFields: FieldEntry[] = [
    field('path', 'string', '相对工作区根目录的文件路径。'),
    field('old_string', 'string', '要被替换的确切文本，需包含足够上下文以保证唯一。'),
    field('new_string', 'string', '替换后的文本。'),
    field('replace_all', 'boolean', '为 true 时替换所有匹配；默认 false，要求 old_string 唯一。')
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
  const readImageFields: FieldEntry[] = [
    field('path', 'string', '工作区内的图片路径（相对根目录）。支持 png / jpg / jpeg / webp / gif / bmp，单文件上限 5 MB。')
  ];
  const generateImageFields: FieldEntry[] = [
    field('prompt', 'string', '画面描述。写清主体、风格、构图、光线；模型会按此生成一张图。'),
    field('size', 'string', '尺寸：1024x1024（默认）、1024x1792 或 1792x1024。'),
    field('model', 'string', '可选的图像模型 ID；省略时使用当前对话模型。')
  ];
  const memoryWriteFields: FieldEntry[] = [
    field('content', 'string', '要长期记住的内容，一句话写清事实、偏好或决定。')
  ];
  const memoryGetFields: FieldEntry[] = [
    field('query', 'string', '关键词，空格分隔；省略时返回最近的记忆。'),
    field('days', 'number', '回看最近多少天，默认 7，最大 90。'),
    field('limit', 'number', '最多返回多少条，默认 20，最大 100。')
  ];
  const readSkillFields: FieldEntry[] = [
    field('id', 'string', '技能 id 或名称，见系统提示中的技能列表。')
  ];
  const clipboardWriteFields: FieldEntry[] = [
    field('text', 'string', '要写入系统剪贴板的纯文本。')
  ];
  const subagentFields: FieldEntry[] = [
    field('action', 'string',
      'delegate（默认）启动子代理；status 查看本对话的子代理；steer 纠偏运行中的子代理；' +
        'cancel 停止指定子代理并保留部分结果；resume 重启应用被终止时中断的子代理。'),
    field('prompt', 'string',
      'action=delegate 时必填。交给子代理的完整任务说明；子代理看不到当前对话，' +
        '必须写清目标、输入、约束和期望输出。'),
    field('label', 'string', '可选短标签，用于状态、后台消息与子会话标题。'),
    field('job_id', 'string',
      'action=status/steer/cancel/resume 使用。启动时返回的 job_id，接受前缀；' +
        'status 省略时列出全部，resume 省略时重启全部已中断的子代理。'),
    field('message', 'string',
      'action=steer 时必填。对运行中子代理的纠正，会保留已完成的工作；' +
        '在它下一次请求模型前读取。若子代理先结束，则报告未送达。'),
    field('wait', 'boolean',
      'action=delegate 时有效。false（默认）立即返回 job_id，结果稍后以后台消息送达；' +
        'true 阻塞到结束并直接返回结果，仅在下一次操作必须依赖结果时使用。'),
    field('max_minutes', 'number',
      'action=delegate 时的实际耗时上限，默认 10，最大 60；超时返回已产生的部分结果。')
  ];
  const browserFields: FieldEntry[] = [
    field('action', 'string',
      '动作：open 打开网址，click 点击，type 输入，text 取文本，html 取 HTML，' +
        'eval 执行 JS，back/forward/reload 导航，wait 等待，title/url 读取当前页。'),
    field('url', 'string', 'open 时必填；省略协议时自动补 https://。'),
    field('selector', 'string', 'click/type/text/html 使用的 CSS 选择器；text/html 省略时取整个页面。'),
    field('text', 'string', 'type 时要填入的文本。'),
    field('script', 'string', 'eval 时要执行的 JavaScript。'),
    field('max_chars', 'number', '返回内容的最大字符数，默认 8000，最大 20000。'),
    field('milliseconds', 'number', 'wait 的毫秒数，默认 500，最大 10000。')
  ];
  const calendarFields: FieldEntry[] = [
    field('action', 'string', 'list（默认）查看时间范围内的事件；create 新建一条事件。'),
    field('start', 'string',
      'list 的起始时间，省略为今天 00:00；create 的事件开始时间。' +
        '格式 YYYY-MM-DD HH:mm、ISO 8601 或毫秒时间戳。'),
    field('end', 'string',
      'list 的结束时间，省略为今天之后 7 天；create 的事件结束时间，省略为开始后 1 小时。'),
    field('title', 'string', 'create 必填，事件标题。'),
    field('location', 'string', 'create 可选，事件地点。'),
    field('description', 'string', 'create 可选，事件备注。')
  ];
  const contactsFields: FieldEntry[] = [
    field('action', 'string', 'search（默认）按关键词搜索；list 列出联系人。'),
    field('query', 'string', 'search 的关键词，匹配姓名、电话或邮箱，大小写不敏感。'),
    field('limit', 'number', '最多返回多少条，默认 10，最大 20。')
  ];
  const locationFields: FieldEntry[] = [
    field('action', 'string', 'get（默认）读取当前定位坐标。')
  ];
  const weatherFields: FieldEntry[] = [
    field('action', 'string', 'current（默认）当前天气；forecast 未来几天。'),
    field('city', 'string', '可选城市名；省略时使用设备定位。'),
    field('days', 'number', 'forecast 的天数，默认 3，最大 7。')
  ];
  const shellFields: FieldEntry[] = [
    field('command', 'string',
      '要执行的 shell 命令。由 /bin/sh 执行，可以使用管道、重定向和多行脚本。'),
    field('timeout', 'number',
      '最长执行秒数，默认 900，最大 3600。超时会重启沙箱并丢弃未完成的命令。')
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
      name: 'read_image',
      description: '读取工作区内的图片并把像素传给模型（需要模型支持视觉，且用户在设置中开启）。纯文本模型不要调用。',
      parameters: parametersOf(readImageFields, ['path'])
    },
    {
      name: 'generate_image',
      description: '调用 OpenAI 兼容的 /images/generations 生成一张图片并保存到本机（需要用户在设置中开启图像生成）。' +
        '返回后图片会显示在工具卡片中，同时把像素带给模型。Anthropic / Gemini 原生协议不支持。',
      parameters: parametersOf(generateImageFields, ['prompt'])
    },
    {
      name: 'write_file',
      description: '在工作区内创建或覆盖一个文本文件。需要用户在设置中显式允许写入。',
      parameters: parametersOf(writeFileFields, ['path', 'content'])
    },
    {
      name: 'file_edit',
      description: '对工作区内的文本文件做精确字符串替换。old_string 必须唯一（否则请提供更多上下文或设置 replace_all）；需要用户在设置中显式允许写入。',
      parameters: parametersOf(editFileFields, ['path', 'old_string', 'new_string'])
    },
    {
      name: 'search_text',
      description: '在工作区文本文件中搜索字符串，返回 文件:行号:内容。默认跳过二进制、依赖和构建目录。',
      parameters: parametersOf(searchFields, ['query'])
    },
    {
      name: 'shell_execute',
      description: '在本机的 Linux 沙箱（Alpine）中执行 shell 命令，返回 stdout+stderr 与退出码。' +
        '同一个会话共享一个常驻 shell，cd、环境变量会保留到下一次调用。工作区挂载在 ' +
        '/var/minis/workspace，记忆目录挂载在 /var/minis/memory，用它们读写用户文件。' +
        '沙箱内可能没有外网；需要联网取数据请用 fetch_url。',
      parameters: parametersOf(shellFields, ['command'])
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
    },
    {
      name: 'memory_write',
      description: '把一条值得长期记住的信息写入本机记忆（用户偏好、项目决定、事实）。需要在设置中开启持久记忆。',
      parameters: parametersOf(memoryWriteFields, ['content'])
    },
    {
      name: 'memory_get',
      description: '按关键词检索本机记忆，返回带日期的片段。没有命中时返回最近记录。',
      parameters: parametersOf(memoryGetFields, [])
    },
    {
      name: 'read_skill',
      description: '读取已启用技能的完整说明。系统提示里只列出名称与简介，需要具体步骤时调用本工具。',
      parameters: parametersOf(readSkillFields, ['id'])
    },
    {
      name: 'clipboard_read',
      description: '读取设备剪贴板中的纯文本。需要在设置中开启剪贴板工具；系统可能要求用户授权。',
      parameters: parametersOf(noFields, [])
    },
    {
      name: 'clipboard_write',
      description: '把纯文本写入设备剪贴板，覆盖原有内容。需要在设置中开启剪贴板工具。',
      parameters: parametersOf(clipboardWriteFields, ['text'])
    },
    {
      name: 'browser_use',
      description: '在内置浏览器中打开网页并交互：导航、点击、输入、读取文本/HTML 或执行 JS。' +
        '适合需要登录态或 JavaScript 渲染的页面；静态接口请求请优先用 fetch_url。',
      parameters: parametersOf(browserFields, ['action'])
    },
    {
      name: 'calendar',
      description: '读取或创建设备日历事件。需要在设置中开启日历工具，首次使用会请求系统日历权限。' +
        'list 返回指定范围内的最多 50 条事件；create 写入默认日历。',
      parameters: parametersOf(calendarFields, [])
    },
    {
      name: 'contacts',
      description: '搜索设备通讯录。需要在设置中开启通讯录工具，首次使用会请求系统联系人权限。' +
        '只返回姓名、电话与邮箱，不修改通讯录。',
      parameters: parametersOf(contactsFields, [])
    },
    {
      name: 'location',
      description: '读取设备当前经纬度。需要在设置中开启定位工具，首次使用会请求系统定位权限。',
      parameters: parametersOf(locationFields, [])
    },
    {
      name: 'weather',
      description: '查询当前天气或未来几天预报（Open-Meteo，无需密钥）。' +
        '提供 city 时按城市查询；否则使用设备定位（需要定位权限）。',
      parameters: parametersOf(weatherFields, [])
    },
    {
      name: 'subagent_task',
      description: '把一个独立、边界清晰的子任务交给子代理（最多 3 个并行，队列化的会等空位）。' +
        '子代理有自己的上下文和工具循环，看不到当前对话。默认立即返回 job_id，结果稍后以' +
        '「[后台任务结束 …]」消息送达；wait=true 才阻塞等待。可用 action 查看状态、纠偏、' +
        '取消或重启中断的任务。',
      parameters: parametersOf(subagentFields, [])
    }
  ];
  return definitions;
}

/**
 * Per-tool switches live in settings as bare names. A tool is available when
 * the catalogue includes it AND its name is not in this list.
 */
export function isToolDisabled(disabledTools: string[], name: string): boolean {
  for (let i = 0; i < disabledTools.length; i++) {
    if (disabledTools[i] === name) {
      return true;
    }
  }
  return false;
}
