use std::sync::Mutex;

static DB: Mutex<Option<notation::database_store::Store>> =
    Mutex::new(None);

#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut v = Vec::<u8>::with_capacity(len);
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

#[no_mangle]
pub unsafe extern "C" fn free_buf(ptr: *mut u8, len: usize) {
    drop(Vec::from_raw_parts(ptr, 0, len));
}

#[no_mangle]
pub unsafe extern "C" fn load_index(ptr: *const u8, len: usize) -> i32 {
    let bytes = std::slice::from_raw_parts(ptr, len);
    let text = match std::str::from_utf8(bytes) {
        Ok(t) => t,
        Err(_) => return -1,
    };
    match notation::database_file_format::decode(text) {
        Ok(store) => {
            let n = store.of_kind("block").len() as i32;
            *DB.lock().unwrap_or_else(|e| e.into_inner()) = Some(store);
            n
        }
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn block_count() -> i32 {
    match DB.lock().unwrap_or_else(|e| e.into_inner()).as_ref() {
        Some(s) => s.of_kind("block").len() as i32,
        None => -1,
    }
}
