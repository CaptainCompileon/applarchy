//! Every effect through the C API on small and odd canvases (the app's preview, narrow
//! screens, a one-line logo): it may refuse to build, but must never panic.

use std::ffi::CString;
use std::panic::{catch_unwind, AssertUnwindSafe};
use ttfx::saver_ffi::*;

const EFFECTS: &[&str] = &[
    "beams", "binarypath", "blackhole", "bouncyballs", "bubbles", "burn", "colorshift",
    "crumble", "decrypt", "errorcorrect", "expand", "fireworks", "highlight", "laseretch",
    "matrix", "middleout", "orbittingvolley", "overflow", "pour", "print", "rain",
    "randomsequence", "rings", "scattered", "slice", "slide", "smoke", "spotlights", "spray",
    "swarm", "sweep", "synthgrid", "thunderstorm", "unstable", "vhstape", "waves", "wipe",
];

#[test]
fn no_effect_panics_on_small_or_odd_canvases() {
    let logos = ["▄█▀\n█▀▄", "x", ""];
    let sizes = [(0, 0), (0, 10), (10, 0), (1, 1), (2, 1), (1, 3), (3, 2), (8, 4), (20, 3), (144, 2), (2, 46), (216, 46)];
    let mut panics = Vec::new();
    for logo in logos {
        let text = CString::new(logo).unwrap();
        for &(w, h) in &sizes {
            for name in EFFECTS {
                let cname = CString::new(*name).unwrap();
                let run = catch_unwind(AssertUnwindSafe(|| {
                    let s = ttfx_saver_new_named(text.as_ptr(), w, h, 7, cname.as_ptr());
                    let mut len = 0usize;
                    let mut n = 0;
                    while !s.is_null() && n < 20_000 && !ttfx_saver_next(s, &mut len).is_null() { n += 1; }
                    ttfx_saver_free(s);
                }));
                if run.is_err() { panics.push(format!("{name} {w}x{h} logo {logo:?}")); }
            }
        }
    }
    assert!(panics.is_empty(), "{} panics:\n{}", panics.len(), panics.join("\n"));
}
