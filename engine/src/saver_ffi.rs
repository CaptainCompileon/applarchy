//! C interface for the macOS screensaver: build a random effect over some text
//! on a fixed canvas, then pull frames (ANSI rows, top first) one at a time.

use std::ffi::{c_char, CStr};

use clap::{CommandFactory, Parser};

use crate::cli::Cli;
use crate::engine::ctx::Clock;
use crate::fx::run::{step, Effect};
use crate::fx::Engine;
use crate::utils::rng::Rng;

pub struct Saver {
    effect: Box<dyn Effect>,
    engine: Engine,
    frame: Vec<u8>,
    name: Vec<u8>,
}

fn effect_names() -> Vec<String> {
    Cli::command()
        .get_subcommands()
        .map(|c| c.get_name().to_string())
        .filter(|n| n != "help")
        .collect()
}

/// `command` is an effect name, optionally followed by that effect's options
/// ("thunderstorm --storm-time 600").
fn build(text: &str, width: i32, height: i32, command: &str, rng: Rng) -> Option<Saver> {
    let (w, h) = (width.to_string(), height.to_string());
    let mut args: Vec<&str> = vec![
        "ttfx", "--canvas-width", &w, "--canvas-height", &h,
        "--anchor-canvas", "c", "--anchor-text", "c",
        "--ignore-terminal-dimensions", "--frame-rate", "120",
    ];
    args.extend(command.split_whitespace());
    let name = *args.get(12)?;
    let cli = Cli::try_parse_from(args).ok()?;
    let config = cli.terminal_config();
    let mut effect = crate::fx::effects::build(cli.effect.as_ref()?)?;
    let clock = Clock::virtual_with_frame_rate(config.frame_rate);
    let mut engine = Engine::new(text, config, rng, clock).ok()?;
    effect.build(&mut engine).ok()?;
    Some(Saver { effect, engine, frame: Vec::new(), name: name.as_bytes().to_vec() })
}

/// A random effect over `text` on a `width` x `height` canvas; null on failure.
#[no_mangle]
pub extern "C" fn ttfx_saver_new(text: *const c_char, width: i32, height: i32, seed: u64) -> *mut Saver {
    if text.is_null() || width < 1 || height < 1 {
        return std::ptr::null_mut();
    }
    let Ok(text) = unsafe { CStr::from_ptr(text) }.to_str() else {
        return std::ptr::null_mut();
    };
    let mut rng = Rng::seeded(seed);
    let mut names = effect_names();
    while !names.is_empty() {
        let name = names.swap_remove(rng.choice_index(names.len()));
        if let Some(saver) = build(text, width, height, &name, Rng::seeded(seed ^ 0x9e37_79b9_7f4a_7c15)) {
            return Box::into_raw(Box::new(saver));
        }
    }
    std::ptr::null_mut()
}

/// A named effect, optionally with options ("thunderstorm --storm-time 600"); null if it can't be built.
#[no_mangle]
pub extern "C" fn ttfx_saver_new_named(text: *const c_char, width: i32, height: i32, seed: u64, name: *const c_char) -> *mut Saver {
    if text.is_null() || name.is_null() {
        return std::ptr::null_mut();
    }
    let (Ok(text), Ok(name)) = (unsafe { CStr::from_ptr(text) }.to_str(), unsafe { CStr::from_ptr(name) }.to_str()) else {
        return std::ptr::null_mut();
    };
    match build(text, width, height, name, Rng::seeded(seed)) {
        Some(saver) => Box::into_raw(Box::new(saver)),
        None => std::ptr::null_mut(),
    }
}

/// Advance one frame. Returns the frame's bytes (valid until the next call) or
/// null when the effect has finished.
#[no_mangle]
pub extern "C" fn ttfx_saver_next(saver: *mut Saver, len: *mut usize) -> *const u8 {
    let Some(s) = (unsafe { saver.as_mut() }) else { return std::ptr::null() };
    if !step(s.effect.as_mut(), &mut s.engine) {
        return std::ptr::null();
    }
    let mut parts = Vec::new();
    s.engine.renderer().frame_parts(&[], &[], &mut parts);
    s.frame.clear();
    for p in &parts {
        s.frame.extend_from_slice(p);
    }
    if !len.is_null() {
        unsafe { *len = s.frame.len() };
    }
    s.frame.as_ptr()
}

/// The effect's name (not NUL-terminated); length in `len`.
#[no_mangle]
pub extern "C" fn ttfx_saver_effect_name(saver: *const Saver, len: *mut usize) -> *const u8 {
    let Some(s) = (unsafe { saver.as_ref() }) else { return std::ptr::null() };
    if !len.is_null() {
        unsafe { *len = s.name.len() };
    }
    s.name.as_ptr()
}

#[no_mangle]
pub extern "C" fn ttfx_saver_free(saver: *mut Saver) {
    if !saver.is_null() {
        drop(unsafe { Box::from_raw(saver) });
    }
}
