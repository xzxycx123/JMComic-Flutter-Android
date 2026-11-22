/**
 * dsh-subagent-models — Client half.
 *
 * 三处入口，同一份数据与同一组操作：
 *   1. conversation.hero.options  —— 新建会话行的「子Agent模型」按钮，打开选择窗口
 *   2. shell.overlay              —— 选择窗口本身（模态弹窗，点遮罩 / Esc 关闭）
 *   3. conversation.composer.dock —— 输入框下方的常驻条，展开即内联面板
 *
 * 勾选即写 DSH 的 subagent-model-selection-settings 配置行；
 * 「应用到当前会话」再把同一份白名单追写进当前会话的
 * subagent/model-selection-policy 事件。
 */

window.__ModuleLoader__.load({
  id: 'dsh-subagent-models',
  factory(require) {
    const React = require('react')
    const h = React.createElement
    const { useCallback, useEffect, useMemo, useState } = React

    const NS = 'subagent-models'
    const API = '/subagent-models/api'

    const zh = {
      title: '子Agent模型',
      summaryOn: '已启用',
      summaryOff: '跟随父会话',
      summaryUnknown: '读取中…',
      expand: '展开',
      collapse: '收起',
      open: '选择模型',
      dialogTitle: '子 Agent 允许使用的模型',
      dialogSubtitle: '这里的勾选会写进 DSH 的子 Agent 模型选择设置。',
      close: '关闭',
      intro: '勾选子 Agent 允许使用的模型。没有策略时子 Agent 只能跟随父会话那一条路由，勾选后它就能挑便宜的路由跑。',
      appliesToNew: '保存后对新建会话自动生效；当前这个会话要立刻用上，就点下面的「应用到当前会话」。',
      master: '启用子 Agent 模型选择',
      allowed: '可选模型',
      allowedCount: '个已允许',
      modelsTotal: '个模型',
      selectAll: '全选',
      clear: '清空',
      apply: '应用到当前会话',
      applied: '已写入当前会话 ✓',
      saved: '已保存 ✓',
      saving: '保存中…',
      loading: '读取模型目录…',
      noModels: '没有读到任何模型（先在 设置 → 模型 里配好 provider）',
      emptyPolicy: '未选任何模型：子 Agent 只能跟随父会话的模型。',
      readOnly: '当前环境不可写设置',
      failedPrefix: '操作失败：',
      sessionNone: '当前会话还没有策略，点「应用到当前会话」即可立即生效。',
      sessionHas: '当前会话已生效：',
      refresh: '刷新',
      warnings: '告警',
    }

    const en = {
      title: 'Subagent models',
      summaryOn: 'enabled',
      summaryOff: 'inherits parent',
      summaryUnknown: 'loading…',
      expand: 'Expand',
      collapse: 'Collapse',
      open: 'Pick models',
      dialogTitle: 'Models a subagent may use',
      dialogSubtitle: 'Your ticks are written to the DSH subagent model selection settings.',
      close: 'Close',
      intro: 'Tick the models a subagent may run on. Without a policy a subagent can only inherit the parent route; with one it can pick a cheaper route.',
      appliesToNew: 'Saved values apply to new sessions automatically. Use “Apply to this session” to make this session use them right away.',
      master: 'Enable subagent model selection',
      allowed: 'Allowed models',
      allowedCount: 'allowed',
      modelsTotal: 'models',
      selectAll: 'All',
      clear: 'None',
      apply: 'Apply to this session',
      applied: 'Written to this session ✓',
      saved: 'Saved ✓',
      saving: 'Saving…',
      loading: 'Reading model directory…',
      noModels: 'No models found. Configure a provider under Settings → Models first.',
      emptyPolicy: 'Nothing selected: subagents can only inherit the parent model.',
      readOnly: 'Settings are read-only in this environment',
      failedPrefix: 'Failed: ',
      sessionNone: 'This session has no policy yet. Use “Apply to this session”.',
      sessionHas: 'Active in this session: ',
      refresh: 'Refresh',
      warnings: 'Warnings',
    }

    const S = {
      root: {
        marginTop: 6,
        border: '1px solid var(--dsw-alias-border-l1)',
        borderRadius: 10,
        background: 'var(--dsw-alias-bg-layer-1)',
        color: 'var(--dsw-alias-label-primary)',
        fontSize: 12,
        overflow: 'hidden',
      },
      bar: {
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        padding: '6px 10px',
        cursor: 'pointer',
        userSelect: 'none',
      },
      badge: { display: 'inline-flex', alignItems: 'center', gap: 5, fontWeight: 600 },
      dot: (on) => ({
        width: 7,
        height: 7,
        borderRadius: 4,
        background: on ? 'var(--dsw-alias-state-success-primary)' : 'var(--dsw-alias-state-idle-primary)',
        display: 'inline-block',
      }),
      meta: { color: 'var(--dsw-alias-label-secondary)', flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
      panel: {
        borderTop: '1px solid var(--dsw-alias-border-l1)',
        padding: '8px 10px 10px',
        maxHeight: '38vh',
        overflowY: 'auto',
      },
      intro: { color: 'var(--dsw-alias-label-secondary)', lineHeight: 1.5, marginBottom: 8 },
      row: { display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap', marginBottom: 8 },
      switchLabel: { display: 'inline-flex', alignItems: 'center', gap: 6, fontWeight: 600 },
      group: { marginTop: 8 },
      groupName: {
        color: 'var(--dsw-alias-label-secondary)',
        textTransform: 'uppercase',
        letterSpacing: '.04em',
        fontSize: 10,
        margin: '6px 0 4px',
      },
      chip: (on, disabled) => ({
        display: 'inline-flex',
        alignItems: 'center',
        gap: 6,
        padding: '3px 9px',
        margin: '0 6px 6px 0',
        borderRadius: 999,
        border: `1px solid ${on ? 'var(--dsw-alias-brand-primary)' : 'var(--dsw-alias-border-l2)'}`,
        background: on ? 'color-mix(in srgb, var(--dsw-alias-brand-primary) 14%, transparent)' : 'transparent',
        color: 'inherit',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.55 : 1,
        font: 'inherit',
      }),
      chipBadge: { color: 'var(--dsw-alias-label-secondary)', fontSize: 10 },
      button: (primary) => ({
        padding: '4px 10px',
        borderRadius: 8,
        border: `1px solid ${primary ? 'var(--dsw-alias-brand-primary)' : 'var(--dsw-alias-border-l2)'}`,
        background: primary ? 'var(--dsw-alias-brand-primary)' : 'transparent',
        color: primary ? '#fff' : 'inherit',
        cursor: 'pointer',
        font: 'inherit',
      }),
      heroChip: {
        display: 'inline-flex',
        alignItems: 'center',
        gap: 6,
        padding: '4px 10px',
        borderRadius: 999,
        border: '1px solid var(--dsw-alias-border-l2)',
        background: 'transparent',
        color: 'var(--dsw-alias-label-secondary)',
        cursor: 'pointer',
        font: 'inherit',
        fontSize: 12,
      },
      subtle: { marginTop: 6, color: 'var(--dsw-alias-label-secondary)', lineHeight: 1.5 },
      error: { marginTop: 6, color: 'var(--dsw-alias-state-error-primary)', lineHeight: 1.5, wordBreak: 'break-word' },
      ok: { marginTop: 6, color: 'var(--dsw-alias-state-success-primary)' },
      scrim: {
        position: 'fixed',
        inset: 0,
        zIndex: 2147483000,
        // shell.overlay 整层是 click-through，这里显式把指针事件要回来。
        pointerEvents: 'auto',
        background: 'rgba(0, 0, 0, 0.42)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 16,
      },
      dialog: {
        width: 'min(620px, 94vw)',
        maxHeight: '80vh',
        overflowY: 'auto',
        background: 'var(--dsw-alias-bg-overlay)',
        color: 'var(--dsw-alias-label-primary)',
        border: '1px solid var(--dsw-alias-border-l2)',
        borderRadius: 14,
        boxShadow: '0 18px 48px rgba(0, 0, 0, 0.38)',
        padding: '14px 16px 16px',
        fontSize: 12.5,
      },
      dialogHead: { display: 'flex', alignItems: 'flex-start', gap: 10, marginBottom: 10 },
      dialogTitle: { fontWeight: 700, fontSize: 14, lineHeight: 1.4 },
      dialogSubtitle: { color: 'var(--dsw-alias-label-secondary)', marginTop: 2, lineHeight: 1.5 },
      closeButton: {
        marginLeft: 'auto',
        flex: '0 0 auto',
        width: 26,
        height: 26,
        lineHeight: '22px',
        textAlign: 'center',
        borderRadius: 8,
        border: '1px solid var(--dsw-alias-border-l2)',
        background: 'transparent',
        color: 'inherit',
        cursor: 'pointer',
        font: 'inherit',
        fontSize: 14,
      },
      footer: {
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        flexWrap: 'wrap',
        marginTop: 10,
        paddingTop: 10,
        borderTop: '1px solid var(--dsw-alias-border-l1)',
      },
    }

    /* ---------------------------------------------------------------- *
     * modal open state shared by the hero button and the overlay
     * ---------------------------------------------------------------- */

    const opener = { open: false, sessionId: null, listeners: new Set() }

    function setOpener(next) {
      opener.open = next.open === true
      opener.sessionId = next.sessionId ?? null
      for (const listener of [...opener.listeners]) {
        try {
          listener()
        } catch {
          /* ignore */
        }
      }
    }

    function useOpener() {
      const [, bump] = useState(0)
      useEffect(() => {
        const listener = () => bump((value) => value + 1)
        opener.listeners.add(listener)
        return () => {
          opener.listeners.delete(listener)
        }
      }, [])
      return opener
    }

    /* ---------------------------------------------------------------- *
     * data + actions
     * ---------------------------------------------------------------- */

    async function callApi(payload) {
      const response = await fetch(API, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify(payload),
      })
      let data = null
      try {
        data = await response.json()
      } catch {
        data = null
      }
      if (!response.ok || !data || data.ok === false) {
        throw new Error((data && data.error) || `HTTP ${response.status}`)
      }
      return data
    }

    const keyOf = (route) => `${route.provider}\u0000${route.model}`

    function usePicker(sessionId, t) {
      const [state, setState] = useState(null)
      const [busy, setBusy] = useState(false)
      const [note, setNote] = useState('')
      const [error, setError] = useState('')

      const reload = useCallback(async (refresh) => {
        try {
          const data = await callApi({ op: 'state', sessionId, refresh: refresh === true })
          setState(data)
          setError('')
        } catch (cause) {
          setError(String((cause && cause.message) || cause))
        }
      }, [sessionId])

      useEffect(() => {
        reload(false)
      }, [reload])

      const routes = state?.allowedModels ?? []
      const selected = useMemo(() => new Set(routes.map(keyOf)), [routes])

      const persist = useCallback(async (next) => {
        setBusy(true)
        setNote('')
        setError('')
        try {
          const data = await callApi({
            op: 'save',
            enabled: next.enabled,
            allowedModels: next.allowedModels,
            sessionId,
          })
          setState(data)
          setNote(t('saved'))
        } catch (cause) {
          setError(String((cause && cause.message) || cause))
        } finally {
          setBusy(false)
        }
      }, [sessionId, t])

      const applyNow = useCallback(async () => {
        setBusy(true)
        setNote('')
        setError('')
        try {
          const data = await callApi({ op: 'apply', sessionId, allowedModels: routes })
          setState(data)
          setNote(t('applied'))
        } catch (cause) {
          setError(String((cause && cause.message) || cause))
        } finally {
          setBusy(false)
        }
      }, [sessionId, routes, t])

      return {
        state,
        busy,
        note,
        error,
        routes,
        selected,
        reload,
        persist,
        applyNow,
        toggleModel(model) {
          if (!state || state.writable === false) return
          const key = keyOf(model)
          const next = selected.has(key)
            ? routes.filter((route) => keyOf(route) !== key)
            : [...routes, { provider: model.provider, model: model.model }]
          // 取消最后一个模型时自动关掉启用位，避免「启用但没有任何模型」的非法状态。
          persist({ enabled: next.length === 0 ? false : true, allowedModels: next })
        },
        toggleEnabled() {
          if (!state || state.writable === false) return
          const enabled = !state.enabled
          if (enabled && routes.length === 0) {
            setError(t('emptyPolicy'))
            return
          }
          persist({ enabled, allowedModels: routes })
        },
        selectAll() {
          if (!state) return
          const all = (state.models ?? []).map((model) => ({ provider: model.provider, model: model.model }))
          persist({ enabled: true, allowedModels: all })
        },
        clearAll() {
          if (!state) return
          persist({ enabled: false, allowedModels: [] })
        },
      }
    }

    /* ---------------------------------------------------------------- *
     * shared body
     * ---------------------------------------------------------------- */

    function PickerBody(props) {
      const { picker, t, variant } = props
      const { state, busy, note, error, routes, selected } = picker
      const groups = useMemo(() => {
        const map = new Map()
        for (const model of state?.models ?? []) {
          const list = map.get(model.provider) ?? []
          list.push(model)
          map.set(model.provider, list)
        }
        return [...map.entries()]
      }, [state])

      const enabled = state?.enabled === true
      const sessionText = state?.session?.allowedModels?.length
        ? `${t('sessionHas')}${state.session.allowedModels.map((route) => `${route.provider}/${route.model}`).join(', ')}`
        : t('sessionNone')

      return h('div', null,
        variant === 'dialog'
          ? h('div', { style: S.intro }, t('intro'), ' ', t('appliesToNew'))
          : h('div', { style: S.intro }, t('intro')),
        h('div', { style: S.row },
          h('label', { style: S.switchLabel },
            h('input', {
              type: 'checkbox',
              checked: enabled,
              disabled: busy || state?.writable === false,
              onChange: picker.toggleEnabled,
              style: { accentColor: 'var(--dsw-alias-brand-primary)' },
            }),
            t('master'),
          ),
          h('span', { style: { flex: 1 } }),
          h('button', { type: 'button', style: S.button(false), disabled: busy || !state, onClick: picker.selectAll }, t('selectAll')),
          h('button', { type: 'button', style: S.button(false), disabled: busy || !state, onClick: picker.clearAll }, t('clear')),
          h('button', { type: 'button', style: S.button(false), disabled: busy, onClick: () => picker.reload(true) }, t('refresh')),
        ),
        state === null ? h('div', { style: S.subtle }, t('loading')) : null,
        state !== null && groups.length === 0 ? h('div', { style: S.subtle }, t('noModels')) : null,
        groups.map(([provider, models]) => h('div', { key: provider, style: S.group },
          h('div', { style: S.groupName }, models[0]?.providerName || provider),
          models.map((model) => {
            const on = selected.has(keyOf(model))
            return h('button', {
              key: keyOf(model),
              type: 'button',
              style: S.chip(on, busy || state?.writable === false),
              title: `${model.provider}/${model.model}`,
              onClick: () => picker.toggleModel(model),
            }, `${on ? '✓ ' : ''}${model.name}`, model.badge ? h('span', { style: S.chipBadge }, model.badge) : null)
          }),
        )),
        variant === 'dialog'
          ? h('div', { style: S.footer },
            h('button', {
              type: 'button',
              style: S.button(true),
              disabled: busy || routes.length === 0,
              onClick: picker.applyNow,
            }, t('apply')),
            h('span', { style: S.meta }, sessionText),
          )
          : h('div', { style: S.row },
            h('button', {
              type: 'button',
              style: S.button(true),
              disabled: busy || routes.length === 0,
              onClick: picker.applyNow,
            }, t('apply')),
            h('span', { style: S.meta }, sessionText),
          ),
        state?.writable === false ? h('div', { style: S.subtle }, t('readOnly')) : null,
        state?.warnings?.length ? h('div', { style: S.subtle }, `${t('warnings')}: ${state.warnings.join(' | ')}`) : null,
        error ? h('div', { style: S.error }, `${t('failedPrefix')}${error}`) : null,
        note ? h('div', { style: S.ok }, note) : null,
      )
    }

    /* ---------------------------------------------------------------- *
     * 1. composer dock (inline)
     * ---------------------------------------------------------------- */

    function SubagentModelDock(props) {
      const t = props.t || ((key) => key)
      const picker = usePicker(props.sessionId, t)
      const [open, setOpen] = useState(false)
      const enabled = picker.state?.enabled === true
      const summary = picker.state === null
        ? t('summaryUnknown')
        : `${enabled ? t('summaryOn') : t('summaryOff')} · ${picker.routes.length} ${t('allowedCount')}`

      return h('div', { style: S.root },
        h('div', {
          style: S.bar,
          role: 'button',
          tabIndex: 0,
          title: open ? t('collapse') : t('expand'),
          onClick: () => setOpen((value) => !value),
          onKeyDown: (event) => {
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault()
              setOpen((value) => !value)
            }
          },
        },
          h('span', { style: S.badge }, h('span', { style: S.dot(enabled) }), t('title')),
          h('span', { style: S.meta }, summary),
          h('span', { style: S.meta, textAlign: 'right', flex: '0 0 auto' }, open ? t('collapse') : t('expand')),
        ),
        open ? h('div', { style: S.panel }, h(PickerBody, { picker, t, variant: 'inline' })) : null,
      )
    }

    /* ---------------------------------------------------------------- *
     * 2. new-session hero button
     * ---------------------------------------------------------------- */

    function HeroModelButton(props) {
      const t = props.t || ((key) => key)
      const [summary, setSummary] = useState(null)

      useEffect(() => {
        let alive = true
        callApi({ op: 'state', sessionId: props.sessionId })
          .then((data) => {
            if (alive) setSummary(data)
          })
          .catch(() => {
            /* the dialog surfaces failures; the chip can stay plain */
          })
        return () => {
          alive = false
        }
      }, [props.sessionId])

      const count = summary?.allowedModels?.length ?? null
      const label = count === null
        ? t('title')
        : `${t('title')} · ${count} ${t('allowedCount')}`

      return h('button', {
        type: 'button',
        style: S.heroChip,
        title: t('dialogTitle'),
        onClick: () => setOpener({ open: true, sessionId: props.sessionId ?? null }),
      }, h('span', { style: S.dot(summary?.enabled === true) }), label)
    }

    /* ---------------------------------------------------------------- *
     * 3. the selection window itself
     * ---------------------------------------------------------------- */

    function PickerDialogCard(props) {
      const t = props.t || ((key) => key)
      const picker = usePicker(props.sessionId, t)

      useEffect(() => {
        const onKey = (event) => {
          if (event.key === 'Escape') props.close()
        }
        document.addEventListener('keydown', onKey)
        return () => document.removeEventListener('keydown', onKey)
      }, [props.close])

      return h('div', {
        style: S.scrim,
        onMouseDown: (event) => {
          if (event.target === event.currentTarget) props.close()
        },
      },
        h('div', {
          style: S.dialog,
          role: 'dialog',
          'aria-modal': 'true',
          'aria-label': t('dialogTitle'),
        },
          h('div', { style: S.dialogHead },
            h('div', null,
              h('div', { style: S.dialogTitle }, t('dialogTitle')),
              h('div', { style: S.dialogSubtitle }, t('dialogSubtitle')),
            ),
            h('button', { type: 'button', style: S.closeButton, title: t('close'), onClick: props.close }, '×'),
          ),
          h(PickerBody, { picker, t, variant: 'dialog' }),
        ),
      )
    }

    function PickerDialog() {
      const snapshot = useOpener()
      if (!snapshot.open) return null
      return h(PickerDialogCard, {
        key: snapshot.sessionId ?? 'none',
        sessionId: snapshot.sessionId ?? undefined,
        t: translate,
        close: () => setOpener({ open: false }),
      })
    }

    /* ---------------------------------------------------------------- *
     * wiring
     * ---------------------------------------------------------------- */

    let translate = (key) => key

    return {
      name: 'dsh-subagent-models',
      inject: ['slots', 'locale'],
      apply(ctx) {
        let bound = (key) => key
        try {
          ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'dsh-subagent-models: dictionaries')
          bound = ctx.locale.bind(NS)
        } catch {
          /* keep the raw keys when the locale service is unavailable */
        }
        translate = bound

        // 输入框下方的常驻条
        ctx.slots.inject('conversation.composer.dock', () => ctx.slots.register({
          name: 'conversation.composer.dock',
          id: 'subagent-models',
          order: 2,
          label: () => bound('title'),
          inject: (sessionId) => ({ sessionId, t: bound }),
        }, SubagentModelDock))

        // 新建会话行里的入口
        ctx.slots.inject('conversation.hero.options', () => ctx.slots.register({
          name: 'conversation.hero.options',
          id: 'subagent-models',
          order: 10,
          label: () => bound('open'),
          inject: (sessionId) => ({ sessionId, t: bound }),
        }, HeroModelButton))

        // 选择窗口（浮层）
        ctx.slots.inject('shell.overlay', () => ctx.slots.register({
          name: 'shell.overlay',
          id: 'subagent-models-dialog',
          order: 90,
        }, PickerDialog))
      },
    }
  },
})
