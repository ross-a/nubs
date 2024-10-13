/* [[file:../../nubs.org::*Bezier Curve][Bezier Curve:2]] */
package bezier_test

import "core:fmt"
import "core:mem"
import rl "vendor:raylib"
import bezier "../"
import "base:runtime"

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

update :: proc() {
	@static with_raylib := false
	s := [2]f32{10, 20}
	h1 := [2]f32{20, 20}
	e := [2]f32{60, 80}
	e2 := [2]f32{180, 50}
	h2 := [2]f32{70, 100}
	h3 := [2]f32{75, 110}

	bez1 := bezier.Bezier{s, e, h1, bezier.ZERO, bezier.Bezier_Type.QUADRATIC}
	bez2 := bezier.Bezier{e, e2, h2, h3, bezier.Bezier_Type.CUBIC}
	thick : f32 = 1.0
	color := rl.WHITE

	bezs := []bezier.Bezier{bez1, bez2}
	divs := []int{10, 10}
	lut := bezier.get_lut_from_many(bezs, divs); defer delete(lut)

	b : []bezier.Bez = { bezier.Bez{-2,0,1,0,4,0},
	                     bezier.Bez{7,3,10,3,13,3},
	                     bezier.Bez{16,0,20,0,23,0} }
	lut2 := bezier.get_lut_from_many(b); defer delete(lut2)

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		fmt.println(lut2)
		fmt.println(bezier.get_value_from_many(b, 9))
		fmt.println(bezier.get_value_from_many(b, 20))
	}
	
	// Update ------------------------------
	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
		with_raylib = !with_raylib
	}

	// Draw   ------------------------------
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	if with_raylib {
		pt_cnt := 3
		pts := make([^]rl.Vector2, pt_cnt); defer free(pts)
		pts[0] = rl.Vector2{s[0], s[1]}
		pts[2] = rl.Vector2{e[0], e[1]}
		pts[1] = rl.Vector2{h1[0], h1[1]}
		rl.DrawSplineBezierQuadratic(pts, i32(pt_cnt), thick, color)
		pts[0] = rl.Vector2{e[0], e[1]}
		pts[2] = rl.Vector2{e2[0], e2[1]}
		pts[1] = rl.Vector2{h2[0], h2[1]}
		rl.DrawSplineBezierQuadratic(pts, i32(pt_cnt), thick, color)
	} else {
		for i in 0..<len(lut)-1 {
			rl.DrawLineEx(rl.Vector2{lut[i][0], lut[i][1]}, rl.Vector2{lut[i+1][0], lut[i+1][1]}, thick, color)
		}
	}

	rl.EndDrawing()
}

main :: proc() {
	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		ta := mem.Tracking_Allocator{};
		mem.tracking_allocator_init(&ta, context.allocator);
		context.allocator = mem.tracking_allocator(&ta);
	}

	{
		WIDTH  :: 800
		HEIGHT :: 600

		rl.InitWindow(WIDTH, HEIGHT, "Bezier")
		rl.SetTargetFPS(60)

		for !rl.WindowShouldClose() {
			update()
		}
		rl.CloseWindow()
	}

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {	
		if len(ta.allocation_map) > 0 {
			for _, v in ta.allocation_map {
				fmt.printf("Leaked %v bytes @ %v\n", v.size, v.location)
			}
		}
		if len(ta.bad_free_array) > 0 {
			fmt.println("Bad frees:")
			for v in ta.bad_free_array {
				fmt.println(v)
			}
		}
	}
}
/* Bezier Curve:2 ends here */
