/* [[file:../../nubs.org::*Stars][Stars:2]] */
package stars_test


import "core:mem"
import "core:fmt"

import "core:sync"
import "core:thread"
import em_thread "../../emscripten_threads" // for emscripten/wasm pthread or wasm_workers

import "core:math/bits"
import "core:strings"
import rl "vendor:raylib"
import "base:runtime"
import stars "../"

tempAllocatorData: [mem.Megabyte * 1]byte
tempAllocatorArena: mem.Arena
mainMemoryData: [mem.Megabyte * 48]byte
mainMemoryArena: mem.Arena

MAX_INT :: bits.I32_MAX
MENU_RECT :: rl.Rectangle{250, 10, 240, 150}

Values :: struct {
	show_menu          : bool,
	brightness_factor  : f32 `15`, // Higher = brighter
	star_range_indices : f32 `10`, // Higher = more random looking, comp expensive
	level_depth        : f32 `6`,  // Higher = more (faint) stars, comp expensive
	star_density       : f32 `2`,  // Higher = more stars (2-3), comp expensive

	w, h: i32,
	panning: bool,
	textColor: rl.Color,
	clicked_pos: rl.Vector2,
	delta: rl.Vector2,

	pos: rl.Vector2,
	scale: f32,
	prev_scale: f32,

	star_data : stars.StarData,
	star_data_thread: union{^thread.Thread, em_thread.Thread},
}

values : Values
ctx: runtime.Context

@(export, link_name="_main")
_main :: proc "c" () {
	ctx = runtime.default_context()
	context = ctx

	mem.arena_init(&mainMemoryArena, mainMemoryData[:])
	mem.arena_init(&tempAllocatorArena, tempAllocatorData[:])
	ctx.allocator      = mem.arena_allocator(&mainMemoryArena)
	ctx.temp_allocator = mem.arena_allocator(&tempAllocatorArena)
	
	main()
}
main :: proc () {
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		context = ctx // this is important! for [dynamic]stuff in -target=freestanding_wasm
	}
	
	//ta := mem.Tracking_Allocator{}
	//mem.tracking_allocator_init(&ta, context.allocator)
	//context.allocator = mem.tracking_allocator(&ta)
	//
	//defer {
	//  if len(ta.allocation_map) > 0 {
	//    for _, v in ta.allocation_map {
	//      fmt.printf("Leaked %v bytes @ %v\n", v.size, v.location)
	//    }
	//  }
	//  if len(ta.bad_free_array) > 0 {
	//    fmt.println("Bad frees:");
	//    for v in ta.bad_free_array {
	//      fmt.println(v)
	//    }
	//  }
	//}

	WIDTH :: 800
	HEIGHT :: 600
	
	values.brightness_factor = 15
	values.star_range_indices = 10
	values.level_depth = 6
	values.star_density = 2
	values.scale = 1
	values.star_data.rect = [4]f32{values.pos.x, values.pos.y, WIDTH / values.scale, HEIGHT / values.scale}
	values.textColor = rl.LIGHTGRAY

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		rl.SetConfigFlags(rl.ConfigFlags{rl.ConfigFlag.WINDOW_RESIZABLE})
	} else {
		t_s := em_thread.wrap_size_pthread_t()
		m_s := em_thread.wrap_size_pthread_mutex_t()
		c_s := em_thread.wrap_size_pthread_cond_t()
		values.star_data_thread = em_thread.Thread{}
		if i, ok := &values.star_data_thread.(em_thread.Thread); ok {
			i.t_size = t_s
			i.m_size = m_s
			i.c_size = c_s
			i.thread = &i.d
			i.mutex = &i.d[t_s]
			i.cond = &i.d[t_s + m_s]
			i.flags = {.Done}
		}
	}

	// get initial stars
	values.star_data.stars = stars.get_stars(values.star_data.rect, &values)
	
	rl.InitWindow(WIDTH, HEIGHT, "Stars Test")
	rl.SetTargetFPS(60)
	
	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		for !rl.WindowShouldClose() {
			update()
		}
		rl.CloseWindow()
	}

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		if values.star_data_thread != nil {
			for ; !thread.is_done(values.star_data_thread.(^thread.Thread)); {}
			free(&values.star_data_thread.(^thread.Thread))
		}
	}
}

@(export, link_name="step")
step :: proc "contextless" () {
	context = ctx
	update()
}

update_stars :: proc(values: ^Values) {
	_update_stars1 :: proc "c" (raw_v: rawptr) -> rawptr {
		context = ctx
		values := transmute(^Values)raw_v

		if i, ok := &values.star_data_thread.(em_thread.Thread); ok {
			em_thread.wrap_pthread_mutex_lock(i.mutex)
			rect := values.star_data.rect // cpy while safe?
			for ; !(.Started in i.flags); {
				em_thread.wrap_pthread_cond_wait(i.cond, i.mutex)
			}
			em_thread.wrap_pthread_mutex_unlock(i.mutex)

			// without this temp mem, things fill up pretty fast!
			tmp_mem := mem.begin_arena_temp_memory(&mainMemoryArena)
			work_stars := stars.get_stars(rect, values)

			em_thread.wrap_pthread_mutex_lock(i.mutex)
			clear(&values.star_data.stars)
			for si in work_stars {
				append(&values.star_data.stars, si)
			}
			mem.end_arena_temp_memory(tmp_mem)
			i.flags = {.Done}
			em_thread.wrap_pthread_mutex_unlock(i.mutex)
		}
		return nil
	}
	_update_stars2 :: proc(t: ^thread.Thread) {
		values := transmute(^Values)t.data

		sync.lock(&t.mutex)
		rect := values.star_data.rect
		sync.unlock(&t.mutex)

		work_stars := stars.get_stars(rect, values)
		
		sync.lock(&t.mutex)
		clear(&values.star_data.stars)
		for si in work_stars {
			append(&values.star_data.stars, si)
		}
		sync.unlock(&t.mutex)
	}

	if i, ok := &values.star_data_thread.(em_thread.Thread); ok {
		if !(.Started in i.flags) {
			// TODO use thread_attr(currently nil) to create with detach flag set
			_ = em_thread.PTHREAD_CREATE_DETACHED

			//em_thread.wrap_emscripten_console_log("create thread\n")
			em_thread.wrap_pthread_create(i.thread, nil, _update_stars1, values)
			i.flags = {.Started}
			em_thread.wrap_pthread_cond_signal(i.cond)
		}
	} else {
		if values.star_data_thread == nil || thread.is_done(values.star_data_thread.(^thread.Thread)) {
			t := thread.create(_update_stars2)
			values.star_data_thread = t
			t.data = values
			thread.start(t)
		}
	}  
}

update :: proc() {
	using rl

	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		if (mainMemoryArena.offset >= mem.Megabyte * 48) {
			free_all() // TODO: fix the horrible fix here for running out of memory
			return
		}
	}
	
	// Update ------------------------------
	w := GetScreenWidth()
	h := GetScreenHeight()

	// if menu is open and mouse is inside menu don't do this stuff
	d := GetMousePosition()
	menu_rect := MENU_RECT
	menu_rect.x = f32(w) - menu_rect.x
	if !values.show_menu || !CheckCollisionPointRec(d, menu_rect) {
		if IsMouseButtonPressed(MouseButton.LEFT) && !values.panning {
			values.panning = true
			values.clicked_pos = GetMousePosition()
			values.textColor = YELLOW
		}
		if IsMouseButtonDown(MouseButton.LEFT) {
			values.delta.x = (values.clicked_pos.x - d.x) / values.scale
			values.delta.y = (values.clicked_pos.y - d.y) / values.scale
			values.star_data.rect.x = values.pos.x + values.delta.x
			values.star_data.rect.y = values.pos.y + values.delta.y
			// update stars
			update_stars(&values)
		} else if values.panning { // no .LEFT being pressed anymo'
			values.panning = false
			values.pos.x += values.delta.x
			values.pos.y += values.delta.y
			values.delta.x = 0
			values.delta.y = 0
			values.textColor = LIGHTGRAY
		}
		
		gmwm : f32 = GetMouseWheelMove()
		if gmwm != 0.0 {
			mult : f32 = (gmwm > 0.5) ? 1.11 : (1 / 1.11)
			values.scale *= mult
			// too far zoomed in things start to look like a grid (happens with .scale upwards of +400000)
			// too far zoomed out stars just disappear (happens with .scale around 4e-17)
			// TODO: think of some solution? or just keep this behavior?
			if (values.scale * f32(w) > MAX_INT) || (values.scale * f32(h) > MAX_INT) {
				values.scale = values.prev_scale
			}
			
			e := GetMousePosition()
			values.pos.x += e.x * (1 - 1 / mult) / values.scale
			values.pos.y += e.y * (1 - 1 / mult) / values.scale
		}
		if values.scale != values.prev_scale {
			values.star_data.rect.x = values.pos.x + values.delta.x
			values.star_data.rect.y = values.pos.y + values.delta.y
			values.star_data.rect.z = f32(w) / values.scale
			values.star_data.rect.w = f32(h) / values.scale
			// update stars
			update_stars(&values)
			values.prev_scale = values.scale
		}
	}

	// Draw   ------------------------------
	BeginDrawing()
	ClearBackground(BLACK)

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		sync.lock(&values.star_data_thread.(^thread.Thread).mutex)
	} else {
		em_thread.wrap_pthread_mutex_lock(values.star_data_thread.(em_thread.Thread).mutex)
	}
	for star in values.star_data.stars {
		a : u8 = cast(u8)(star.z * 255)
		x := cast(i32)((star.x - (values.pos.x + values.delta.x)) * values.scale)
		y := cast(i32)((star.y - (values.pos.y + values.delta.y)) * values.scale)
		DrawPixel(x, y, Color{a,a,a,a})
	}
	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		sync.unlock(&values.star_data_thread.(^thread.Thread).mutex)
	} else {
		em_thread.wrap_pthread_mutex_unlock(values.star_data_thread.(em_thread.Thread).mutex)
	}

	// note: I can't get fmt.tprintf() working with freestanding_wasm!
	DrawText("Pan: hold left mouse button", 0, 0, 20, values.textColor)
	sb := strings.builder_make()
	strings.write_f32(&sb, values.pos.x + values.delta.x, 'g', true)
	strings.write_string(&sb, " ")
	strings.write_f32(&sb, values.pos.y + values.delta.y, 'g', true)
	strings.write_string(&sb, " ")
	strings.write_f32(&sb, values.scale, 'g', true)
	strings.write_string(&sb, " ")
	strings.write_byte(&sb, 0)
	DrawText(cstring(raw_data(sb.buf[:])), 0, 21, 20, values.textColor)
	DrawText("Zoom: scroll mouse wheel", 0, 41, 20, values.textColor)
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		strings.builder_reset(&sb)
		strings.write_string(&sb, "mem: ")
		strings.write_f32(&sb, f32(mainMemoryArena.offset), 'g', true)
		strings.write_byte(&sb, 0)
		DrawText(cstring(raw_data(sb.buf[:])), 0, 61, 20, values.textColor)
	}
	strings.builder_destroy(&sb)
	
	draw_menu(w, h, &values)

	EndDrawing()
}

draw_menu :: proc(w, h: i32, values: ^Values) {
	using rl

	menu_rect := MENU_RECT
	menu_rect.x = f32(w) - menu_rect.x
	if !values.show_menu {
		values.show_menu = GuiButton(Rectangle{f32(w) - 40, 13, 18, 18}, "_")
	} else {
		panel := GuiPanel(menu_rect, "")
		values.show_menu = !GuiButton(Rectangle{f32(w) - 40, 13, 18, 18}, "_")
		
		tmp_brightness := values.brightness_factor
		GuiSlider(Rectangle{f32(w) - 185, 40, 160, 20}, "brightness", "", &tmp_brightness, 5, 150)
		values.brightness_factor = tmp_brightness

		// with freestanding_wasm maybe update_stars() thread is messin' wif strings built here
		// TODO: try putting them in a diff allocator?
		sb := strings.builder_make()
		strings.write_f32(&sb, values.brightness_factor, 'g', false)
		strings.write_byte(&sb, 0)
		cstr := cstring(raw_data(sb.buf[:]))
		
		GuiTextBox(Rectangle{f32(w) - 185, 40, 160, 20}, cstr, 10, false)
		
		tmp_star_range_indices := values.star_range_indices
		GuiSlider(Rectangle{f32(w) - 185, 65, 160, 20}, "randomy", "", &tmp_star_range_indices, 5, 15)
		values.star_range_indices = tmp_star_range_indices

		strings.builder_reset(&sb)
		strings.write_f32(&sb, values.star_range_indices, 'g', false)
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))
		
		GuiTextBox(Rectangle{f32(w) - 185, 65, 160, 20}, cstr, 10, false)
		
		tmp_level_depth := values.level_depth
		GuiSlider(Rectangle{f32(w) - 185, 90, 160, 20}, "depth", "", &tmp_level_depth, 1, 8)
		values.level_depth = tmp_level_depth

		strings.builder_reset(&sb)
		strings.write_f32(&sb, values.level_depth, 'g', false)
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))

		GuiTextBox(Rectangle{f32(w) - 185, 90, 160, 20}, cstr, 10, false)
		
		tmp_star_density := values.star_density
		GuiSlider(Rectangle{f32(w) - 185, 115, 160, 20}, "density", "", &tmp_star_density, 1, 2)
		values.star_density = tmp_star_density

		strings.builder_reset(&sb)
		strings.write_f32(&sb, values.star_density, 'g', false)
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))

		GuiTextBox(Rectangle{f32(w) - 185, 115, 160, 20}, cstr, 10, false)

		strings.builder_destroy(&sb)
	}
}
/* Stars:2 ends here */
