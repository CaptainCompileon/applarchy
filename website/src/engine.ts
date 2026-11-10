// The ttfx engine (../engine, the same Rust code the app embeds), compiled to
// WebAssembly by scripts/build-wasm.sh. It exposes the screensaver's C API
// (engine/src/saver_ffi.rs): build an effect over some text on a fixed canvas,
// then pull ANSI frames one at a time, at the engine's 120 fps pace.
import wasmUrl from './ttfx.wasm?url'

interface Exports {
  memory: WebAssembly.Memory
  web_alloc(len: number): number
  web_free(ptr: number, len: number): void
  ttfx_saver_new_named(text: number, width: number, height: number, seed: bigint, name: number): number
  ttfx_saver_next(saver: number, len: number): number
  ttfx_saver_free(saver: number): void
}

let loading: Promise<Engine> | null = null
let failedAt = -Infinity
const RETRY_AFTER_MS = 5000
const failureListeners: (() => void)[] = []

/** `listener` runs each time the engine fails to load: no WebAssembly here (Lockdown
 *  Mode, an old browser), or its file didn't arrive. */
export const onEngineFailure = (listener: () => void) => { failureListeners.push(listener) }

/** The engine, loaded once and shared by every screen on the page. A failed load isn't
 *  kept: asking again a while later tries again (the connection may be back). */
export function loadEngine(): Promise<Engine> {
  if (!loading && performance.now() - failedAt < RETRY_AFTER_MS) return Promise.reject(new Error('the engine failed to load a moment ago'))
  return (loading ??= instantiate().then(e => new Engine(e)).catch(error => {
    loading = null
    failedAt = performance.now()
    failureListeners.forEach(listener => listener())
    throw error
  }))
}

async function instantiate(): Promise<Exports> {
  if (typeof WebAssembly !== 'object') throw new Error('WebAssembly is not available')
  let memory: WebAssembly.Memory | undefined
  const view = () => new DataView(memory!.buffer)
  // The few WASI calls Rust's std makes here: the clock for Instant, randomness for
  // HashMap seeds, and stderr for panic messages. Effects use a virtual clock.
  const wasi = {
    clock_time_get: (_id: number, _precision: bigint, out: number) => {
      view().setBigUint64(out, BigInt(Math.round(performance.now() * 1e6)), true)
      return 0
    },
    random_get: (ptr: number, len: number) => {
      crypto.getRandomValues(new Uint8Array(memory!.buffer, ptr, len))
      return 0
    },
    environ_sizes_get: (count: number, size: number) => {
      view().setUint32(count, 0, true)
      view().setUint32(size, 0, true)
      return 0
    },
    environ_get: () => 0,
    fd_write: (_fd: number, iovs: number, n: number, written: number) => {
      const v = view()
      let total = 0
      for (let i = 0; i < n; i++) total += v.getUint32(iovs + i * 8 + 4, true)
      v.setUint32(written, total, true)
      return 0
    },
    poll_oneoff: () => 52, // ENOSYS
    proc_exit: (code: number) => { throw new Error(`ttfx exited (${code})`) },
  }
  const imports = { wasi_snapshot_preview1: wasi }
  const response = fetch(wasmUrl)
  const { instance } = await WebAssembly.instantiateStreaming(response, imports)
    .catch(async () => WebAssembly.instantiate(await (await fetch(wasmUrl)).arrayBuffer(), imports))
  const exports = instance.exports as unknown as Exports
  memory = exports.memory
  return exports
}

const encoder = new TextEncoder()

export class Engine {
  private lenPtr: number
  constructor(readonly x: Exports) {
    this.lenPtr = x.web_alloc(4)
  }

  private cString(s: string): [number, number] {
    const bytes = encoder.encode(s + '\0')
    const ptr = this.x.web_alloc(bytes.length)
    new Uint8Array(this.x.memory.buffer, ptr, bytes.length).set(bytes)
    return [ptr, bytes.length]
  }

  /** An effect over `text`, `command` being "name [options]" as the app passes it. Null if
   *  it can't be built, or building it trapped: in WebAssembly a panic aborts (wasm/Cargo.toml),
   *  so the engine's own guard (saver_ffi.rs) can't catch it and it's caught here instead. */
  effect(text: string, cols: number, rows: number, command: string, seed = randomSeed()): Effect | null {
    try {
      const [t, tl] = this.cString(text)
      const [c, cl] = this.cString(command)
      const ptr = this.x.ttfx_saver_new_named(t, cols, rows, seed, c)
      this.x.web_free(t, tl)
      this.x.web_free(c, cl)
      return ptr ? new Effect(this, ptr) : null
    } catch {
      return null
    }
  }

  /** Advance `saver` one frame: where its ANSI bytes are, or 0 when it's over. */
  next(saver: number): number {
    return this.x.ttfx_saver_next(saver, this.lenPtr)
  }

  /** The bytes of the frame `next` just returned, viewed afresh: memory may have grown since. */
  bytes(ptr: number): Uint8Array {
    const len = new Uint32Array(this.x.memory.buffer, this.lenPtr, 1)[0]
    return new Uint8Array(this.x.memory.buffer, ptr, len)
  }
}

export class Effect {
  frames = 0
  done = false
  /** A step trapped: the effect is over (`done`) and what it drew can't be trusted. */
  failed = false
  constructor(private engine: Engine, private ptr: number) {}

  /** Step up to `n` frames; the last one's bytes, or null if none (the effect ended, or failed). */
  advance(n: number): Uint8Array | null {
    let last = 0
    try {
      for (let i = 0; i < n && !this.done; i++) {
        const p = this.engine.next(this.ptr)
        if (p) { last = p; this.frames++ } else this.done = true
      }
    } catch {
      // Left as it is, not freed: its state is whatever the trap left behind.
      this.failed = this.done = true
      this.ptr = 0
      return null
    }
    return last ? this.engine.bytes(last) : null
  }

  free() {
    try { if (this.ptr) this.engine.x.ttfx_saver_free(this.ptr) } catch { /* trapped: nothing more to do */ }
    this.ptr = 0
    this.done = true
  }
}

export const randomSeed = () => BigInt(Math.floor(Math.random() * 2 ** 52))
