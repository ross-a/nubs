/* [[file:../nubs.org::*Bezier Curve][Bezier Curve:3]] */
package bezier

import "core:log"
import "core:math"

ZERO :: [2]f32{0,0}
Bezier_Type :: enum { QUADRATIC, CUBIC }

Bezier :: struct {
	startPos : [2]f32,
	endPos   : [2]f32,
	ctrlPos1 : [2]f32,
	ctrlPos2 : [2]f32,
	type : Bezier_Type,
}

Bez :: distinct [6]f32 // left handle's frame(x) and value(y). keyframes x, y.  then right handles x, y.

BezierList :: struct {
	l : [dynamic]Bez,
}

get_lut_bezier :: proc(bez: Bezier, divisions: int) -> [][2]f32 {
	ret := make([][2]f32, divisions+1)
	step := 1.0 / cast(f32)divisions
	curr := ZERO
	t : f32 = 0.0

	for i:=0; i <= divisions; i+=1 {
		t = step * cast(f32)i

		if bez.type == Bezier_Type.QUADRATIC {
			a := math.pow(1 - t, 2)
			b := 2 * (1 - t) * t
			c := math.pow(t, 2)

			curr.y = a*bez.startPos.y + b*bez.ctrlPos1.y + c*bez.endPos.y
			curr.x = a*bez.startPos.x + b*bez.ctrlPos1.x + c*bez.endPos.x
		} else if bez.type == Bezier_Type.CUBIC {
			a := math.pow(1 - t, 3)
			b := 3*math.pow(1 - t, 2)*t
			c := 3*(1-t)*math.pow(t, 2)
			d := math.pow(t, 3)

			curr.y = a*bez.startPos.y + b*bez.ctrlPos1.y + c*bez.ctrlPos2.y + d*bez.endPos.y
			curr.x = a*bez.startPos.x + b*bez.ctrlPos1.x + c*bez.ctrlPos2.x + d*bez.endPos.x
		}

		ret[i] = curr
	}
	return ret
}

get_lut_bez :: proc(bez: [2]Bez, ignore_first: bool) -> [][2]f32 {
	assert(bez[1][2] > bez[0][2])
	divisions := int(bez[1][2]-bez[0][2]) // assumes b[0] has frame less than b[1]
	ret := make([][2]f32, divisions+1)
	step := 1.0 / cast(f32)divisions
	curr := ZERO
	t : f32 = 0.0

	for i:=0; i <= divisions; i+=1 {
		t := step * cast(f32)i

		a := math.pow(1 - t, 3)
		b := 3*math.pow(1 - t, 2)*t
		c := 3*(1-t)*math.pow(t, 2)
		d := math.pow(t, 3)

		curr.y = a*bez[0][3] + b*bez[0][5] + c*bez[1][1] + d*bez[1][3]
		curr.x = a*bez[0][2] + b*bez[0][4] + c*bez[1][0] + d*bez[1][2]

		curr.x = math.round(curr.x) // TODO: this has to be an ERROR... fix me!

		ret[i] = curr
	}
	return ret
}

get_lut :: proc { get_lut_bezier, get_lut_bez }

// get one lut from many linked up bezier curves
get_lut_from_many_bezier :: proc(bez: []Bezier, divisions: []int) -> [][2]f32 {
	if len(bez) != len(divisions) {
		// can't use log. or fmt.  in wasm!
		//log.error("mismatched lengths")
	}

	cnt := 0
	for i in 0..<len(divisions) {
		cnt += divisions[i]
	}

	luts := make([][2]f32, cnt+1)
	idx := 0

	for i in 0..<len(bez) {
		lut := get_lut(bez[i], divisions[i])
		if idx > 0 {
			idx -= 1 // rewrite last point as these curves should be connected!
			if luts[idx] != lut[0] {
				//log.error("unconnected curves!", luts[idx], lut[0])
			}
		}
		for j in 0..<len(lut) {
			luts[idx] = lut[j]
			idx += 1
		}
		delete(lut)
	}
	return luts
}

get_lut_from_many_bez :: proc(bez: []Bez) -> [][2]f32 {
	luts := make([][2]f32, int(bez[len(bez)-1][2] - bez[0][2]) + 1)
	idx := 0
	for i in 1..<len(bez) {
		lut := get_lut( [2]Bez{bez[i-1], bez[i]}, i!=1 )
		j:= (i!=1) ? 1 : 0
		for ; j < len(lut); j+=1 {
			luts[idx] = lut[j]
			idx += 1
		}
		delete(lut)
	}
	return luts
}

get_lut_from_many :: proc { get_lut_from_many_bezier, get_lut_from_many_bez }

get_value_from_many :: proc(bez: []Bez, frame: i32) -> f32 {
	if len(bez) < 1 {
		return 0
	} else if cast(f32)frame <= bez[0][2] { // less than first keyframe
		return bez[0][3] // return value of first keyframe
	} else if cast(f32)frame >= bez[len(bez)-1][2] { // greater than last keyframe
		return bez[len(bez)-1][3] // value of last
	}
	// first find 2 Bez that frame is between
	for i in 1..<len(bez) {
		if cast(f32)frame >= bez[i-1][2] && cast(f32)frame <= bez[i][2] {
			divisions := int(bez[i][2]-bez[i-1][2])
			step := 1.0 / cast(f32)divisions
			t := step * (cast(f32)frame - bez[i-1][2])
			a := math.pow(1 - t, 3)
			b := 3*math.pow(1 - t, 2)*t
			c := 3*(1-t)*math.pow(t, 2)
			d := math.pow(t, 3)

			return a*bez[i-1][3] + b*bez[i-1][5] + c*bez[i][1] + d*bez[i][3]
		}
	}
	return 0
}
/* Bezier Curve:3 ends here */
