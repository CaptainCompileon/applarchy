//! The ttfx engine for the website: the screensaver's C API (engine/src/saver_ffi.rs),
//! re-exported for wasm32, plus the two calls JavaScript needs to hand it strings.

pub use ttfx::saver_ffi::*;

/// `len` bytes of wasm memory for the caller to fill, e.g. a NUL-terminated string.
#[no_mangle]
pub extern "C" fn web_alloc(len: usize) -> *mut u8 {
    let mut buf = Vec::<u8>::with_capacity(len);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

#[no_mangle]
pub extern "C" fn web_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(unsafe { Vec::from_raw_parts(ptr, 0, len) });
    }
}
