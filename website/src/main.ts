import './styles.css'
import { EFFECTS, effectTitle, THEMES, type Theme } from './data'
import { onEngineFailure } from './engine'
import { blocksToPixels, defaultLogo, hasAppleLogo, pixelsToBlocks, stormLogo, textLogo } from './logos'
import { Screen, stats, type ClockOptions } from './screen'

// Booted: the page's failsafe (index.html) leaves the reveal animations on.
;(window as unknown as { applarchy: boolean }).applarchy = true

const $ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => root.querySelector(sel) as T
const $$ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => [...root.querySelectorAll(sel)] as T[]
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches
const swatchColors = (t: Theme) => t.stops.length ? t.stops : ['8a008a', '00d1ff', 'ffffff']

/** Said to screen readers, once: what the visitor did, or what went wrong. The lines that
 *  name the playing effect change every few seconds, so they aren't live regions. */
const announcer = $('#announce')
const announce = (text: string) => { announcer.textContent = text }

// "Click for full screen" only where an element can go full screen (not on iPhone).
if (typeof document.documentElement.requestFullscreen !== 'function') document.documentElement.classList.add('no-fullscreen')

// ---------------------------------------------------------------- reveal + scramble

/** The decrypt effect, for headings: characters churn, then lock in left to right. */
function scramble(el: HTMLElement) {
  const text = el.dataset.text ?? (el.dataset.text = el.textContent ?? '')
  if (reducedMotion) return
  const pool = '▀▄█▌▐░▒▓#*+=<>/\\|01'
  const start = performance.now()
  const lock = [...text].map((_, i) => 180 + i * 45 + Math.random() * 260)
  const step = (now: number) => {
    const t = now - start
    let out = '', done = true
    for (let i = 0; i < text.length; i++) {
      if (text[i] === ' ' || t >= lock[i]) out += text[i]
      else { out += pool[(Math.random() * pool.length) | 0]; done = false }
    }
    el.textContent = out
    if (!done) requestAnimationFrame(step)
  }
  requestAnimationFrame(step)
}

const revealer = new IntersectionObserver(entries => {
  for (const e of entries) {
    if (!e.isIntersecting) continue
    const el = e.target as HTMLElement
    el.classList.add('in')
    revealer.unobserve(el)
    if (el.matches('[data-scramble]')) scramble(el)
    $$('[data-scramble]', el).forEach(scramble)
  }
}, { rootMargin: '0px 0px -8% 0px' })
$$('.reveal, [data-scramble]').forEach(el => revealer.observe(el))

// Section links light up as you read.
const navLinks = $$<HTMLAnchorElement>('.nav-links a')
const sections = navLinks.map(a => $(a.hash)).filter(Boolean)
const sectionSpy = new IntersectionObserver(entries => {
  for (const e of entries) if (e.isIntersecting) {
    navLinks.forEach(a => a.setAttribute('aria-current', String(a.hash === '#' + e.target.id)))
  }
}, { rootMargin: '-45% 0px -50% 0px' })
sections.forEach(s => sectionSpy.observe(s))

// ---------------------------------------------------------------- hero

const SHOWY = ['decrypt', 'thunderstorm', 'beams', 'fireworks', 'matrix', 'blackhole', 'rings', 'bubbles', 'synthgrid',
  'laseretch', 'vhstape', 'smoke', 'swarm', 'unstable', 'burn', 'spotlights', 'waves', 'orbittingvolley', 'crumble', 'bouncyballs']
const heroNow = $('#hero-now')
new Screen($('#hero-screen'), {
  logo: defaultLogo(),
  theme: THEMES[1],
  playlist: SHOWY,
  cycleThemes: true,
  fullscreen: true,
  pauseMs: 2600,
  clock: { show: true, date: true, hour: 'auto', large: false },
  onEffect: (id, theme) => { heroNow.textContent = `${effectTitle(id)} · ${theme.name}` },
})

// ---------------------------------------------------------------- II. the app window

let lastPreviewed: string | null = null
const state = {
  selected: new Set(['beams', 'bubbles', 'decrypt', 'fireworks', 'matrix', 'rings', 'thunderstorm', 'blackhole']),
  theme: THEMES[1],
  logo: 'default' as 'default' | 'storm' | 'custom',
  customArt: '' as string,
  clock: { show: true, date: true, hour: 'auto', large: false } as ClockOptions,
  previewing: null as string | null,
}

const status = $('#app-status')
const fxList = $('#fx-list')
const fxFoot = $('#fx-foot')
const appScreen = new Screen($('#app-screen'), {
  logo: defaultLogo(),
  theme: state.theme,
  playlist: [...state.selected],
  fullscreen: true,
  clock: state.clock,
  onEffect: id => {
    $$('.fx-item', fxList).forEach(li => li.classList.toggle('playing', li.dataset.id === id))
    status.textContent = state.previewing === id
      ? `Previewing ${effectTitle(id)} — click it again to preview your selection`
      : state.selected.size ? `Playing ${effectTitle(id)} from your selection`
      : `Playing ${effectTitle(id)} — nothing is selected, so every effect plays`
    if (state.previewing === id) state.previewing = null
    else lastPreviewed = null          // the preview is over: a click on this effect previews it
  },
})

// The engine didn't load (no WebAssembly here, or offline): the screens show the logo
// still, and the lines that name the playing effect say why. A later load takes them over.
onEngineFailure(() => {
  heroNow.textContent = "The engine didn't load here · showing the logo still"
  status.textContent = "The preview's engine didn't load here, so the logo stands still"
  announce("The live demos couldn't load their engine, which needs WebAssembly. The logo is shown still.")
})

fxList.innerHTML = EFFECTS.map(e => `
  <li class="fx-item" data-id="${e.id}">
    <label class="check"><input type="checkbox" ${state.selected.has(e.id) ? 'checked' : ''} aria-label="Include ${e.title}"><span class="box" aria-hidden="true"></span></label>
    <button class="fx-name" type="button" aria-label="Preview ${e.title}"><b>${e.title}</b><span>${e.summary}</span></button>
  </li>`).join('')

const appActions = $$<HTMLAnchorElement>('#app .actions .big-btn')
const appNone = $('#app-none')
function selectionChanged() {
  const none = state.selected.size === 0
  fxFoot.textContent = `${state.selected.size}/${EFFECTS.length} selected · click a name to preview`
  // None ticked, as in the app: the preview plays everything, and there's nothing to apply.
  appScreen.setPlaylist(none ? EFFECTS.map(e => e.id) : [...state.selected])
  appNone.hidden = !none
  appActions.forEach(a => {
    a.setAttribute('aria-disabled', String(none))
    a.tabIndex = none ? -1 : 0
  })
}
fxList.addEventListener('change', e => {
  const input = e.target as HTMLInputElement
  const id = input.closest<HTMLElement>('.fx-item')!.dataset.id!
  if (input.checked) state.selected.add(id); else state.selected.delete(id)
  selectionChanged()
})
fxList.addEventListener('click', e => {
  const btn = (e.target as HTMLElement).closest('.fx-name')
  if (!btn) return
  const id = btn.closest<HTMLElement>('.fx-item')!.dataset.id!
  if (lastPreviewed === id && appScreen.current === id) {
    lastPreviewed = null
    status.textContent = 'Previewing your selection'
    announce('Previewing your selection')
    appScreen.restart()
    return
  }
  lastPreviewed = id
  state.previewing = id
  announce(`Previewing ${effectTitle(id)}`)
  appScreen.preview(id)
})
$$('[data-fx]').forEach(b => b.addEventListener('click', () => {
  const all = b.dataset.fx === 'all'
  state.selected = new Set(all ? EFFECTS.map(e => e.id) : [])
  $$<HTMLInputElement>('input', fxList).forEach(i => { i.checked = all })
  selectionChanged()
}))
selectionChanged()

/** Segmented control: one choice, ↔ keys move it (a radio group). */
function segmented(group: HTMLElement, onPick: (b: HTMLButtonElement) => void) {
  const buttons = $$<HTMLButtonElement>('button', group)
  const pick = (b: HTMLButtonElement) => {
    buttons.forEach(x => { x.setAttribute('aria-checked', String(x === b)); x.tabIndex = x === b ? 0 : -1 })
    onPick(b)
  }
  buttons.forEach(b => {
    b.tabIndex = b.getAttribute('aria-checked') === 'true' ? 0 : -1
    b.addEventListener('click', () => pick(b))
    b.addEventListener('keydown', e => {
      const d = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1 : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 0
      if (!d) return
      e.preventDefault()
      const next = buttons[(buttons.indexOf(b) + d + buttons.length) % buttons.length]
      next.focus()
      pick(next)
    })
  })
  return pick
}

// Logo
const customRow = $('#custom-row')
const customText = $<HTMLInputElement>('#custom-text')
if (!hasAppleLogo()) {
  $('[data-logo="default"]').title = "Chill Guy is drawn from Apple's system font: open this page on a Mac or iPhone to see it."
}
function currentLogo(): string {
  if (state.logo === 'storm') return stormLogo()
  if (state.logo === 'custom') return state.customArt || textLogo(customText.value) || defaultLogo()
  return defaultLogo()
}
const pickLogo = segmented($('#logo-seg'), b => {
  state.logo = b.dataset.logo as typeof state.logo
  customRow.hidden = state.logo !== 'custom'
  appScreen.setLogo(currentLogo())
})
let typing = 0
customText.addEventListener('input', () => {
  clearTimeout(typing)
  typing = window.setTimeout(() => { state.customArt = ''; appScreen.setLogo(currentLogo()) }, 350)
})

// Theme
const swatches = $('#theme-swatches')
const themeName = $('#theme-name')
swatches.innerHTML = THEMES.map(t => `
  <button class="swatch" type="button" role="radio" aria-checked="${t.id === state.theme.id}" aria-label="${t.name}" title="${t.name}" data-theme="${t.id}" style="background:#${t.background}">
    ${swatchColors(t).map(c => `<i style="background:#${c}"></i>`).join('')}
  </button>`).join('')
const pickThemeButton = segmented(swatches, b => setTheme(THEMES.find(t => t.id === b.dataset.theme)!))
function setTheme(t: Theme) {
  state.theme = t
  themeName.textContent = t.name
  for (const s of [appScreen, padScreen, smoothSaver, smoothLock, smoothDesk]) s.setTheme(t)
  $$('.theme-card').forEach(c => c.setAttribute('aria-pressed', String(c.dataset.theme === t.id)))
}

// Clock
const clockShow = $<HTMLInputElement>('#clock-show'), clockDate = $<HTMLInputElement>('#clock-date')
const clockChanged = () => {
  state.clock = { ...state.clock, show: clockShow.checked, date: clockDate.checked }
  clockDate.disabled = !clockShow.checked
  appScreen.setClock(state.clock)
}
clockShow.addEventListener('change', clockChanged)
clockDate.addEventListener('change', clockChanged)
segmented($('#hour-seg'), b => { state.clock = { ...state.clock, hour: b.dataset.hour as ClockOptions['hour'] }; appScreen.setClock(state.clock) })
segmented($('#size-seg'), b => { state.clock = { ...state.clock, large: b.dataset.size === 'large' }; appScreen.setClock(state.clock) })
segmented($('#pause-seg'), b => appScreen.setPause(Number(b.dataset.pause)))

// ---------------------------------------------------------------- III. themes

const themesEl = $('#themes')
themesEl.innerHTML = THEMES.map(t => `
  <button class="theme-card" type="button" data-theme="${t.id}" aria-pressed="${t.id === state.theme.id}" aria-label="Use ${t.name}">
    <span class="screen-host" aria-hidden="true"></span>
    <span class="theme-card-name"><span>${t.name}</span><i>${swatchColors(t).map(c => `<b style="background:#${c}"></b>`).join('')}</i></span>
  </button>`).join('')
const HOVER_FX = ['highlight', 'colorshift', 'sweep', 'beams', 'decrypt', 'synthgrid', 'rain', 'bubbles', 'fireworks']
$$('.theme-card', themesEl).forEach((card, i) => {
  const theme = THEMES[i]
  const screen = new Screen($('.screen-host', card), {
    logo: defaultLogo(), theme, clock: { show: false, date: false, hour: 'auto', large: false },
    playlist: [HOVER_FX[i % HOVER_FX.length]], autoplay: false, pauseMs: 400,
  })
  card.addEventListener('pointerenter', () => screen.hover(true))
  card.addEventListener('pointerleave', () => screen.hover(false))
  card.addEventListener('focus', () => screen.hover(true))
  card.addEventListener('blur', () => screen.hover(false))
  card.addEventListener('click', () => {
    pickThemeButton($(`[data-theme="${theme.id}"]`, swatches) as HTMLButtonElement)
  })
})

// ---------------------------------------------------------------- III. logo pad

const COLS = 44, ROWS = 44
const padGrid = $('#pad-grid')
padGrid.style.setProperty('--cols', String(COLS))
padGrid.innerHTML = '<i></i>'.repeat(COLS * ROWS)
const cells = $$('i', padGrid)
let px = blocksToPixels(stormLogo(), COLS, ROWS)
const padNow = $('#pad-now')
const padSize = $('#pad-size')
const padScreen = new Screen($('#pad-screen'), {
  logo: pixelsToBlocks(px),
  theme: state.theme,
  clock: { show: false, date: false, hour: 'auto', large: false },
  playlist: EFFECTS.map(e => e.id),
  pauseMs: 1800,
  onEffect: id => { padNow.textContent = `PREVIEW · ${effectTitle(id).toUpperCase()}` },
})

function paintPad() {
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) cells[r * COLS + c].classList.toggle('on', px[r][c])
  const art = pixelsToBlocks(px)
  const lines = art.trim() ? art.replace(/\n$/, '').split('\n').length : 0
  padSize.textContent = `${lines} LINES × ${COLS} COLUMNS`
}
let padTimer = 0
function padChanged() {
  paintPad()
  clearTimeout(padTimer)
  padTimer = window.setTimeout(() => {
    const art = pixelsToBlocks(px)
    if (art.trim()) padScreen.setLogo(art)
  }, 450)
}
paintPad()

let painting: boolean | null = null
let last: [number, number] | null = null
const cellAt = (e: PointerEvent): [number, number] | null => {
  const r = padGrid.getBoundingClientRect()
  const c = Math.floor((e.clientX - r.left) / r.width * COLS), row = Math.floor((e.clientY - r.top) / r.height * ROWS)
  return c >= 0 && c < COLS && row >= 0 && row < ROWS ? [row, c] : null
}
const set = (r: number, c: number, on: boolean) => {
  if (px[r][c] === on) return
  px[r][c] = on
  cells[r * COLS + c].classList.toggle('on', on)
}
padGrid.addEventListener('contextmenu', e => e.preventDefault())
padGrid.addEventListener('pointerdown', e => {
  const at = cellAt(e)
  if (!at) return
  padGrid.setPointerCapture(e.pointerId)
  // Start on a filled square (or right-click, or ⌥) to erase; on an empty one to draw.
  painting = !(e.button === 2 || e.altKey || px[at[0]][at[1]])
  set(at[0], at[1], painting)
  last = at
})
padGrid.addEventListener('pointermove', e => {
  if (painting === null) return
  const at = cellAt(e)
  if (!at || !last) return
  // Fill the squares between samples, so a fast stroke has no gaps.
  const steps = Math.max(Math.abs(at[0] - last[0]), Math.abs(at[1] - last[1]))
  for (let s = 1; s <= steps; s++) {
    set(Math.round(last[0] + (at[0] - last[0]) * s / steps), Math.round(last[1] + (at[1] - last[1]) * s / steps), painting)
  }
  last = at
})
const endStroke = () => { if (painting !== null) { painting = null; last = null; padChanged() } }
padGrid.addEventListener('pointerup', endStroke)
padGrid.addEventListener('pointercancel', endStroke)

// By keyboard: the arrow keys move a cursor square, Space or Enter fills or erases it.
let cursor: [number, number] | null = null
const cursorCell = () => cursor && cells[cursor[0] * COLS + cursor[1]]
const moveCursor = (r: number, c: number) => {
  cursorCell()?.classList.remove('cursor')
  cursor = [Math.max(0, Math.min(ROWS - 1, r)), Math.max(0, Math.min(COLS - 1, c))]
  cursorCell()!.classList.add('cursor')
  announce(`Row ${cursor[0] + 1}, column ${cursor[1] + 1}, ${px[cursor[0]][cursor[1]] ? 'filled' : 'empty'}`)
}
const ARROWS: Record<string, [number, number]> = { ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1] }
padGrid.tabIndex = 0
padGrid.addEventListener('keydown', e => {
  const [r, c] = cursor ?? [ROWS >> 1, COLS >> 1]
  const step = ARROWS[e.key]
  if (step) {
    e.preventDefault()
    moveCursor(cursor ? r + step[0] : r, cursor ? c + step[1] : c)   // the first press only shows where it is
  } else if (e.key === ' ' || e.key === 'Enter') {
    e.preventDefault()
    set(r, c, !px[r][c])
    moveCursor(r, c)
    padChanged()
  }
})
padGrid.addEventListener('blur', () => cursorCell()?.classList.remove('cursor'))

$('#pad-clear').addEventListener('click', () => { px = px.map(row => row.map(() => false)); paintPad() })
$('#pad-reset').addEventListener('click', () => { px = blocksToPixels(stormLogo(), COLS, ROWS); padChanged() })
$('#pad-invert').addEventListener('click', () => { px = px.map(row => row.map(v => !v)); padChanged() })
$('#pad-play').addEventListener('click', () => {
  const art = pixelsToBlocks(px)
  if (!art.trim()) return
  padScreen.setLogo(art)
  padScreen.restart()
})
$('#pad-use').addEventListener('click', () => {
  const art = pixelsToBlocks(px)
  if (!art.trim()) return
  state.customArt = art
  customText.value = ''
  pickLogo($('[data-logo="custom"]') as HTMLButtonElement)
  $('#app').scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth', block: 'center' })
})

// ---------------------------------------------------------------- IV. modes

// Smooth Mode: one look on the screensaver, the lock screen and the desktop.
const noClock: ClockOptions = { show: false, date: false, hour: 'auto', large: false }
const withClock: ClockOptions = { show: true, date: true, hour: 'auto', large: false }
const smoothSaver = new Screen($('#smooth-saver'), {
  logo: defaultLogo(), theme: state.theme, clock: withClock, pauseMs: 1500,
  playlist: ['thunderstorm', 'rain', 'matrix', 'beams', 'decrypt', 'fireworks'],
})
const smoothLock = new Screen($('#smooth-lock'), { logo: defaultLogo(), theme: state.theme, clock: withClock, autoplay: false })
const smoothDesk = new Screen($('#smooth-desk'), { logo: defaultLogo(), theme: state.theme, clock: noClock, autoplay: false })
// The desktop starts with the logo where the lock screen had it, under the clock.
new ResizeObserver(() => {
  $('#smooth-desk').style.setProperty('--glide', `${smoothLock.clockOffset}px`)
}).observe($('#smooth-lock'))

// The wallpaper pauses itself whenever a window covers the desktop.
const wall = $('#wall')
const wallScreen = new Screen($('#wall-screen'), {
  logo: defaultLogo(), theme: THEMES[7], clock: noClock, pauseMs: 1200,
  playlist: ['rain', 'thunderstorm', 'bubbles', 'matrix', 'waves', 'smoke'],
})
let wallTimer = 0
new IntersectionObserver(([e]) => {
  clearInterval(wallTimer)
  // Every visit starts uncovered and playing, however the last one was left.
  wall.classList.remove('covered')
  wallScreen.pause(false)
  if (!e.isIntersecting || reducedMotion) return
  let covered = false
  wallTimer = window.setInterval(() => {
    covered = !covered
    wall.classList.toggle('covered', covered)
    wallScreen.pause(covered)
  }, 3200)
}).observe(wall)

// ---------------------------------------------------------------- V. live stats

const statEls = { frames: $('[data-stat="frames"]'), effects: $('[data-stat="effects"]'), cost: $('[data-stat="cost"]') }
let statTimer = 0
new IntersectionObserver(([e]) => {
  clearInterval(statTimer)
  if (!e.isIntersecting) return
  const update = () => {
    statEls.frames.textContent = stats.frames.toLocaleString('en-GB')
    statEls.effects.textContent = stats.effects.toLocaleString('en-GB')
    statEls.cost.textContent = stats.frames ? (stats.engineMs / stats.frames).toFixed(3) : '–'
  }
  update()
  statTimer = window.setInterval(update, 400)
}).observe($('.pipe'))

// ---------------------------------------------------------------- download

$$<HTMLButtonElement>('[data-copy]').forEach(b => b.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText($(b.dataset.copy!).textContent ?? '')
    b.textContent = 'COPIED'
  } catch { b.textContent = 'SELECT IT' }
  setTimeout(() => { b.textContent = 'COPY' }, 1600)
}))

interface Release { tag: string; dmg?: string; stars?: number }
async function release(): Promise<Release | null> {
  try {
    const cached = sessionStorage.getItem('applarchy-release')
    if (cached) return JSON.parse(cached)
  } catch { /* storage blocked */ }
  try {
    const base = 'https://api.github.com/repos/CaptainCompileon/applarchy'
    const [rel, repo] = await Promise.all([fetch(`${base}/releases/latest`), fetch(base)])
    if (!rel.ok) return null
    const r = await rel.json()
    const info: Release = {
      tag: r.tag_name,
      dmg: r.assets?.find((a: { name: string }) => a.name.endsWith('.dmg'))?.browser_download_url,
      stars: repo.ok ? (await repo.json()).stargazers_count : undefined,
    }
    try { sessionStorage.setItem('applarchy-release', JSON.stringify(info)) } catch { /* fine */ }
    return info
  } catch { return null }
}
const showRelease = () => release().then(r => {
  if (!r) return
  $$('[data-version-line]').forEach(el => { el.textContent = `${r.tag} · Free · macOS 13 or later` })
  if (r.dmg) $$<HTMLAnchorElement>('a[data-download][href^="https"]').forEach(a => { a.href = r.dmg! })
  if (r.stars) $$('[data-stars]').forEach(el => { el.textContent = r.stars! >= 1000 ? (r.stars! / 1000).toFixed(1) + 'k' : String(r.stars) })
})
if ('requestIdleCallback' in window) requestIdleCallback(showRelease, { timeout: 3000 })
else setTimeout(showRelease, 1500)
