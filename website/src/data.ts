// Ported from the app: saver/Themes.swift, studio/Catalog.swift, saver/PixelClock.swift.

export interface Theme {
  id: string
  name: string
  background: string   // "rrggbb"
  foreground: string   // clock and date
  stops: string[]      // final gradient, darkest → brightest; empty = ttfx defaults
  accents: string[]    // effect colours (beams, rain, fireworks, …)
}

export const THEMES: Theme[] = [
  { id: 'omarchy', name: 'Omarchy', background: '000000', foreground: 'f0f0f0', stops: [], accents: [] },
  { id: 'tokyo-night', name: 'Tokyo Night', background: '1a1b26', foreground: 'c0caf5',
    stops: ['7aa2f7', 'bb9af7', '7dcfff'], accents: ['f7768e', 'e0af68', '9ece6a', '7dcfff'] },
  { id: 'catppuccin', name: 'Catppuccin', background: '1e1e2e', foreground: 'cdd6f4',
    stops: ['cba6f7', 'f5c2e7', '89dceb'], accents: ['f38ba8', 'fab387', 'a6e3a1', '89b4fa'] },
  { id: 'gruvbox', name: 'Gruvbox', background: '282828', foreground: 'ebdbb2',
    stops: ['cc241d', 'd79921', 'b8bb26'], accents: ['fb4934', 'fe8019', 'fabd2f', '8ec07c'] },
  { id: 'nord', name: 'Nord', background: '2e3440', foreground: 'eceff4',
    stops: ['5e81ac', '81a1c1', '88c0d0'], accents: ['bf616a', 'ebcb8b', 'a3be8c', '8fbcbb'] },
  { id: 'everforest', name: 'Everforest', background: '2d353b', foreground: 'd3c6aa',
    stops: ['83c092', 'a7c080', 'dbbc7f'], accents: ['e67e80', 'e69875', 'dbbc7f', '7fbbb3'] },
  { id: 'kanagawa', name: 'Kanagawa', background: '1f1f28', foreground: 'dcd7ba',
    stops: ['957fb8', '7e9cd8', 'e6c384'], accents: ['c34043', 'ffa066', '98bb6c', '7fb4ca'] },
  { id: 'rose-pine', name: 'Rosé Pine', background: '191724', foreground: 'e0def4',
    stops: ['eb6f92', 'c4a7e7', 'f6c177'], accents: ['eb6f92', 'ebbcba', '31748f', '9ccfd8'] },
  { id: 'matte-black', name: 'Matte Black', background: '121212', foreground: 'bebebe',
    stops: ['5c5c5c', 'bebebe', 'f0a500'], accents: ['8a8a8d', 'bebebe', 'f0a500', 'ffffff'] },
]

/** The ttfx command for `effect` in `theme`, as Theme.command(for:) builds it. */
export function themedCommand(effect: string, theme: Theme): string {
  if (!theme.stops.length) return effect
  const parts = [effect, effect === 'synthgrid' ? '--text-gradient-stops' : '--final-gradient-stops', ...theme.stops]
  const a = theme.accents.join(' ')
  const extra: Record<string, string[]> = {
    beams: ['--beam-gradient-stops', a],
    matrix: ['--rain-color-gradient', a],
    thunderstorm: ['--lightning-color', theme.accents[theme.accents.length - 1], '--glowing-text-color', theme.accents[0]],
    rain: ['--rain-colors', a],
    fireworks: ['--firework-colors', a],
    bubbles: ['--bubble-colors', a],
    rings: ['--ring-colors', a],
    waves: ['--wave-gradient-stops', a],
    bouncyballs: ['--ball-colors', a],
    blackhole: ['--star-colors', a],
    synthgrid: ['--grid-gradient-stops', a],
  }
  parts.push(...(extra[effect] ?? []))
  return ['--terminal-background-color', theme.background, ...parts].join(' ')
}

export interface EffectInfo { id: string; title: string; summary: string }

const TITLES: Record<string, string> = {
  binarypath: 'Binary Path', bouncyballs: 'Bouncy Balls', colorshift: 'Color Shift', errorcorrect: 'Error Correct',
  laseretch: 'Laser Etch', middleout: 'Middle Out', orbittingvolley: 'Orbiting Volley',
  randomsequence: 'Random Sequence', synthgrid: 'Synth Grid', vhstape: 'VHS Tape',
}

export const EFFECTS: EffectInfo[] = ([
  ['beams', 'Beams travel over the canvas, illuminating the characters behind them'],
  ['binarypath', 'Binary representations of each character move towards their home'],
  ['blackhole', 'Characters are consumed by a black hole and explode outwards'],
  ['bouncyballs', 'Characters are bouncy balls falling from the top of the canvas'],
  ['bubbles', 'Characters are formed into bubbles that float down and pop'],
  ['burn', 'Burns vertically in the canvas'],
  ['colorshift', 'A gradient that shifts colors across the terminal'],
  ['crumble', 'Characters lose color and crumble into dust, are vacuumed up, and reformed'],
  ['decrypt', 'A movie-style decryption effect'],
  ['errorcorrect', 'Some characters start in the wrong position and are corrected in sequence'],
  ['expand', 'Expands the text from a single point'],
  ['fireworks', 'Characters launch and explode like fireworks and fall into place'],
  ['highlight', 'A specular highlight runs across the text'],
  ['laseretch', 'A laser etches characters onto the terminal'],
  ['matrix', 'Matrix digital rain'],
  ['middleout', 'Text expands in a single row or column in the middle, then out'],
  ['orbittingvolley', 'Four launchers orbit the canvas, firing volleys of characters inward'],
  ['overflow', 'Text overflows and scrolls in a random order until it appears ordered'],
  ['pour', 'Pours the characters into position from a direction'],
  ['print', 'Lines are printed one at a time following a print head'],
  ['rain', 'Rains characters from the top of the canvas'],
  ['randomsequence', 'Prints the text in a random sequence'],
  ['rings', 'Characters are dispersed and form into spinning rings'],
  ['scattered', 'Text is scattered across the canvas and moves into position'],
  ['slice', 'Slices the text in half and slides it into place from opposite directions'],
  ['slide', 'Slides characters into view from outside the canvas'],
  ['smoke', 'Smoke floods the canvas, colorizing any characters it crosses'],
  ['spotlights', 'Spotlights search the text, converge in the center and expand'],
  ['spray', 'Draws the characters spawning at varying rates from a single point'],
  ['swarm', 'Characters are grouped into swarms that move around before settling'],
  ['sweep', 'Sweeps across the canvas to reveal the text, then sweeps back to color it'],
  ['synthgrid', 'A grid fills with characters dissolving into the final text'],
  ['thunderstorm', 'A thunderstorm, with rain and lightning striking the text'],
  ['unstable', 'Characters spawn jumbled, explode to the edges, then reassemble'],
  ['vhstape', 'Lines glitch left and right and lose detail like an old VHS tape'],
  ['waves', 'Waves travel across the canvas, leaving the characters behind'],
  ['wipe', 'Wipes the text across the canvas to reveal it'],
] as const).map(([id, summary]) => ({ id, summary, title: TITLES[id] ?? id[0].toUpperCase() + id.slice(1) }))

export const effectTitle = (id: string) => EFFECTS.find(e => e.id === id)?.title ?? id

/** Effects that stay calm (no flying, exploding or flashing characters): all that
 *  plays with Reduce Motion on, as in the app. */
export const GENTLE = new Set(['colorshift', 'expand', 'highlight', 'middleout', 'print', 'randomsequence', 'sweep', 'wipe'])

/** The 5×7 clock font, from PixelClock.swift. */
const F: Record<string, string[]> = {
  ' ': ['   ', '   ', '   ', '   ', '   ', '   ', '   '],
  ':': [' ', ' ', '#', ' ', '#', ' ', ' '],
  '.': [' ', ' ', ' ', ' ', ' ', ' ', '#'],
  ',': ['  ', '  ', '  ', '  ', '  ', ' #', '# '],
  '0': [' ### ', '#   #', '#  ##', '# # #', '##  #', '#   #', ' ### '],
  '1': ['  #  ', ' ##  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
  '2': [' ### ', '#   #', '    #', '   # ', '  #  ', ' #   ', '#####'],
  '3': ['#####', '   # ', '  #  ', '   # ', '    #', '#   #', ' ### '],
  '4': ['   # ', '  ## ', ' # # ', '#  # ', '#####', '   # ', '   # '],
  '5': ['#####', '#    ', '#### ', '    #', '    #', '#   #', ' ### '],
  '6': ['  ## ', ' #   ', '#    ', '#### ', '#   #', '#   #', ' ### '],
  '7': ['#####', '    #', '   # ', '  #  ', ' #   ', ' #   ', ' #   '],
  '8': [' ### ', '#   #', '#   #', ' ### ', '#   #', '#   #', ' ### '],
  '9': [' ### ', '#   #', '#   #', ' ####', '    #', '   # ', ' ##  '],
  A: [' ### ', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  B: ['#### ', '#   #', '#   #', '#### ', '#   #', '#   #', '#### '],
  C: [' ### ', '#   #', '#    ', '#    ', '#    ', '#   #', ' ### '],
  D: ['#### ', '#   #', '#   #', '#   #', '#   #', '#   #', '#### '],
  E: ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#####'],
  F: ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#    '],
  G: [' ### ', '#   #', '#    ', '# ###', '#   #', '#   #', ' ####'],
  H: ['#   #', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  I: [' ### ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
  J: ['  ###', '   # ', '   # ', '   # ', '   # ', '#  # ', ' ##  '],
  K: ['#   #', '#  # ', '# #  ', '##   ', '# #  ', '#  # ', '#   #'],
  L: ['#    ', '#    ', '#    ', '#    ', '#    ', '#    ', '#####'],
  M: ['#   #', '## ##', '# # #', '# # #', '#   #', '#   #', '#   #'],
  N: ['#   #', '#   #', '##  #', '# # #', '#  ##', '#   #', '#   #'],
  O: [' ### ', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  P: ['#### ', '#   #', '#   #', '#### ', '#    ', '#    ', '#    '],
  Q: [' ### ', '#   #', '#   #', '#   #', '# # #', '#  # ', ' ## #'],
  R: ['#### ', '#   #', '#   #', '#### ', '# #  ', '#  # ', '#   #'],
  S: [' ####', '#    ', '#    ', ' ### ', '    #', '    #', '#### '],
  T: ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  '],
  U: ['#   #', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  V: ['#   #', '#   #', '#   #', '#   #', '#   #', ' # # ', '  #  '],
  W: ['#   #', '#   #', '#   #', '# # #', '# # #', '# # #', ' # # '],
  X: ['#   #', '#   #', ' # # ', '  #  ', ' # # ', '#   #', '#   #'],
  Y: ['#   #', '#   #', ' # # ', '  #  ', '  #  ', '  #  ', '  #  '],
  Z: ['#####', '    #', '   # ', '  #  ', ' #   ', '#    ', '#####'],
}
export const clockGlyph = (ch: string) => F[ch] ?? F[' ']

/** The app icon's storm cloud as half-block art (from docs/icon.png, 40 columns). */
export const STORM_LOGO = `               ██████████
           ████████████████
           ██████████████████
        ▄████████████████████
        █████████████████████████▄
    ▄█████████████████████████████████
  ▄▄██████████████████████████████████
▄▄████████████████████████████████████▄▄
████████████████████████████████████████
████████████████████████████████████████
████████████████████████████████████████
████████████████████████████████████████
██████████████████████████████████████▀▀
▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀████▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
               ▄▄████▄▄▄▄
               ▀▀▀▀████▀▀
                   ████
                 ████
              ▄████
             ████
             ██
`
