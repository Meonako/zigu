use std::mem::ManuallyDrop;
use std::alloc;

#[repr(C)]
pub struct FFISlice {
    ptr: *const u8,
    len: usize,
}

#[no_mangle]
pub extern "C" fn arch_os() -> FFISlice {
    let s = ManuallyDrop::new(format!("{}-{}", std::env::consts::ARCH, std::env::consts::OS));
    FFISlice {
        ptr: s.as_ptr(),
        len: s.len(),
    }
}

#[no_mangle]
pub extern "C" fn free_string(ptr: *const u8, len: usize) {
    unsafe {
        alloc::dealloc(ptr as *mut u8, alloc::Layout::from_size_align_unchecked(len, 1));
    }
}