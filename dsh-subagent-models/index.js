/**
 * dsh-subagent-models — Host half.
 *
 * 目的：子 Agent（subagent / workflow）能选的模型不再只有父会话那一条路由。
 * DSH 本身已有这条策略通道：
 *   1. 配置行 `subagent-model-selection-settings`（enabled + allowedModels）
 *      —— 决定「之后新建的顶层会话」记录什么授权；
 *   2. 会话事件 `subagent/model-selection-policy`（{ allowedModels }）
 *      —— 每个会话真正生效的那份白名单（先写入者生效）。
 *
 * 本插件把这两件事包成一个可被 UI 与 Agent 共同调用的操作：
 *   - 读取全部 provider × model（= 你在模型选择器里能看到的那一份目录）
 *   - 保存白名单到上面那条配置行
 *   - 需要时把白名单立刻写入当前会话（不必重开会话就生效）
 */

const ROUTE_PATH = '/subagent-models/api'
const POLICY_EVENT = 'subagent/model-selection-policy'
const DEFAULT_NS = 'subagent-model-selection-settings'
const POLICY_PACKAGE = '@deepseek-ai/dsh-tool-subagent/model-selection-settings'
const CACHE_MS = 60_000
const MAX_SESSION_ROWS = 30

export const name = 'dsh-subagent-models'
export const inject = []

const cleanups = []
const catalogCache = { at: 0, models: [], errors: [] }

export function apply(ctx) {
  try {
    ctx.effect(() => disposeAll, 'dsh-subagent-models: cleanup')
  } catch {
    /* older contexts just lose the eager cleanup */
  }
  installRoute(ctx)
  installTool(ctx)
}

/* ------------------------------------------------------------------ *
 * wiring
 * ------------------------------------------------------------------ */

function installRoute(ctx) {
  if (typeof ctx.inject !== 'function') return
  try {
    ctx.inject(['webServer'], (host) => {
      track(() => host.webServer.register({
        kind: 'exact',
        path: ROUTE_PATH,
        handler: (request, response) => handleRequest(host, request, response),
      }))
    })
  } catch (error) {
    warn(error)
  }
}

function installTool(ctx) {
  if (typeof ctx.inject !== 'function') return
  try {
    ctx.inject(['tools'], (host) => {
      track(() => host.tools.register({
        name: 'subagent_models',
        description:
          '列出本机所有可用模型，并管理「子 Agent 可用的模型」白名单：'
          + '写入 DSH 的子 Agent 模型选择设置，可选地把白名单立即应用到指定会话。'
          + '把子 Agent 固定到便宜模型可以显著省钱。',
        parameters: {
          type: 'object',
          additionalProperties: false,
          properties: {
            action: { type: 'string', enum: ['list', 'save', 'apply'], description: 'list=只看目录与当前白名单；save=保存白名单；apply=把白名单写入某个会话' },
            enabled: { type: 'boolean', description: 'save 时是否启用子 Agent 模型选择' },
            allowedModels: {
              type: 'array',
              description: '允许子 Agent 使用的 provider/model 组合',
              items: {
                type: 'object',
                additionalProperties: false,
                properties: {
                  provider: { type: 'string' },
                  model: { type: 'string' },
                },
                required: ['provider', 'model'],
              },
            },
            sessionId: { type: 'string', description: 'apply 时要写入的会话 id' },
          },
          required: ['action'],
        },
        output: {
          schema: {
            type: 'object',
            additionalProperties: false,
            properties: { text: { type: 'string' } },
          },
          render: (_args, value) => [{ type: 'text', text: String(value?.text ?? '') }],
        },
        async execute(args) {
          try {
            const action = String(args?.action || 'list')
            if (action === 'save') {
              const state = await save(ctx, {
                enabled: args?.enabled,
                allowedModels: args?.allowedModels,
                sessionId: args?.sessionId,
              })
              return { text: describeState(state) }
            }
            if (action === 'apply') {
              const state = await applyToSession(ctx, {
                sessionId: args?.sessionId,
                allowedModels: args?.allowedModels,
              })
              return { text: describeState(state) }
            }
            const state = await readState(ctx, { sessionId: args?.sessionId })
            return { text: describeState(state) }
          } catch (error) {
            return { text: `ERROR: ${messageOf(error)}` }
          }
        },
      }))
    })
  } catch (error) {
    warn(error)
  }
}

function track(register) {
  try {
    const dispose = register()
    if (typeof dispose === 'function') cleanups.push(dispose)
  } catch (error) {
    warn(error)
  }
}

function disposeAll() {
  for (const dispose of cleanups.splice(0).reverse()) {
    try {
      dispose()
    } catch {
      /* ignore */
    }
  }
}

/* ------------------------------------------------------------------ *
 * HTTP entry point (the Client half talks to this)
 * ------------------------------------------------------------------ */

async function handleRequest(ctx, request, response) {
  if (!sameOrigin(request, response)) return
  const method = String(request.method || 'GET').toUpperCase()
  try {
    if (method === 'GET') {
      const url = new URL(String(request.url || '/'), 'http://localhost')
      sendJson(response, 200, await readState(ctx, {
        sessionId: url.searchParams.get('sessionId') || undefined,
        refresh: url.searchParams.get('refresh') === '1',
      }))
      return
    }
    if (method !== 'POST') {
      sendJson(response, 405, { ok: false, error: '只支持 GET / POST' })
      return
    }
    const body = await readJsonBody(request)
    const op = String(body?.op || 'state')
    if (op === 'state') {
      sendJson(response, 200, await readState(ctx, {
        sessionId: body?.sessionId,
        refresh: body?.refresh === true,
      }))
      return
    }
    if (op === 'save') {
      sendJson(response, 200, await save(ctx, body))
      return
    }
    if (op === 'apply') {
      sendJson(response, 200, await applyToSession(ctx, body))
      return
    }
    sendJson(response, 400, { ok: false, error: `未知操作: ${op}` })
  } catch (error) {
    sendJson(response, 500, { ok: false, error: messageOf(error) })
  }
}

function headerOf(request, name) {
  const headers = request?.headers
  if (!headers) return ''
  const value = headers[name] ?? headers[String(name).toLowerCase()]
  if (Array.isArray(value)) return String(value[0] || '')
  return String(value || '')
}

function sameOrigin(request, response) {
  if (headerOf(request, 'sec-fetch-site').toLowerCase() === 'cross-site') {
    deny(response)
    return false
  }
  const origin = headerOf(request, 'origin').trim()
  if (origin === 'null') {
    deny(response)
    return false
  }
  if (!origin) return true
  try {
    if (new URL(origin).host === headerOf(request, 'host')) return true
  } catch {
    /* fall through */
  }
  deny(response)
  return false
}

function deny(response) {
  sendJson(response, 403, { ok: false, error: 'cross-origin blocked' })
}

function sendJson(response, status, payload) {
  try {
    response.writeHead(status, {
      'cache-control': 'no-store',
      'content-type': 'application/json; charset=utf-8',
    })
    response.end(JSON.stringify(payload))
  } catch (error) {
    warn(error)
  }
}

async function readJsonBody(request, maxBytes = 256 * 1024) {
  const chunks = []
  let size = 0
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)
    size += buffer.length
    if (size > maxBytes) throw new Error('请求体过大')
    chunks.push(buffer)
  }
  const raw = Buffer.concat(chunks).toString('utf8').trim()
  if (!raw) return {}
  try {
    return JSON.parse(raw)
  } catch {
    throw new Error('请求体不是合法 JSON')
  }
}

/* ------------------------------------------------------------------ *
 * core operations (shared by the route and the tool)
 * ------------------------------------------------------------------ */

async function readState(ctx, options = {}) {
  const catalog = await collectModels(ctx, options.refresh === true)
  const info = resolveSettings(ctx)
  const policy = readPolicy(ctx, info)
  return {
    ok: true,
    enabled: policy.enabled,
    allowedModels: policy.allowedModels,
    ns: info.ns,
    writable: Boolean(info.settings),
    models: catalog.models,
    warnings: catalog.errors,
    session: options.sessionId ? readSessionPolicy(ctx, String(options.sessionId)) : null,
    sessions: listLiveSessions(ctx),
  }
}

async function save(ctx, body) {
  const enabled = body?.enabled === true
  const routes = normalizeRoutes(body?.allowedModels)
  if (enabled && routes.length === 0) throw new Error('启用时必须至少勾选一个模型')
  const info = resolveSettings(ctx)
  if (!info.settings) throw new Error('settings 服务不可用，无法保存子 Agent 模型设置')
  await info.settings.update(info.ns, { enabled, allowedModels: routes })
  const applied = readPolicy(ctx, resolveSettings(ctx))
  if (applied.enabled !== enabled || routesKey(applied.allowedModels) !== routesKey(routes)) {
    await editConfigRow(ctx, info.ns, { enabled, allowedModels: routes })
  }
  return readState(ctx, { sessionId: body?.sessionId, refresh: false })
}

async function editConfigRow(ctx, ns, patch) {
  const editor = ctx.get('configEditor')
  if (!editor) throw new Error('配置层不可写：settings.update 没有生效，且 configEditor 不可用')
  const rows = editor.configuration() || []
  const row = rows.find((candidate) => entryMatches(candidate?.entry, ns))
  if (!row) throw new Error('找不到子 Agent 模型设置行，无法保存')
  await editor.edit(row.entry, (current) => ({ ...(current || {}), ...patch }))
}

function routesKey(routes) {
  return routes.map((route) => `${route.provider}/${route.model}`).sort().join('|')
}

async function applyToSession(ctx, body) {
  const sessionId = String(body?.sessionId || '')
  const routes = normalizeRoutes(body?.allowedModels)
  if (!sessionId) throw new Error('缺少 sessionId')
  if (routes.length === 0) throw new Error('至少要有一个模型才能应用')
  const sessions = ctx.get('sessions')
  const session = sessions?.get(sessionId)
  if (!session) throw new Error('该会话不在线，无法立即应用（重开会话后会自动带上新设置）')
  session.append(POLICY_EVENT, { allowedModels: routes })
  return readState(ctx, { sessionId, refresh: false })
}

async function collectModels(ctx, refresh) {
  const now = Date.now()
  if (!refresh && catalogCache.models.length > 0 && now - catalogCache.at < CACHE_MS) return catalogCache
  const models = []
  const errors = []
  const llm = ctx.get('llm')
  if (!llm) {
    Object.assign(catalogCache, { at: now, models, errors: ['llm 服务不可用'] })
    return catalogCache
  }
  let providers = []
  try {
    providers = llm.listProviders() || []
  } catch (error) {
    errors.push(`listProviders: ${messageOf(error)}`)
  }
  for (const provider of providers) {
    const id = String(provider?.id || '')
    if (!id) continue
    try {
      const list = await llm.listModels(id)
      for (const model of list || []) {
        models.push({
          provider: id,
          providerName: String(provider?.name || id),
          model: String(model?.id || ''),
          name: String(model?.name || model?.id || ''),
          badge: badgeText(model?.badge),
        })
      }
    } catch (error) {
      errors.push(`${id}: ${messageOf(error)}`)
    }
  }
  Object.assign(catalogCache, { at: now, models, errors })
  return catalogCache
}

function badgeText(badge) {
  const text = badge?.text
  if (typeof text === 'string') return text
  if (text && typeof text === 'object') return String(text.zh || text['zh-CN'] || text.en || '')
  return ''
}

function resolveSettings(ctx) {
  const settings = ctx.get('settings')
  if (!settings) return { settings: null, ns: DEFAULT_NS, descriptor: null }
  let descriptors = []
  try {
    descriptors = settings.describe() || []
  } catch (error) {
    warn(error)
  }
  const hit = descriptors.find((descriptor) => policyProps(descriptor?.schema) !== null)
  return { settings, ns: hit?.ns ?? DEFAULT_NS, descriptor: hit ?? null }
}

function policyProps(schema) {
  if (!schema || typeof schema !== 'object') return null
  const direct = schema.properties
  if (direct && 'allowedModels' in direct && 'enabled' in direct) return direct
  for (const branch of Array.isArray(schema.anyOf) ? schema.anyOf : []) {
    const props = branch && typeof branch === 'object' ? branch.properties : null
    if (props && 'allowedModels' in props && 'enabled' in props) return props
  }
  return null
}

function policyOfDescriptor(descriptor) {
  const value = descriptor && typeof descriptor.value === 'object' && descriptor.value ? descriptor.value : {}
  const user = descriptor && typeof descriptor.user === 'object' && descriptor.user ? descriptor.user : {}
  const merged = { ...user, ...value }
  return {
    enabled: merged.enabled === true,
    allowedModels: normalizeRoutes(merged.allowedModels),
  }
}

/**
 * 读「当前生效的白名单」。
 * `enabled` / `allowedModels` 是 volatile 字段：settings.describe() 的表单投影会
 * 把它们裁掉，所以先走 configEditor 的 inherited + override 原始层，再退回 settings。
 */
function readPolicy(ctx, info) {
  const editor = ctx.get('configEditor')
  if (editor) {
    try {
      const rows = editor.configuration() || []
      const row = rows.find((candidate) => entryMatches(candidate?.entry, info.ns))
      if (row) {
        const merged = { ...(row.inherited || {}), ...(row.override || {}) }
        return {
          enabled: merged.enabled === true,
          allowedModels: normalizeRoutes(merged.allowedModels),
        }
      }
    } catch (error) {
      warn(error)
    }
  }
  return policyOfDescriptor(info.descriptor)
}

function entryMatches(entry, ns) {
  if (!entry) return false
  const id = String(entry.id || '')
  if (id === ns || id === `include:${ns}`) return true
  const name = String(entry.options?.name || entry.name || '')
  return name === POLICY_PACKAGE
}

function normalizeRoutes(input) {
  const routes = []
  const seen = new Set()
  if (!Array.isArray(input)) return routes
  for (const candidate of input) {
    if (!candidate || typeof candidate !== 'object') continue
    const provider = String(candidate.provider || '')
    const model = String(candidate.model || '')
    if (!provider || !model) continue
    const key = `${provider}\u0000${model}`
    if (seen.has(key)) continue
    seen.add(key)
    routes.push({ provider, model })
  }
  return routes
}

function readSessionPolicy(ctx, sessionId) {
  const sessions = ctx.get('sessions')
  const session = sessions?.get(sessionId)
  if (!session) return { id: sessionId, live: false, allowedModels: null }
  return { id: sessionId, live: true, allowedModels: scanPolicyEvent(session) }
}

function scanPolicyEvent(session) {
  let routes = null
  let events = []
  try {
    events = session.snapshotEvents() || []
  } catch {
    try {
      events = session.ownEvents() || []
    } catch {
      return null
    }
  }
  for (const event of events) {
    if (event?.type !== POLICY_EVENT) continue
    const next = normalizeRoutes(event?.data?.allowedModels)
    if (next.length > 0) routes = next
  }
  return routes
}

function listLiveSessions(ctx) {
  try {
    const sessions = ctx.get('sessions')
    const list = sessions?.list?.() || []
    return list.slice(-MAX_SESSION_ROWS).map((session) => ({
      id: String(session?.id || ''),
      origin: session?.header?.origin === 'subagent' ? 'subagent' : 'top',
      policy: scanPolicyEvent(session)?.length ?? null,
    }))
  } catch {
    return []
  }
}

/* ------------------------------------------------------------------ *
 * rendering for the tool result
 * ------------------------------------------------------------------ */

function describeState(state) {
  const lines = []
  lines.push(`子 Agent 模型策略：${state.enabled ? '已启用' : '未启用'}（配置行 ${state.ns}${state.writable ? '' : '，只读'}）`)
  lines.push(`白名单（${state.allowedModels.length}）：${state.allowedModels.map((r) => `${r.provider}/${r.model}`).join(', ') || '空'}`)
  if (state.session) {
    const current = state.session.allowedModels
    lines.push(`当前会话 ${state.session.id}：${state.session.live ? (current && current.length ? current.map((r) => `${r.provider}/${r.model}`).join(', ') : '无策略（子 Agent 只能跟随父会话模型）') : '不在线'}`)
  }
  lines.push(`可用模型目录（${state.models.length}）：`)
  for (const model of state.models) {
    lines.push(`  - ${model.provider}/${model.model} — ${model.name}${model.badge ? ` [${model.badge}]` : ''}`)
  }
  if (state.warnings?.length) {
    lines.push(`读取告警：${state.warnings.join(' | ')}`)
  }
  return lines.join('\n')
}

function warn(error) {
  try {
    console.warn('[dsh-subagent-models]', messageOf(error))
  } catch {
    /* ignore */
  }
}

function messageOf(error) {
  if (error instanceof Error) return error.message
  return String(error ?? 'unknown error')
}
