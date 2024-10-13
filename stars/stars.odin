/* [[file:../nubs.org::*Stars][Stars:3]] */
package stars


import "core:sync"
import "core:thread"
import em_thread "../emscripten_threads"
import "core:math"
import "core:math/bits"
import "core:strings"
import "base:runtime"

MAX_INT :: bits.I32_MAX

Cache :: distinct map[string][3]f32

StarData :: struct {
  stars : [dynamic][3]f32,
  rect  : [4]f32,
}

hashFnv32 :: proc(s : string) -> i32 {
  h : u32 = 0x811c9dc5
  hval : i32 = cast(i32)h

  for i, l := 0, len(s); i < l; i+=1 {
    hval ~=  cast(i32)s[i]
    hval += (hval << 1) + (hval << 4) + (hval << 7) + (hval << 8) +   (hval << 24)
  }
  return hval
}

cached_hash :: proc(to_hash : string, cache : ^Cache = nil) -> [3]f32 {
  if cache != nil {
    if cached, ok := cache[to_hash]; !ok {
      return cached
    }
  }
  a := cast(f32)hashFnv32(strings.concatenate({to_hash, "a"}))
  b := cast(f32)hashFnv32(strings.concatenate({to_hash, "b"}))
  c := cast(f32)hashFnv32(strings.concatenate({to_hash, "c"}))
  digest := [3]f32{ a, b, c }
  if cache != nil {
    cache[to_hash] = digest
  }
  return digest
}

get_stars :: proc(rect: [4]f32, values: ^$T) -> (work_stars: [dynamic][3]f32) {
  // The level at which you would expect one star in current viewport.
  level_for_current_density := - math.log_f32(rect[2] * rect[3], math.E) / values.star_density
  start_level := math.floor_f32(level_for_current_density)

  for level := start_level; level < start_level + values.level_depth; level += 1 {
    spacing := math.exp_f32(-level)
    
    prev_xIndex := math.floor_f32(rect.x / spacing) - values.star_range_indices - 1
    for
      xIndex := math.floor_f32(rect.x / spacing) - values.star_range_indices;
    xIndex <= math.ceil_f32((rect.x + rect[2]) / spacing) + values.star_range_indices;
    xIndex += 1
    {
      if xIndex == prev_xIndex {
        break // break if some rounding or precision error with floats makes a +1 meaningless, then inf loop stuck
      }
      prev_xIndex = xIndex
      prev_yIndex := math.floor_f32(rect.y / spacing) - values.star_range_indices - 1;
      for
        yIndex := math.floor_f32(rect.y / spacing) - values.star_range_indices;
      yIndex <= math.ceil_f32((rect.y + rect[3]) / spacing) + values.star_range_indices;
      yIndex += 1
      {
        if yIndex == prev_yIndex {
          break // break if some rounding or precision error with floats makes a +1 meaningless, then inf loop stuck
        }
        prev_yIndex = yIndex
        sb := strings.builder_make()
        strings.write_f32(&sb, xIndex, 'g', false)
        strings.write_rune(&sb,':')
        strings.write_f32(&sb, yIndex, 'g', false)
        strings.write_rune(&sb,':')
        strings.write_f32(&sb, level, 'g', false)
        str := strings.to_string(sb)
        hash := cached_hash(str)
        strings.builder_destroy(&sb)
        
        e1 := math.exp_f32(level_for_current_density - level - abs(hash.z / MAX_INT))
        e2 := math.exp_f32(level_for_current_density - (start_level + values.level_depth))
        t := math.atan((e1 - e2) * values.brightness_factor) * 2 / math.PI
        
        append(&work_stars, [3]f32{
          xIndex * spacing + (hash.x / MAX_INT) * spacing * values.star_range_indices,
          yIndex * spacing + (hash.y / MAX_INT) * spacing * values.star_range_indices,
          max(0, t)})
      }
    }
  }
  return
}
/* Stars:3 ends here */
