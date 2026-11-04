// A screen: the app's ScreenSaverView (saver/ApplarchySaverView.swift) for the web.
// The engine hands out ANSI frames; they're parsed into a grid of cells and drawn as
// pixel art, block characters as exact rectangles and everything else as Menlo glyphs.
// Only cells that changed since the last frame are repainted.
import { clockGlyph, GENTLE, themedCommand, THEMES, type Theme } from './data'
import { loadEngine, type Effect, type Engine } from './engine'

export interface ClockOptions { show: boolean; date: boolean; hour: 'auto' | '12' | '24'; large: boolean }

export interface ScreenOptions {
  logo: string
  theme?: Theme
  playlist?: string[]
  clock?: ClockOptions
  pauseMs?: number
  /** Pick a new theme for every effect (the hero). */
  cycleThemes?: boolean
  /** Click for full screen, as the app's preview does. */
  fullscreen?: boolean
  /** false: show the settled logo, and play only while hovered (the theme cards). */
  autoplay?: boolean
  onEffect?: (effect: string, theme: Theme) => void
}

const NONE = 0xffffffff
const DEFAULT_FG = 0xc0c0c0
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)')

/** What the page's engine has done so far (shown in "Under the hood"). */
export const stats = { frames: 0, engineMs: 0, draws: 0, drawMs: 0, effects: 0 }

/** 1 on a 1512 × 982 pt screen (Omarchy's screensaver size): the app's layoutScale. */
const layoutScale = (w: number, h: number) => Math.min(w / 1512, h / 982)

const colorCache = new Map<number, string>()
const css = (rgb: number) => {
  let s = colorCache.get(rgb)
  if (!s) {
    if (colorCache.size > 4096) colorCache.clear()
    colorCache.set(rgb, (s = '#' + rgb.toString(16).padStart(6, '0')))
  }
  return s
}

export class Screen {
  readonly el: HTMLElement
  private canvas: HTMLCanvasElement
  private clockCanvas?: HTMLCanvasElement   // made the first time a clock shows
  private ctx: CanvasRenderingContext2D
  private engine?: Engine
  private effect: Effect | null = null
  private effectName = ''
  private opts: Required<Omit<ScreenOptions, 'onEffect'>> & Pick<ScreenOptions, 'onEffect'>
  private playlist: string[] = []
  private once: string | null = null

  // grid (device pixels)
  private W = 0; private H = 0; private dpr = 1; private scale = 1
  private cols = 0; private rows = 0; private cellW = 0; private cellH = 0; private baseline = 0
  private extra = 0; private ox = 0; private oy = 0
  private font = ''
  private scalar = new Uint32Array(0); private fg = new Uint32Array(0); private bg = new Uint32Array(0)
  private pScalar = new Uint32Array(0); private pFg = new Uint32Array(0); private pBg = new Uint32Array(0)
  private dirty = new Uint8Array(0)

  // timeline
  private t0 = 0
  private raf = 0
  private holdTimer = 0
  private clockTimer = 0
  private visible = false
  private started = false
  private params: number[] = []
  private armed: boolean
  private hovering = false
  private still = false

  constructor(host: HTMLElement, options: ScreenOptions) {
    this.opts = {
      theme: THEMES[1], playlist: ['decrypt'], pauseMs: 3000, cycleThemes: false, fullscreen: false, autoplay: true,
      clock: { show: true, date: true, hour: 'auto', large: false }, ...options,
    }
    this.armed = this.opts.autoplay
    this.el = host
    host.classList.add('screen')
    this.canvas = document.createElement('canvas')
    this.canvas.setAttribute('aria-hidden', 'true')
    host.append(this.canvas)
    this.ctx = this.canvas.getContext('2d', { alpha: false })!
    this.paintBackground()

    new ResizeObserver(() => this.layout()).observe(host)
    new IntersectionObserver(([e]) => { this.visible = e.isIntersecting; this.wake() }, { rootMargin: '120px' }).observe(host)
    document.addEventListener('visibilitychange', () => this.wake())
    if (this.opts.fullscreen) {
      host.addEventListener('click', () => this.toggleFullscreen())
      host.title = 'Click for full screen'
    }
  }

  get theme() { return this.opts.theme }

  /** How far the logo sits below the centre when there's a clock, in CSS pixels (Smooth Mode glides it up). */
  get clockOffset() {
    if (!this.W) return 0
    const s = this.scale * this.dpr
    return (38 * s + this.clockHeight()) / 2 / this.dpr
  }
  get current() { return this.effectName }

  setTheme(theme: Theme, restart = true) {
    if (theme.id === this.opts.theme.id) return
    this.opts.theme = theme
    this.paintBackground()
    this.layout(true)
    if (restart) this.restart()
  }

  setLogo(logo: string) {
    if (logo === this.opts.logo) return
    this.opts.logo = logo
    this.layout(true)
    this.restart()
  }

  setPlaylist(ids: string[]) {
    this.opts.playlist = ids.length ? ids : ['decrypt']
    this.playlist = []
  }

  setClock(clock: ClockOptions) {
    this.opts.clock = clock
    this.layout(true)
    this.restart()
  }

  setPause(ms: number) { this.opts.pauseMs = ms }

  /** Play `id` now, once, then carry on with the playlist (clicking an effect's name). */
  preview(id: string) {
    this.once = id
    this.restart()
  }

  /** Hovered (or focused): play; let go: the current effect finishes, then it rests. */
  hover(on: boolean) {
    this.hovering = on
    if (on && !this.armed) {
      this.armed = true
      this.restart()
    }
  }

  restart() {
    this.effect?.free()
    this.effect = null
    cancelAnimationFrame(this.raf)
    clearTimeout(this.holdTimer)
    this.raf = this.holdTimer = 0
    this.wake()
  }

  // MARK: layout

  private paintBackground() {
    this.el.style.setProperty('--screen-bg', '#' + this.opts.theme.background)
  }

  private layout(force = false) {
    const rect = this.el.getBoundingClientRect()
    if (!rect.width || !rect.height) return
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    const W = Math.round(rect.width * dpr), H = Math.round(rect.height * dpr)
    if (!force && W === this.W && H === this.H) return
    const resized = W !== this.W || H !== this.H
    this.W = W; this.H = H; this.dpr = dpr
    this.scale = layoutScale(rect.width, rect.height)
    this.canvas.width = W
    this.canvas.height = H
    if (this.clockCanvas) { this.clockCanvas.width = W; this.clockCanvas.height = H }

    // Font size 18 on a 1512 × 982 pt screen, scaled to the view (layoutGrid).
    const size = Math.max(3, 18 * this.scale) * dpr
    this.font = `${size}px Menlo, "DejaVu Sans Mono", Consolas, "Liberation Mono", ui-monospace, monospace`
    const ctx = this.ctx
    ctx.font = this.font
    const m = ctx.measureText('M')
    this.cellW = m.width
    const ascent = m.fontBoundingBoxAscent ?? size * 0.93, descent = m.fontBoundingBoxDescent ?? size * 0.24
    this.cellH = Math.ceil(ascent + descent)
    this.baseline = (this.cellH - ascent - descent) / 2 + ascent
    this.cols = Math.max(1, Math.floor(W / this.cellW))
    this.rows = Math.max(1, Math.floor(H / this.cellH))
    this.ox = Math.floor((W - this.cols * this.cellW) / 2)
    this.oy = Math.floor((H - this.rows * this.cellH) / 2)
    const n = this.cols * this.rows
    this.scalar = new Uint32Array(n); this.fg = new Uint32Array(n); this.bg = new Uint32Array(n).fill(NONE)
    this.pScalar = new Uint32Array(n); this.pFg = new Uint32Array(n); this.pBg = new Uint32Array(n).fill(NONE)
    this.dirty = new Uint8Array(n)
    this.extra = this.logoLayout().extra
    this.still = false
    ctx.fillStyle = '#' + this.opts.theme.background
    ctx.fillRect(0, 0, W, H)
    this.drawClock()
    if (resized && this.started) this.restart()
  }

  private get logoLines() { return this.opts.logo.replace(/\n$/, '').split('\n').length }

  private clockMetrics() {
    const s = this.scale * this.dpr, large = this.opts.clock.large
    return {
      date: Math.max(1, Math.floor((large ? 5 : 4) * s)),
      time: Math.max(1, Math.floor((large ? 18 : 13) * s)),
      gap: Math.round((large ? 16 : 14) * s),
    }
  }

  private clockHeight() {
    const m = this.clockMetrics()
    return (this.opts.clock.date ? 7 * m.date + m.gap : 0) + 7 * m.time
  }

  /** ttfx centres the logo in its canvas; a canvas `extra` rows taller than the screen
   *  (only the top rows drawn) moves it down half a row per row. Pick the `extra` that
   *  puts it closest to the centre of the space under the clock (logoLayout). */
  private logoLayout() {
    const lines = this.logoLines
    const top = this.opts.clock.show ? 38 * this.scale * this.dpr + this.clockHeight() : 0
    const centre = (top + this.H) / 2
    let best = { extra: 0, topRow: Math.max(0, Math.floor((this.rows - lines) / 2)), err: Infinity }
    for (let extra = 0; extra <= Math.max(0, this.rows - lines); extra++) {
      const topRow = Math.floor((this.rows + extra) / 2) - Math.ceil(lines / 2)
      const err = Math.abs(this.oy + (topRow + lines / 2) * this.cellH - centre)
      if (err < best.err) best = { extra, topRow, err }
    }
    return best
  }

  // MARK: clock

  private drawClock() {
    clearTimeout(this.clockTimer)
    const c = this.opts.clock
    if (!this.clockCanvas) {
      if (!c.show) return
      this.clockCanvas = document.createElement('canvas')
      this.clockCanvas.setAttribute('aria-hidden', 'true')
      this.clockCanvas.width = this.W
      this.clockCanvas.height = this.H
      this.el.append(this.clockCanvas)
    }
    const ctx = this.clockCanvas.getContext('2d')!
    ctx.clearRect(0, 0, this.W, this.H)
    if (!c.show || !this.W) return
    const m = this.clockMetrics()
    // Midway between the top of the screen and the top of the logo.
    const logoTop = this.oy + this.logoLayout().topRow * this.cellH
    let y = Math.max(0, Math.round((logoTop - this.clockHeight()) / 2))
    const now = new Date()
    const rgb = parseInt(this.opts.theme.foreground, 16)
    const [r, g, b] = [rgb >> 16 & 255, rgb >> 8 & 255, rgb & 255]
    if (c.date) {
      ctx.fillStyle = `rgba(${r * 0.66 | 0},${g * 0.66 | 0},${b * 0.66 | 0},0.92)`
      const date = now.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })
        .normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/,/g, '').toUpperCase()
      this.pixelText(ctx, date, m.date, y)
      y += 7 * m.date + m.gap
    }
    ctx.fillStyle = `rgba(${r},${g},${b},0.95)`
    this.pixelText(ctx, timeString(now, c.hour), m.time, y)
    this.clockTimer = window.setTimeout(() => this.drawClock(), 60_000 - (Date.now() % 60_000) + 50)
  }

  private pixelText(ctx: CanvasRenderingContext2D, text: string, p: number, top: number) {
    const glyphs = [...text].map(clockGlyph)
    const width = glyphs.reduce((w, g) => w + g[0].length + 1, 0) - 1
    let x = Math.round(this.W / 2 - width * p / 2)
    for (const g of glyphs) {
      g.forEach((row, r) => { for (let c = 0; c < row.length; c++) if (row[c] === '#') ctx.fillRect(x + c * p, top + r * p, p, p) })
      x += (g[0].length + 1) * p
    }
  }

  // MARK: timeline

  private paused = false
  private get running() { return this.visible && !document.hidden && !this.paused }

  /** Hold still where it is (the wallpaper, when its desktop is covered). */
  pause(on: boolean) {
    this.paused = on
    this.wake()
  }

  private wake() {
    if (!this.running) {
      cancelAnimationFrame(this.raf)
      this.raf = 0
      return
    }
    if (this.raf || this.holdTimer) return
    if (!this.engine) {
      loadEngine().then(e => { this.engine = e; this.wake() })
      return
    }
    this.started = true
    if (!this.effect && !this.armed) return this.drawStill()
    if (!this.effect) this.startNext()
    else this.t0 = performance.now() - this.effect.frames / 0.12   // carry on where it paused
    this.raf = requestAnimationFrame(this.tick)
  }

  /** The settled logo, without the animation: an effect run to its end in one go. */
  private drawStill() {
    if (this.still || !this.engine || !this.W) return
    this.still = true
    const effect = this.engine.effect(this.opts.logo, this.cols, this.rows + this.extra, themedCommand('print', this.opts.theme))
    if (!effect) return
    const t = performance.now()
    let frame: Uint8Array | null, any = false
    while ((frame = effect.advance(256))) { this.parse(frame); any = true }
    stats.engineMs += performance.now() - t
    stats.frames += effect.frames
    stats.effects++
    if (any) this.draw()
    effect.free()
  }

  private nextEffectName(): string {
    if (this.once) { const id = this.once; this.once = null; return id }
    const pool = reducedMotion.matches ? this.opts.playlist.filter(id => GENTLE.has(id)) : this.opts.playlist
    const source = pool.length ? pool : [...GENTLE]
    // Each once, in random order, before any repeats.
    if (!this.playlist.length) {
      this.playlist = [...source].sort(() => Math.random() - 0.5)
      if (this.playlist.length > 1 && this.playlist[0] === this.effectName) this.playlist.push(this.playlist.shift()!)
    }
    return this.playlist.shift()!
  }

  private startNext() {
    if (!this.engine || !this.W) return
    const name = this.nextEffectName()
    if (this.opts.cycleThemes) {
      const others = THEMES.filter(t => t.id !== this.opts.theme.id)
      this.opts.theme = others[Math.floor(Math.random() * others.length)]
      this.paintBackground()
      this.ctx.fillStyle = '#' + this.opts.theme.background
      this.ctx.fillRect(0, 0, this.W, this.H)
      this.pScalar.fill(NONE)
      this.drawClock()
    }
    const t = performance.now()
    this.effect?.free()
    this.effect = this.engine.effect(this.opts.logo, this.cols, this.rows + this.extra, themedCommand(name, this.opts.theme))
    stats.engineMs += performance.now() - t
    this.effectName = name
    this.t0 = performance.now()
    stats.effects++
    this.opts.onEffect?.(name, this.opts.theme)
  }

  private tick = (now: number) => {
    this.raf = 0
    const effect = this.effect
    if (!effect || !this.running) return
    // The engine runs at 120 fps whatever the display does: catch it up to where it
    // should be by now, drawing only the latest frame (a slow tick drops a frame).
    let due = Math.floor((now - this.t0) * 0.12) - effect.frames
    if (due > 8) { this.t0 += (due - 8) / 0.12; due = 8 }
    if (due > 0) {
      const t = performance.now()
      const bytes = effect.advance(due)
      const t1 = performance.now()
      stats.engineMs += t1 - t
      stats.frames += due
      if (bytes) {
        this.parse(bytes)
        this.draw()
        stats.drawMs += performance.now() - t1
        stats.draws++
      }
    }
    if (effect.done) {
      // Hold the settled logo for the pause, then the next effect.
      this.holdTimer = window.setTimeout(() => {
        this.holdTimer = 0
        if (!this.opts.autoplay && !this.hovering) { this.armed = false; this.still = true }
        this.effect?.free()
        this.effect = null
        this.wake()
      }, this.opts.pauseMs)
      return
    }
    this.raf = requestAnimationFrame(this.tick)
  }

  // MARK: frames

  private parse(b: Uint8Array) {
    const { cols, rows, scalar, fg: fgs, bg: bgs, params } = this
    scalar.fill(32)
    fgs.fill(DEFAULT_FG)
    bgs.fill(NONE)
    let row = 0, col = 0, fg = DEFAULT_FG, bg = NONE, i = 0
    const n = b.length
    while (i < n) {
      const c = b[i]
      if (c === 0x1b) {
        i++
        if (i >= n) break
        if (b[i] !== 0x5b) { i++; continue }   // ESC 7 / ESC 8
        i++
        params.length = 0
        let cur = 0, has = false
        while (i < n) {
          const d = b[i]
          if (d >= 0x30 && d <= 0x39) { cur = cur * 10 + d - 0x30; has = true }
          else if (d === 0x3b) { params.push(has ? cur : 0); cur = 0; has = false }
          else if (d !== 0x3f) break
          i++
        }
        if (has) params.push(cur)
        if (i >= n) break
        if (b[i++] === 0x6d) {   // SGR
          if (!params.length) { fg = DEFAULT_FG; bg = NONE }
          for (let j = 0; j < params.length; j++) {
            const p = params[j]
            if (p === 0) { fg = DEFAULT_FG; bg = NONE }
            else if (p === 39) fg = DEFAULT_FG
            else if (p === 49) bg = NONE
            else if (p === 38 || p === 48) {
              if (j + 4 < params.length && params[j + 1] === 2) {
                const rgb = (params[j + 2] & 255) << 16 | (params[j + 3] & 255) << 8 | (params[j + 4] & 255)
                if (p === 38) fg = rgb; else bg = rgb
                j += 4
              } else if (j + 2 < params.length && params[j + 1] === 5) j += 2
            }
          }
        }
        continue
      }
      if (c === 0x0a) { row++; col = 0; i++; continue }
      if (c === 0x0d) { col = 0; i++; continue }
      let s = c, extra = 0
      if (c >= 0xf0) { s = c & 7; extra = 3 } else if (c >= 0xe0) { s = c & 15; extra = 2 } else if (c >= 0xc0) { s = c & 31; extra = 1 }
      i++
      while (extra > 0 && i < n) { s = (s << 6) | (b[i] & 63); i++; extra-- }
      if (row < rows && col < cols) { const k = row * cols + col; scalar[k] = s; fgs[k] = fg; bgs[k] = bg }
      col++
    }
  }

  private draw() {
    const { ctx, cols, rows, scalar, fg, bg, pScalar, pFg, pBg, dirty } = this
    const n = cols * rows
    // Changed cells, and glyph cells beside them (a glyph can overhang its cell).
    let any = false
    for (let k = 0; k < n; k++) {
      if (scalar[k] !== pScalar[k] || fg[k] !== pFg[k] || bg[k] !== pBg[k]) { dirty[k] = 1; any = true }
    }
    if (!any) return
    for (let k = 0; k < n; k++) {
      if (dirty[k] !== 1) continue
      const c = k % cols
      if (c > 0 && !dirty[k - 1] && isGlyph(scalar[k - 1])) dirty[k - 1] = 2
      if (c < cols - 1 && !dirty[k + 1] && isGlyph(scalar[k + 1])) dirty[k + 1] = 2
      if (k >= cols && !dirty[k - cols] && isGlyph(scalar[k - cols])) dirty[k - cols] = 2
      if (k + cols < n && !dirty[k + cols] && isGlyph(scalar[k + cols])) dirty[k + cols] = 2
    }
    const themeBg = parseInt(this.opts.theme.background, 16)
    const { cellW, cellH, ox, oy } = this
    let style = -1
    const fill = (rgb: number) => { if (rgb !== style) { ctx.fillStyle = css(rgb); style = rgb } }
    // Backgrounds first, then contents, so an overhanging glyph isn't cut by a neighbour.
    for (let k = 0; k < n; k++) {
      if (!dirty[k]) continue
      const r = (k / cols) | 0, c = k - r * cols
      const x0 = Math.round(ox + c * cellW), y0 = Math.round(oy + r * cellH)
      fill(bg[k] === NONE ? themeBg : bg[k])
      ctx.fillRect(x0, y0, Math.round(ox + (c + 1) * cellW) - x0, Math.round(oy + (r + 1) * cellH) - y0)
    }
    ctx.font = this.font
    for (let k = 0; k < n; k++) {
      if (!dirty[k]) continue
      dirty[k] = 0
      const s = scalar[k]
      if (s === 32 || s === 0) continue
      const r = (k / cols) | 0, c = k - r * cols
      const x0 = Math.round(ox + c * cellW), y0 = Math.round(oy + r * cellH)
      const w = Math.round(ox + (c + 1) * cellW) - x0, h = Math.round(oy + (r + 1) * cellH) - y0
      fill(fg[k])
      if (s >= 0x2580 && s <= 0x259f) drawBlock(ctx, s, x0, y0, w, h)
      else ctx.fillText(String.fromCodePoint(s), x0, y0 + this.baseline)
    }
    pScalar.set(scalar); pFg.set(fg); pBg.set(bg)
  }

  private toggleFullscreen() {
    if (document.fullscreenElement) document.exitFullscreen()
    else this.el.requestFullscreen?.().catch(() => {})
  }
}

const isGlyph = (s: number) => s !== 32 && s !== 0 && (s < 0x2580 || s > 0x259f)

/** Block elements (U+2580–U+259F) as exact rectangles, so the logo has no seams. */
function drawBlock(ctx: CanvasRenderingContext2D, s: number, x: number, y: number, w: number, h: number) {
  const f = (fx: number, fy: number, fw: number, fh: number) => {
    const ax = Math.round(fx * w), ay = Math.round(fy * h)
    ctx.fillRect(x + ax, y + ay, Math.round((fx + fw) * w) - ax, Math.round((fy + fh) * h) - ay)
  }
  if (s === 0x2580) f(0, 0, 1, 0.5)
  else if (s <= 0x2587) { const k = (s - 0x2580) / 8; f(0, 1 - k, 1, k) }
  else if (s === 0x2588) f(0, 0, 1, 1)
  else if (s <= 0x258f) f(0, 0, (0x2590 - s) / 8, 1)
  else if (s === 0x2590) f(0.5, 0, 0.5, 1)
  else if (s <= 0x2593) { ctx.globalAlpha = (s - 0x2590) / 4; f(0, 0, 1, 1); ctx.globalAlpha = 1 }
  else if (s === 0x2594) f(0, 0, 1, 0.125)
  else if (s === 0x2595) f(0.875, 0, 0.125, 1)
  else {
    // quadrants: bits = upper-left, upper-right, lower-left, lower-right
    const m = [0b0010, 0b0001, 0b1000, 0b1011, 0b1001, 0b1110, 0b1101, 0b0100, 0b0110, 0b0111][s - 0x2596]
    if (m & 8) f(0, 0, 0.5, 0.5)
    if (m & 4) f(0.5, 0, 0.5, 0.5)
    if (m & 2) f(0, 0.5, 0.5, 0.5)
    if (m & 1) f(0.5, 0.5, 0.5, 0.5)
  }
}

function timeString(d: Date, hour: ClockOptions['hour']): string {
  const twelve = hour === '12' || (hour === 'auto' &&
    new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).resolvedOptions().hourCycle?.startsWith('h1'))
  const h = d.getHours(), mm = String(d.getMinutes()).padStart(2, '0')
  return twelve ? `${h % 12 || 12}:${mm} ${h < 12 ? 'AM' : 'PM'}` : `${String(h).padStart(2, '0')}:${mm}`
}
