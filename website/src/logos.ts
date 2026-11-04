// Logos as half-block text art (▀ ▄ █), the way saver/LogoArt.swift makes them.
import { STORM_LOGO } from './data'

/** Crop to the ink and resample into half-blocks, 2 pixels per text cell, `cols`
 *  wide; 3×3 supersampling with a majority vote per pixel (LogoArt.halfBlocks). */
export function halfBlocks(w: number, h: number, cols: number, ink: (x: number, y: number) => boolean): string | null {
  let minX = w, maxX = 0, minY = h, maxY = 0
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (ink(x, y)) {
    if (x < minX) minX = x; if (x > maxX) maxX = x
    if (y < minY) minY = y; if (y > maxY) maxY = y
  }
  if (minX >= maxX || minY >= maxY) return null
  const bw = maxX - minX + 1, bh = maxY - minY + 1
  const rowsPx = Math.round(cols * bh / bw)
  const on = (c: number, r: number) => {
    if (r >= rowsPx) return false
    let hits = 0
    for (let dy = 0; dy < 3; dy++) for (let dx = 0; dx < 3; dx++) {
      const x = minX + Math.floor((c + (dx + 0.5) / 3) * bw / cols)
      const y = minY + Math.floor((r + (dy + 0.5) / 3) * bh / rowsPx)
      if (ink(Math.min(x, maxX), Math.min(y, maxY))) hits++
    }
    return hits >= 5
  }
  const lines: string[] = []
  for (let r = 0; r < rowsPx; r += 2) {
    let line = ''
    for (let c = 0; c < cols; c++) {
      const top = on(c, r), bottom = on(c, r + 1)
      line += top && bottom ? '█' : top ? '▀' : bottom ? '▄' : ' '
    }
    lines.push(line.trimEnd())
  }
  return lines.join('\n') + '\n'
}

/** Draw `text` big into a square canvas and read back its ink. */
function inkOf(text: string, font: string, n = 600): { data: Uint8ClampedArray; n: number } {
  const c = document.createElement('canvas')
  c.width = c.height = n
  const ctx = c.getContext('2d', { willReadFrequently: true })!
  ctx.fillStyle = '#000'
  ctx.fillRect(0, 0, n, n)
  ctx.fillStyle = '#fff'
  ctx.font = font
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillText(text, n / 2, n / 2)
  return { data: ctx.getImageData(0, 0, n, n).data, n }
}

const appleFont = '380px -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif'

/** "Chill Guy": the Apple logo, drawn like the app does from the system font's
 *  U+F8FF. Only Apple's fonts have it there (it's a private-use code point), so on
 *  other systems this is null and the page uses the storm cloud instead. */
export function appleLogo(cols = 44): string | null {
  const apple = inkOf('', appleFont)
  const other = inkOf('', appleFont)   // another private-use point: tofu, or nothing
  let differs = false, inked = 0
  for (let i = 0; i < apple.data.length; i += 4) {
    if (apple.data[i] > 127) inked++
    if (!differs && apple.data[i] !== other.data[i]) differs = true
  }
  if (!differs || inked < 2000) return null
  return halfBlocks(apple.n, apple.n, cols, (x, y) => apple.data[(y * apple.n + x) * 4] > 127)
}

export const stormLogo = () => STORM_LOGO

/** Your own text, set in Departure Mono on its own pixel grid (11 px to the em), so
 *  every font pixel becomes exactly one logo pixel, or a 2×2 block for short words. */
export function textLogo(text: string, maxCols = 72): string | null {
  const t = text.trim().toUpperCase().slice(0, 14)
  if (!t) return null
  const advance = 7                                   // px per character at 11 px
  const k = Math.max(1, Math.min(3, Math.floor(maxCols / (t.length * advance))))
  const w = t.length * advance + 2, h = 14
  const c = document.createElement('canvas')
  c.width = w
  c.height = h
  const ctx = c.getContext('2d', { willReadFrequently: true })!
  ctx.fillStyle = '#fff'
  ctx.font = '11px "Departure Mono", monospace'
  ctx.textBaseline = 'top'
  ctx.fillText(t, 1, 1)
  const d = ctx.getImageData(0, 0, w, h).data
  const px: boolean[][] = []
  for (let y = 0; y < h; y++) {
    const row = Array.from({ length: w }, (_, x) => d[(y * w + x) * 4 + 3] > 127)
    for (let i = 0; i < k; i++) px.push(row.flatMap(v => Array<boolean>(k).fill(v)))
  }
  const art = pixelsToBlocks(px)
  return art.trim() ? art.replace(/^\n+/, '') : null
}

/** Half-block art from a grid of pixels (the drawing pad): rows of booleans. */
export function pixelsToBlocks(px: boolean[][]): string {
  const lines: string[] = []
  for (let r = 0; r < px.length; r += 2) {
    let line = ''
    for (let c = 0; c < px[r].length; c++) {
      const top = px[r][c], bottom = px[r + 1]?.[c] ?? false
      line += top && bottom ? '█' : top ? '▀' : bottom ? '▄' : ' '
    }
    lines.push(line.trimEnd())
  }
  while (lines.length && !lines[lines.length - 1]) lines.pop()
  while (lines.length && !lines[0]) lines.shift()
  const indent = Math.min(...lines.filter(Boolean).map(l => l.length - l.trimStart().length))
  return lines.map(l => l.slice(indent)).join('\n') + '\n'
}

/** And back: the pixels of half-block art, `cols` × `rows` (rows even). */
export function blocksToPixels(art: string, cols: number, rows: number): boolean[][] {
  const px = Array.from({ length: rows }, () => Array<boolean>(cols).fill(false))
  const lines = art.replace(/\n$/, '').split('\n')
  const w = Math.max(...lines.map(l => [...l].length))
  const ox = Math.max(0, Math.floor((cols - w) / 2)), oy = Math.max(0, Math.floor((rows - lines.length * 2) / 2 / 2) * 2)
  lines.forEach((line, i) => [...line].forEach((ch, c) => {
    const x = ox + c, y = oy + i * 2
    if (x >= cols || y + 1 >= rows) return
    if (ch === '█' || ch === '▀') px[y][x] = true
    if (ch === '█' || ch === '▄') px[y + 1][x] = true
  }))
  return px
}

let cached: string | undefined
/** The default logo: Chill Guy where the system font has it, else the storm cloud. */
export function defaultLogo(): string {
  return (cached ??= appleLogo() ?? STORM_LOGO)
}
export const hasAppleLogo = () => defaultLogo() !== STORM_LOGO
