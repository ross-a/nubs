/* [[file:../../nubs.org::*pairing heap][pairing heap:2]] */
package pairing_heap_test

import "core:mem"
import "core:fmt"
import "core:slice"
import "core:math/rand"
import "core:testing"
import ph "../"

import "base:runtime"
import "core:prof/spall"
import "core:sync"

import "core:container/priority_queue" // for comparison

spall_ctx: spall.Context
@(thread_local) spall_buffer: spall.Buffer

WITH_TRACKING_ALLOC :: false // will slow down pairing_heap since ph uses a bunch-o-allocs in comp with pqueue

main :: proc() {
  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    if WITH_TRACKING_ALLOC {
      mem.tracking_allocator_init(&track, context.allocator)
      context.allocator = mem.tracking_allocator(&track)
    }
    
    spall_ctx = spall.context_create("trace_test.spall")
    buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
    spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
    spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
    
    defer {
      spall.buffer_flush(&spall_ctx, &spall_buffer)

      spall.context_destroy(&spall_ctx)
      spall.buffer_destroy(&spall_ctx, &spall_buffer)
      delete(buffer_backing)

      if WITH_TRACKING_ALLOC {      
        if len(track.allocation_map) > 0 {
          fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
          for _, entry in track.allocation_map {
            fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
          }
        }
        if len(track.bad_free_array) > 0 {
          fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
          for entry in track.bad_free_array {
            fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
          }
          mem.tracking_allocator_destroy(&track)
        }
      }
    }
  }
  pairing_heap_test(nil)
  pairing_heap_test_10000(nil)
  priority_queue_test_10000(nil)
}

Vertex :: struct {
  x: f32,
  y: f32,
  key: f32,
}

less :: proc(a, b: Vertex) -> bool { return a.key < b.key }

@test
pairing_heap_test_10000 :: proc(t: ^testing.T) {
  root := new(ph.Pairing_Heap(Vertex))
  ph.init(root, less)
  ww := cast(f32)(rand.uint32() % 20)
  root.elem.x = 0; root.elem.y = 0; root.elem.key = ww

  for i in 1..<10000 {  // push 10000 random items on pairing heap
    w := cast(f32)(rand.uint32() % 20)

    node := new(ph.Pairing_Heap(Vertex)) // with tracking_alloc turned on this will swing ph to be slower than pq
    ph.init(node, less)
    node.elem.x = 0; node.elem.y = 0; node.elem.key = w

    ph.push(&root, node)

    w = cast(f32)(rand.uint32() % 20)
    ph.decrease_key(w, &root, node)
  }

  for ; root != nil; { // pop them all off
    popped := ph.pop(&root)
    free(popped)
  }
}

@test
priority_queue_test_10000 :: proc(t: ^testing.T) {
  root := new(priority_queue.Priority_Queue(Vertex)); defer free(root)
  priority_queue.init(root, less, priority_queue.default_swap_proc(Vertex))

  for i in 0..<10000 {  // push 10000 random items on priority queue
    w := cast(f32)(rand.uint32() % 20)
    v : Vertex
    v.x = 0; v.y = 0; v.key = w

    priority_queue.push(root, v)

    w = cast(f32)(rand.uint32() % 20)
    root.queue[i].key -= w
    priority_queue.fix(root, i)
  }

  for ; len(root.queue) > 0; { // pop them all off
    priority_queue.pop(root)
  }
  priority_queue.destroy(root)
}

@test
pairing_heap_test :: proc(t: ^testing.T) {
  fmt.println("pairing heap fuzz test")
  items : [dynamic]^ph.Pairing_Heap(Vertex); defer delete(items)
  root := new(ph.Pairing_Heap(Vertex))
  ph.init(root, less)
  ww := cast(f32)(rand.uint32() % 20)
  root.elem.x = 0; root.elem.y = 0; root.elem.key = ww
  append(&items, root)
  for i in 1..<10 {
    w := cast(f32)(rand.uint32() % 20)

    node := new(ph.Pairing_Heap(Vertex))
    ph.init(node, less)
    node.elem.x = 0; node.elem.y = 0; node.elem.key = w

    append(&items, node)
    ph.push(&root, node)
  }

  fmt.println("trying randomly decreasing keys")
  for _ in 0..<10 {
    w := cast(f32)(rand.uint32() % 20)
    j := rand.uint32() % 10
    node := items[j]                // pick a random node
    
    ph.decrease_key(w, &root, node) // decrease it's key by w
  }

  tmp_less :: proc(i, j: ^ph.Pairing_Heap(Vertex)) -> bool {
    if i.elem.key < j.elem.key do return true
    return false
  }
  slice.sort_by(items[:], tmp_less)

  // print heap keys after sorting.. look for negatives, to assure that decrease_key() is working
  //fmt.println()
  //for i in items {
  //  fmt.println(i.elem.key)
  //}

  // check pop'in off the top of heap will do the same sort
  for i,idx in items {
    if i.elem.key != root.elem.key {
      fmt.println("items not in order", i.elem.key, root.elem.key)
      assert(false)
    }
    popped := ph.pop(&root)
    free(popped)
  }
}

// Automatic profiling of every procedure:

@(instrumentation_enter)
spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
  spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
  spall._buffer_end(&spall_ctx, &spall_buffer)
}
/* pairing heap:2 ends here */
