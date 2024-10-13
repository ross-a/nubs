/* [[file:../../nubs.org::*Celtic Knots][Celtic Knots:2]] */
package knots_test

import "core:mem"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import knots "../"
import "base:runtime"

values : knots.Values

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	tempAllocatorData: [mem.Megabyte * 1]byte
	tempAllocatorArena: mem.Arena
	mainMemoryData: [mem.Megabyte * 48]byte
	mainMemoryArena: mem.Arena

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
	@(export, link_name="step")
	step :: proc "contextless" () {
		context = ctx
		update()
	}
}

main :: proc() {
	using knots

	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		context = ctx // this is important! for [dynamic]stuff in -target=freestanding_wasm
	}

	WIDTH  :: 800
	HEIGHT :: 600

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {	
		rl.SetConfigFlags(rl.ConfigFlags{rl.ConfigFlag.WINDOW_RESIZABLE})
	}
	rl.InitWindow(WIDTH, HEIGHT, "Knot Generator")
	rl.SetTargetFPS(60)

	values.show_menu = false
	values.grid = [?]i32{2,3}
	values.grid_spacing = 80
	values.margin = [?]i32{10,10}
	values.rounding = 0.80  // unused
	values.thickness = 0.50
	values.gap = .07
	values.symmetry = ""
	values.elbow_segments = 4
	values.show_breaks = false
	values.breaks_percent = 0.5
	alloc_breaks(&values)
	random_break_spots(&values)

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {		
		for !rl.WindowShouldClose() {
			update()
		}
		rl.CloseWindow()
		
		clean_breaks(&values)
		delete(values.break_spots)
		delete(values.cells)
	}
}

update :: proc() {
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		if (mainMemoryArena.offset >= mem.Megabyte * 46) {
			free_all() // TODO: fix the horrible fix here for running out of memory
			return
		}
	}

	// Update ------------------------------
	w := rl.GetScreenWidth()
	h := rl.GetScreenHeight()
	
	// Draw   ------------------------------
	rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)
	
	if values.show_breaks {
		draw_grid(w, h, &values)
		draw_bounds(w, h, &values)
	}
	draw_knot(&values)
	draw_menu(w, h, &values)
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		rl.DrawFPS(0,0)
		sb := strings.builder_make()
		strings.write_string(&sb, "mem: ")
		strings.write_f32(&sb, f32(mainMemoryArena.offset), 'g', true)
		strings.write_byte(&sb, 0)
		rl.DrawText(cstring(raw_data(sb.buf[:])), 100, 1, 20, rl.BLUE)
	}
	strings.builder_destroy(&sb)

	
	rl.EndDrawing()
}

draw_grid :: proc(w, h: i32, values: ^knots.Values) {
	for y in 0..<values.grid.y {
		for x in 0..<values.grid.x {
			//rl.DrawRectangleLines(x * values.grid_spacing + values.margin.x, y * values.grid_spacing + values.margin.y, values.grid_spacing + 1, values.grid_spacing + 1, rl.BLACK)
		}
	}
	// primary dots
	for y in 0..=values.grid.y {
		for x in 0..=values.grid.x {
			rl.DrawCircle(x * values.grid_spacing + values.margin.x, y * values.grid_spacing + values.margin.y, 4, rl.RED)
		}
	}
	// secondary dots
	for y in 0..<values.grid.y {
		for x in 0..<values.grid.x {
			xx : f32 = (f32(x)+0.5) * f32(values.grid_spacing) + f32(values.margin.x)
			yy : f32 = (f32(y)+0.5) * f32(values.grid_spacing) + f32(values.margin.y)
			rl.DrawCircle(i32(xx), i32(yy), 4, rl.GRAY)      
		}
	}
}

draw_bounds :: proc(w, h: i32, values: ^knots.Values) {
	knots.scan_for_short_and_long_arcs(values)  

	for y in 0..<values.grid.y*2 {
		for x in 0..<values.grid.x*2 {
			c := values.cells[y * (values.grid.x*2) + x]

			// center of cell
			c.xx = (f32(c.x)+0.5) * f32(values.grid_spacing)/2 + f32(values.margin.x)
			c.yy = (f32(c.y)+0.5) * f32(values.grid_spacing)/2 + f32(values.margin.y)
			
			xl := i32(c.xx - f32(values.grid_spacing)/4)
			yu := i32(c.yy - f32(values.grid_spacing)/4)
			xr := i32(c.xx + f32(values.grid_spacing)/4)
			yb := i32(c.yy + f32(values.grid_spacing)/4)

			if c.bn {
				rl.DrawLine(xl, yu, xr, yu, rl.BLACK)
			}
			if c.bs {
				rl.DrawLine(xl, yb, xr, yb, rl.BLACK)
			}
			if c.be {
				rl.DrawLine(xr, yu, xr, yb, rl.BLACK)
			}
			if c.bw {
				rl.DrawLine(xl, yu, xl, yb, rl.BLACK)
			}
		}
	}
}

draw_knot :: proc(values: ^knots.Values) {
	using knots

	tmp_values : knots.Values
	tmp_mem : mem.Arena_Temp_Memory
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		tmp_values = values^
			tmp_mem = mem.begin_arena_temp_memory(&mainMemoryArena)
	}
	
	knot_paths : [dynamic]KnotPath; defer delete(knot_paths)
	get_knot(values, &knot_paths)
	// TODO: don't get_knot everytime
	
	colr := rl.BLACK
	//if false {      // TODO: put cell in knot_path??
	//  if c.type == u16(CellType.DIAGONAL) {
	//    colr = rl.GRAY
	//  } else if c.type == u16(CellType.CORNER) {
	//    colr = rl.RED
	//  } else if c.type == u16(CellType.ELBOW) {
	//    colr = rl.GREEN
	//  } else if c.type == u16(CellType.SHORT_ARC) {
	//    colr = rl.BLACK
	//  } else if c.type == u16(CellType.LONG_ARC) {
	//    colr = rl.BEIGE
	//  }
	//  //rl.DrawSplineLinear(path, i32(path_pts), 1, colr)
	//}

	for k in knot_paths {
		rl.DrawTriangleStrip(k.path, i32(k.path_pts), colr)
		free(k.path)
	}
	
	// test elbox control points
	//if c.type == u16(CellType.LONG_ARC) {
	//  rl.DrawCircle(i32(xx + pma.x * f32(values.grid_spacing)/2), i32(yy + pma.y * f32(values.grid_spacing)/2), 2, rl.RED)
	//  rl.DrawCircle(i32(xx + pma.z * f32(values.grid_spacing)/2), i32(yy + pma.w * f32(values.grid_spacing)/2), 2, rl.GREEN)
	//  rl.DrawCircle(i32(xx + pmb.x * f32(values.grid_spacing)/2), i32(yy + pmb.y * f32(values.grid_spacing)/2), 2, rl.BLACK)
	//  rl.DrawCircle(i32(xx + pmb.z * f32(values.grid_spacing)/2), i32(yy + pmb.w * f32(values.grid_spacing)/2), 2, rl.DARKGREEN)
	//}
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		mem.end_arena_temp_memory(tmp_mem)
		values^ = tmp_values
	}
}

draw_menu :: proc(w, h: i32, values: ^knots.Values) {
	using knots

	if !values.show_menu {
		values.show_menu = rl.GuiButton(rl.Rectangle{f32(w) - 40, 13, 18, 18}, "_")
	} else {
		panel := rl.GuiPanel(rl.Rectangle{f32(w) - 210, 10, 190, 430}, "")
		values.show_menu = !rl.GuiButton(rl.Rectangle{f32(w) - 40, 13, 18, 18}, "_")    
		tmp_x := f32(values.grid.x)
		tmp_y := f32(values.grid.y)
		rl.GuiSlider(rl.Rectangle{f32(w) - 185, 40, 160, 20}, "x", "", &tmp_x, 1, 120)
		sb := strings.builder_make()
		strings.write_int(&sb, int(tmp_x))
		strings.write_byte(&sb, 0)
		cstr := cstring(raw_data(sb.buf[:]))
		rl.GuiTextBox(rl.Rectangle{f32(w) - 185, 40, 160, 20}, cstr, 10, false)
		rl.GuiSlider(rl.Rectangle{f32(w) - 185, 65, 160, 20}, "y", "", &tmp_y, 1, 20)
		strings.builder_reset(&sb)
		strings.write_int(&sb, int(tmp_y))
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))
		rl.GuiTextBox(rl.Rectangle{f32(w) - 185, 65, 160, 20}, cstr, 10, false)

		values.grid.x = i32(tmp_x)
		values.grid.y = i32(tmp_y)
		if (values.grid.y != values.prev_grid.y) || (values.grid.x != values.prev_grid.x) {
			clean_breaks(values)
			alloc_breaks(values)
			random_break_spots(values)
		}
		values.prev_grid = values.grid
		
		tmp_spacing := f32(values.grid_spacing)
		rl.GuiSlider(rl.Rectangle{f32(w) - 185, 90, 160, 20}, "spc", "", &tmp_spacing, 8, 120)
		values.grid_spacing = i32(tmp_spacing)
		strings.builder_reset(&sb)
		strings.write_int(&sb, int(tmp_spacing))
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))
		rl.GuiTextBox(rl.Rectangle{f32(w) - 185, 90, 160, 20}, cstr, 10, false)

		tmp_thickness := values.thickness * 100
		rl.GuiSlider(rl.Rectangle{f32(w) - 185, 115, 160, 20}, "thk", "", &tmp_thickness, 0, 100)
		if (values.thickness * 100) != tmp_thickness {
			clear(&values.cells)
		}
		values.thickness = tmp_thickness / 100
		strings.builder_reset(&sb)
		strings.write_f32(&sb, values.thickness, 'g', false)
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))
		rl.GuiTextBox(rl.Rectangle{f32(w) - 185, 115, 160, 20}, cstr, 10, false)

		tmp_gap := values.gap * 100
		rl.GuiSlider(rl.Rectangle{f32(w) - 185, 140, 160, 20}, "gap", "", &tmp_gap, 0, 50)
		if (values.gap * 100) != tmp_gap {
			clear(&values.cells)
		}
		values.gap = tmp_gap / 100
		strings.builder_reset(&sb)
		strings.write_f32(&sb, values.gap, 'g', false)
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))
		rl.GuiTextBox(rl.Rectangle{f32(w) - 185, 140, 160, 20}, cstr, 10, false)

		if rl.GuiToggle(rl.Rectangle{f32(w) - 185, 165, 160, 20}, "border & grid", &values.show_breaks) > 0 {
			values.show_breaks = !values.show_breaks
		}

		tmp_bpercent := values.breaks_percent * 100
		rl.GuiSlider(rl.Rectangle{f32(w) - 185, 190, 160, 20}, "b %", "", &tmp_bpercent, 0, 100)
		if (values.breaks_percent * 100) != tmp_bpercent {
			clean_breaks(values)
			alloc_breaks(values)
			random_break_spots(values)
		}
		values.breaks_percent = tmp_bpercent / 100
		strings.builder_reset(&sb)
		strings.write_f32(&sb, values.breaks_percent, 'g', false)
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))
		rl.GuiTextBox(rl.Rectangle{f32(w) - 185, 190, 160, 20}, cstr, 10, false)

		@static dropdown_toggle := false
		
		if !dropdown_toggle { // controls to draw "under" the dropdown below
			rl.GuiToggle(rl.Rectangle{f32(w) - 185, 240, 160, 20}, "ringify", &values.ringify)
			tmp_border_x := values.border_x
			rl.GuiToggle(rl.Rectangle{f32(w) - 185, 265, 160, 20}, "border x", &tmp_border_x)
			if tmp_border_x != values.border_x {
				values.border_x = tmp_border_x
				clean_breaks(values)
				alloc_breaks(values)
				random_break_spots(values)
			}
			tmp_border_y := values.border_y
			rl.GuiToggle(rl.Rectangle{f32(w) - 185, 290, 160, 20}, "border y", &tmp_border_y)
			if tmp_border_y != values.border_y {
				values.border_y = tmp_border_y
				clean_breaks(values)
				alloc_breaks(values)
				random_break_spots(values)
			}
		}
		
		syms := get_symmetries()
		strings.builder_reset(&sb)
		for s,idx in syms {
			if idx == 0 {
				strings.write_string(&sb, s.str)
			} else {
				strings.write_string(&sb, "\n")
				strings.write_string(&sb, s.str)
			}
		}
		strings.write_byte(&sb, 0)
		cstr = cstring(raw_data(sb.buf[:]))
		active : i32 = 0
		for s,idx in syms {
			if values.symmetry == s.str {
				active = s.num
				break
			}
		}
		if rl.GuiDropdownBox(rl.Rectangle{f32(w) - 185, 215, 160, 20}, cstr, &active, dropdown_toggle) {
			dropdown_toggle = !dropdown_toggle
			for s,idx in syms {
				if active == s.num {
					values.symmetry = s.str
				}
			}
			clean_breaks(values)
			alloc_breaks(values)
			random_break_spots(values)
		}
		strings.builder_destroy(&sb)
		
	}
}
/* Celtic Knots:2 ends here */
