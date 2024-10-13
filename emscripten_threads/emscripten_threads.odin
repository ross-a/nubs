/* [[file:../nubs.org::*Emscripten Threads][Emscripten Threads:2]] */
package emscripten_threads


PTHREAD_CREATE_DETACHED :: 1

Thread_State :: enum u8 {
	Started,
	Joined,
	Done,
	Self_Cleanup,
}

Thread :: struct {
  t_size: int,    // pthread_t size
  m_size: int,    // pthread_mutex_t size
  c_size: int,    // pthread_cond_t size
	flags: bit_set[Thread_State; u8],  
  data: rawptr,
  d: [300]u8,
  thread: rawptr, // 32bits or 64 bits?
  mutex: rawptr,
  cond: rawptr,
}

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
  @(default_calling_convention="c")
  foreign {
    wrap_size_pthread_t :: proc() -> int ---
    wrap_size_pthread_mutex_t :: proc() -> int ---
    wrap_size_pthread_cond_t :: proc() -> int ---
    
    wrap_pthread_create :: proc(t: rawptr, tattr: rawptr,
                                start_routine: proc "c" (rawptr) -> rawptr, arg: rawptr) -> int ---
    wrap_pthread_detach :: proc(t: i32/*pthread_t*/) -> int ---
    wrap_pthread_join :: proc(t: i32/*pthread_t*/, status: ^rawptr) -> int ---
    wrap_pthread_mutex_lock :: proc(m: rawptr) -> int ---
    wrap_pthread_mutex_unlock :: proc(m: rawptr) -> int ---
    wrap_pthread_cond_wait :: proc(cond: rawptr, m: rawptr) -> int ---
    wrap_pthread_cond_signal :: proc(cond: rawptr) -> int ---
    
    wrap_emscripten_console_log :: proc(str: cstring) ---
  }
} else {
  wrap_size_pthread_t :: proc() -> int { return 0 }
  wrap_size_pthread_mutex_t :: proc() -> int { return 0 }
  wrap_size_pthread_cond_t :: proc() -> int { return 0 }
  
  wrap_pthread_create :: proc(t: rawptr, tattr: rawptr,
                              start_routine: proc "c" (rawptr) -> rawptr, arg: rawptr) -> int { return 0 }
  wrap_pthread_detach :: proc(t: i32/*pthread_t*/) -> int { return 0 }
  wrap_pthread_join :: proc(t: i32/*pthread_t*/, status: ^rawptr) -> int { return 0 }
  wrap_pthread_mutex_lock :: proc(m: rawptr) -> int { return 0 }
  wrap_pthread_mutex_unlock :: proc(m: rawptr) -> int { return 0 }
  wrap_pthread_cond_wait :: proc(cond: rawptr, m: rawptr) -> int { return 0 }
  wrap_pthread_cond_signal :: proc(cond: rawptr) -> int { return 0 }
  
  wrap_emscripten_console_log :: proc(str: cstring) {}
}
/* Emscripten Threads:2 ends here */
