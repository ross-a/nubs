/* [[file:../nubs.org::*Celtic Knots][Celtic Knots:4]] */
package knots


import "core:math"
import "core:math/linalg"
import "core:math/rand"

Values :: struct {
  show_menu: bool,
  grid: [2]i32,
  prev_grid: [2]i32,
  grid_spacing: i32,
  margin: [2]i32,
  rounding: f32, // unused
  thickness: f32,
  gap: f32,
  symmetry: string,
  elbow_segments: i32,
  show_breaks: bool,
  ringify: bool,
  border_x: bool,
  border_y: bool,
  breaks_percent: f32,
  breaks: []string,
  break_spots: [dynamic]([2]i32),
  cells: [dynamic]Cell,
}

Symmetry :: struct {
  num: i32,
  str: string,
}

get_symmetries :: proc() -> [4]Symmetry {
  syms := [?]Symmetry{ Symmetry{0, "None"},
                       Symmetry{1, "180 rotation"},
                       Symmetry{2, "4-fold mirror"},
                       Symmetry{3, "8-fold mirror"} }
  return syms
}

get_spline_pt_bezier_cubic :: proc(start, ctrlp1, ctrlp2, end: [2]f32, t: f32) -> [2]f32 {
  point : [2]f32
  
  a := math.pow(1.0 - t, 3)
  b := 3.0*math.pow(1.0 - t, 2)*t
  c := 3.0*(1.0 - t)*math.pow(t, 2)
  d := math.pow(t, 3)

  point.y = a*start.y + b*ctrlp1.y + c*ctrlp2.y + d*end.y;
  point.x = a*start.x + b*ctrlp1.x + c*ctrlp2.x + d*end.x;

  return point
}

// Rip'd from: https://www.glassner.com/wp-content/uploads/2014/04/CG-CGA-PDF-99-09-Celtic-Knotwork-1-Sept99.pdf
ELBOWS :: [?][4]f32{ [4]f32{24,0,  30,0},  // c0
                     [4]f32{24,3,  26,5},  // c1
                     [4]f32{17,4,  22,8},  // c2
                     [4]f32{15,8,  26,10}, // c3
                     [4]f32{11,10, 23,13}, // c4
                     [4]f32{9,10,  21,14}, // c5
                     [4]f32{11,19, 18,20}, // c6
                     [4]f32{10,23, 23,25}, // c7
                     [4]f32{3,23,  10,31}, // c8
                     [4]f32{3,25,  10,31} }// c9
// Short Arcs (c4 paired with c5 for thinnest curve, c0-c9 for fattest/thickest).. these assume 32x32 cells
SHORT_ARCS :: [?][4]f32{ [4]f32{24,0, 29,0},  // c0
                         [4]f32{22,1, 29,1},  // c1
                         [4]f32{19,6, 21,7},  // c2
                         [4]f32{13,7, 18,11}, // c3
                         [4]f32{8,6,  16,15}, // c4
                         [4]f32{7,8,  15,17}, // c5
                         [4]f32{9,17, 16,21}, // c6
                         [4]f32{9,22, 14,25}, // c7
                         [4]f32{4,25, 11,31}, // c8
                         [4]f32{4,26, 11,32} }// c9
// Long Arcs
LONG_ARCS :: [?][4]f32{ [4]f32{24,0,  60,0},  // c0
                        [4]f32{22,1,  61,1},  // c1
                        [4]f32{21,8,  56,7},  // c2
                        [4]f32{18,11, 36,11}, // c3
                        [4]f32{17,16, 32,16}, // c4
                        [4]f32{17,18, 31,16}, // c5
                        [4]f32{16,23, 40,21}, // c6
                        [4]f32{13,26, 46,25}, // c7
                        [4]f32{11,32, 43,31}, // c8
                        [4]f32{11,34, 43,32} }// c9

CellType :: enum {
  VBAR,
  HBAR,
  CORNER,
  DIAGONAL,
  ELBOW,
  SHORT_ARC, // 2 elbows sharing an edge
  LONG_ARC,  // 2 elbows connected via a bar
  BAR_REMOVED,
}

Cell :: struct {
  bn: bool, // breaks
  be: bool,
  bs: bool,
  bw: bool,
  
  x: i32,   // cell position
  y: i32,
  xx: f32,  // pixel (center) postion
  yy: f32,
  p1: [2]f32,
  p2: [2]f32,
  type: u16,
  elbow_type: u16, // 1 to 8
  needsMiddlePoint: bool,
}

clean_breaks :: proc(values: ^Values) {
  for y in 0..<len(values.breaks) {
    delete(values.breaks[y])
  }
  delete(values.breaks)
}

alloc_breaks :: proc(values: ^Values) {
  clear(&values.cells)
  
  clear(&values.break_spots)
  values.breaks = make([]string, values.grid.y*2+1)
  for y in 0..<(values.grid.y*2 + 1) {
    values.breaks[y] = string(make([]u8, values.grid.x*2+1))
  }
  
  for y in 0..<(values.grid.y*2 + 1) {
    isTopOrBottom := (y == 0) || (y == values.grid.y*2)
    if values.border_y {
      isTopOrBottom = false // loops around top <-> bottom
    }
    for x in 0..<(values.grid.x*2 + 1) {
      if ((x+y) % 2) == 0 { // has to be odd to be on grid
        raw_data(values.breaks[y])[x] = ' '
        continue
      }
      // mark edges
      if isTopOrBottom {
        raw_data(values.breaks[y])[x] = '-'
        continue
      }
      isLeftOrRight := (x == 0) || (x == values.grid.x*2)
      if values.border_x {
        isLeftOrRight = false // loops around left <-> right
      }

      if isLeftOrRight {
        raw_data(values.breaks[y])[x] = '|'
        continue
      }

      raw_data(values.breaks[y])[x] = ' '

      if values.symmetry == "180 rotational" {
        if y > values.grid.y do continue
      } else if values.symmetry == "4-fold mirror" {
        if (y > values.grid.y) || (x > values.grid.x) do continue
      } else if values.symmetry == "8-fold mirror" {
        if (y > values.grid.y) || (x > values.grid.x) || (y > x) do continue
      }
      append(&values.break_spots, [2]i32{x,y})
    }
  }
}

random_break_spots :: proc(values: ^Values) {
  for i in 0..<len(values.break_spots) {
    if rand.float32() < (1-values.breaks_percent) { // percentage to reject
      continue
    }
    val := (rand.float32() < 0.5) ? '-' : '|'
    x := values.break_spots[i].x
    y := values.break_spots[i].y
    raw_data(values.breaks[y])[x] = u8(val)

    if values.symmetry == "180 rotation" {
      raw_data(values.breaks[y*2 - y])[values.grid.x*2 - x] = u8(val)
    } else if values.symmetry == "4-fold mirror" {
      raw_data(values.breaks[values.grid.y*2 - y])[x] = u8(val)
      raw_data(values.breaks[y])[values.grid.x*2 - x] = u8(val)
      raw_data(values.breaks[values.grid.y*2 - y])[values.grid.x*2 - x] = u8(val)
    } else if values.symmetry == "8-fold mirror" {
      if values.grid.x != values.grid.y do continue
      raw_data(values.breaks[values.grid.y*2 - y])[x] = u8(val)
      raw_data(values.breaks[y])[values.grid.x*2 - x] = u8(val)
      raw_data(values.breaks[values.grid.y*2 - y])[values.grid.x*2 - x] = u8(val)
      other := (val == '-') ? '|' : '-'
      raw_data(values.breaks[x])[y] = u8(other)
      raw_data(values.breaks[x])[values.grid.y*2 - y] = u8(other)
      raw_data(values.breaks[values.grid.x*2 - x])[y] = u8(other)
      raw_data(values.breaks[values.grid.x*2 - x])[values.grid.y*2 - y] = u8(other)
    }
  }
}

get_cell :: proc(x, y: i32, values: ^Values) -> (c: Cell) {
  c.x = x % (values.grid.x*2)
  c.y = y % (values.grid.y*2)

  x1 := (c.x+1) % (values.grid.x*2)
  y1 := (c.y+1) % (values.grid.y*2)
  x0y0 := raw_data(values.breaks[c.y])[c.x]
  x1y0 := raw_data(values.breaks[c.y])[x1]
  x0y1 := raw_data(values.breaks[y1])[c.x]
  x1y1 := raw_data(values.breaks[y1])[x1]
  
  c.bn = (x0y0 == '-') || (x1y0 == '-')
  c.bs = (x0y1 == '-') || (x1y1 == '-')
  c.bw = (x0y0 == '|') || (x0y1 == '|')
  c.be = (x1y0 == '|') || (x1y1 == '|')

  // p1 and p2: line end points connecting left side to right side
  if (x+y) % 2 == 0 {
    c.p1.x = 0 // .    2
    c.p1.y = 1 //
    c.p2.x = 1 //
    c.p2.y = 0 // 1    .
  } else {
    c.p1.x = 0 // 1    .
    c.p1.y = 0 //
    c.p2.x = 1 //
    c.p2.y = 1 // .    2
  }
  c.type = u16(CellType.DIAGONAL)

  isCorner :: proc(p: [2]f32) -> bool {
    isXCorner := (p.x==0) || (p.x==1)
    isYCorner := (p.y==0) || (p.y==1)
    return isXCorner && isYCorner
  }
  
  moveCornerBySpacing :: proc(p: ^[2]f32, spacing: f32) {
    if (p.x == 0.0) do p.x = spacing
    if (p.x == 1.0) do p.x = 1 - spacing
    if (p.y == 0.0) do p.y = spacing
    if (p.y == 1.0) do p.y = 1 - spacing
  }
  
  // This will move p if the braid needs to go "under"
  underweave :: proc(c: ^Cell, x,y: i32, values: ^Values) {
    spacing := values.thickness/(2*math.sqrt_f32(2)) + values.gap/math.sqrt_f32(2);
    if isCorner(c.p1) {
      if (x % 2 != i32(c.p1.y) && y % 2 == i32(c.p1.x)) {
        moveCornerBySpacing(&c.p1, spacing)
      }
    }
    if isCorner(c.p2) {
      if (x % 2 != i32(c.p2.y) && y % 2 == i32(c.p2.x)) {
        moveCornerBySpacing(&c.p2, spacing)
      }
    }
  }

  // Move p1 and p2 if they're touching a breakpoint
  if (c.p1.x == 0 && c.bw) { c.p1.x = 0.5 }
  if (c.p1.y == 0 && c.bn) { c.p1.y = 0.5 }
  if (c.p1.y == 1 && c.bs) { c.p1.y = 0.5 }
  //if (c.p2.x == 0 && c.bw) { c.p2.x = 0.5 } // shouldn't happen
  //if (c.p1.x == 1 && c.be) { c.p1.x = 0.5 }
  if (c.p2.x == 1 && c.be) { c.p2.x = 0.5 }
  if (c.p2.y == 0 && c.bn) { c.p2.y = 0.5 }
  if (c.p2.y == 1 && c.bs) { c.p2.y = 0.5 }
  
  if (c.p1.x == 0.5) && ((c.p2.y == 0) || (c.p2.y == 1)) { c.type = u16(CellType.ELBOW) }
  if (c.p2.x == 0.5) && ((c.p1.y == 0) || (c.p1.y == 1)) { c.type = u16(CellType.ELBOW) }  
  if ((c.p1.y == 0) || (c.p1.y == 1)) && (c.p2.y == 0.5) { c.type = u16(CellType.ELBOW) }
  if (c.p1.y == 0.5) && ((c.p2.y == 0) || (c.p2.y == 1)) { c.type = u16(CellType.ELBOW) }

  if (c.p1.x == 0.5) && (c.p2.x == 0.5) { c.type = u16(CellType.VBAR) } // vertical bar
  if (c.p1.y == 0.5) && (c.p2.y == 0.5) { c.type = u16(CellType.HBAR) } // horizontal bar
  
  if (c.p1.y == 0.5) && (c.p2.x == 0.5) { c.type = u16(CellType.CORNER) }
  if (c.p1.x == 0.5) && (c.p2.y == 0.5) { c.type = u16(CellType.CORNER) }

  c.needsMiddlePoint = !isCorner(c.p1) || !isCorner(c.p2)
  shouldRoundCorners := (isCorner(c.p1) && !isCorner(c.p2)) || (isCorner(c.p2) && !isCorner(c.p1))
    
  underweave(&c, x, y, values)  

  return
}

go_up_down :: proc(a: i32, dir: i32, values: ^Values) -> i32 {
  grid_size := (values.grid.x*2)*(values.grid.y*2)
  W := values.grid.x*2
  ret := (a) + (dir * W) // dir is + to go down, - to go up
  if ret < 0 {
    ret += grid_size
  }
  if ret > grid_size {
    ret -= grid_size
  }
  return ret
}

go_left_right :: proc(a: i32, dir: i32, values: ^Values) -> i32 {
  W := values.grid.x*2
  x := a % W
  y := a / W
  return y * W + ((x + dir + W) % W)
}
  
scan_for_short_and_long_arcs :: proc(values: ^Values) {
  if len(values.cells) == 0 {
    for y in 0..<values.grid.y*2 {
      for x in 0..<values.grid.x*2 {
        append(&values.cells, get_cell(x, y, values))
      }
    }
  }
  change_to_short :: proc(#any_int a, b: int, values: ^Values) {
    if values.cells[b].type == u16(CellType.ELBOW) {
      values.cells[a].type = u16(CellType.SHORT_ARC)
      values.cells[b].type = u16(CellType.SHORT_ARC)      
    }
  }
  change_to_long :: proc(x, y: i32, xdir, ydir: i32, values: ^Values) {
    a := y * (values.grid.x*2) + x
    done_twice := 0
    if xdir != 0 {
      b := go_left_right(a, xdir, values)
      for ; values.cells[b].type == u16(CellType.HBAR); {
        done_twice += 1
        b = go_left_right(b, xdir, values)
      }
      if done_twice >= 2 && values.cells[b].type == u16(CellType.ELBOW) {
        values.cells[a].type = u16(CellType.LONG_ARC)
        tmp := go_left_right(a, xdir, values)
        values.cells[tmp].type = u16(CellType.BAR_REMOVED)
        values.cells[b].type = u16(CellType.LONG_ARC)
        tmp = go_left_right(b, -xdir, values)
        values.cells[tmp].type = u16(CellType.BAR_REMOVED)
      }
    } else if ydir != 0 {
      b := go_up_down(a, ydir, values)
      for ; values.cells[b].type == u16(CellType.VBAR); {
        done_twice += 1
        b = go_up_down(b, ydir, values)
      }
      if done_twice >= 2 && values.cells[b].type == u16(CellType.ELBOW) {
        values.cells[a].type = u16(CellType.LONG_ARC)
        tmp := go_up_down(a, ydir, values)
        values.cells[tmp].type = u16(CellType.BAR_REMOVED)
        values.cells[b].type = u16(CellType.LONG_ARC)
        tmp = go_up_down(b, -ydir, values)
        values.cells[tmp].type = u16(CellType.BAR_REMOVED)
      }
    }
  }
  // there are 8 types of elbows:
  // .     .  | . p2  . | p1    . | p1    . | .    p2 | .      . | .  p1  . | .     p2 |
  //          |         |         |         |         |          |          |          |
  //      p2  |         |      p2 |         | p1      | p1       |          |          |
  //          |         |         |         |         |          |          |          |
  // p1    .  | p1    . | .     . | .  p2 . | .     . | .     p2 | .     p2 | .  p1  . |
  //     1        2         3         4         5           6         7         8
  // TODO: this should have bounds checks or similar if border ever loops or doesn't exist or something
  for y in 0..<values.grid.y*2 {
    for x in 0..<values.grid.x*2 {
      a := y * (values.grid.x*2) + x
      c := values.cells[a]
      if c.type == u16(CellType.ELBOW) || c.type == u16(CellType.SHORT_ARC) || c.type == u16(CellType.LONG_ARC) {
        if c.p1.y > c.p2.y {        // 1, 2, 5, 8
          if c.p2.y == 0.5 {        // 1
            values.cells[a].elbow_type = 1
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_left_right(a, +1, values), values)
              change_to_long(x, y, 1, 0, values)
            }
          } else if c.p2.x == 0.5 { // 2
            values.cells[a].elbow_type = 2
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_up_down(a, -1, values), values)
              change_to_long(x, y, 0, -1, values)
            }
          } else if c.p1.y == 0.5 { // 5
            values.cells[a].elbow_type = 5
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_left_right(a, -1, values), values)
              change_to_long(x, y, -1, 0, values)
            }
          } else if c.p1.x == 0.5 { // 8
            values.cells[a].elbow_type = 8
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_up_down(a, +1, values), values)
              change_to_long(x, y, 0, 1, values)
            }
          }
        } else {                    // 3, 4, 6, 7
          if c.p2.y == 0.5 {        // 3
            values.cells[a].elbow_type = 3
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_left_right(a, +1, values), values)
              change_to_long(x, y, 1, 0, values)
            }
          } else if c.p2.x == 0.5 { // 4
            values.cells[a].elbow_type = 4
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_up_down(a, +1, values), values)
              change_to_long(x, y, 0, 1, values)
            }
          } else if c.p1.y == 0.5 { // 6
            values.cells[a].elbow_type = 6
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_left_right(a, -1, values), values)
              change_to_long(x, y, -1, 0, values)
            }
          } else if c.p1.x == 0.5 { // 7
            values.cells[a].elbow_type = 7
            if c.type == u16(CellType.ELBOW) {
              change_to_short(a, go_up_down(a, -1, values), values)
              change_to_long(x, y, 0, -1, values)
            }
          }
        }
      }
    }
  }
}

KnotPath :: struct {
  path: [^]([2]f32), // Vector2
  path_pts: int,
}

get_knot :: proc(values: ^Values, knot: ^[dynamic]KnotPath) {
  tmp_path : [dynamic]([2]f32)

  scan_for_short_and_long_arcs(values)
  
  for y in 0..<values.grid.y*2 {
    for x in 0..<values.grid.x*2 {
      c := values.cells[y * (values.grid.x*2) + x]
      xx := (f32(x)) * f32(values.grid_spacing)/2 + f32(values.margin.x)
      yy := (f32(y)) * f32(values.grid_spacing)/2 + f32(values.margin.y)

      p1a := c.p1
      p1b := c.p1
      p2a := c.p2
      p2b := c.p2
      pma := [?]f32{0.5, 0.5, 0.5, 0.5}
      pmb := [?]f32{0.5, 0.5, 0.5, 0.5}
      if c.type == u16(CellType.HBAR) {
        p1a.y -= values.thickness/2
        p1b.y += values.thickness/2   //              
        p2a.y -= values.thickness/2   // p1a  pma  p2a
        p2b.y += values.thickness/2   // p1b  pmb  p2b
        pma.y -= values.thickness/2   //
        pmb.y += values.thickness/2
      } else if c.type == u16(CellType.VBAR) {
        //  p1b  p1a      p2a p2b
        //  pmb  pma      pma pmb
        //  p2b  p2a      p1a p1b
        t1 := -values.thickness/2
        t2 := values.thickness/2
        if c.p1.y < c.p2.y {
          t1 = values.thickness/2
          t2 = -values.thickness/2
        }
        p1a.x += t1
        p1b.x += t2
        p2a.x += t1
        p2b.x += t2
        pma.x += t1
        pmb.x += t2
      } else if c.type == u16(CellType.CORNER) {
        if c.p1.x == 0 {
          // p1a      pma              p2a p2b
          // p1b  pmb           p1a    pma      
          //      p2b p2a       p1b        pmb
          p1a.y -= values.thickness/2
          p1b.y += values.thickness/2
          if c.p2.y == 0 { // 2nd case above (p2 on top)
            pma.x -= values.thickness/2
            pma.y -= values.thickness/2
            pmb.x += values.thickness/2
            pmb.y += values.thickness/2
            p2a.x -= values.thickness/2
            p2b.x += values.thickness/2
          } else { // 1st case above
            pma.x += values.thickness/2
            pma.y -= values.thickness/2
            pmb.x -= values.thickness/2
            pmb.y += values.thickness/2
            p2a.x += values.thickness/2
            p2b.x -= values.thickness/2
          }
        } else {
          // p1b p1a        pma     p2a
          //     pma p2a        pmb p2b
          // pmb     p2b    p1a p1b
          p2a.y -= values.thickness/2
          p2b.y += values.thickness/2
          if c.p1.y == 0 { // 1st case above (p1 on top)
            p1a.x += values.thickness/2
            p1b.x -= values.thickness/2
            pma.x += values.thickness/2
            pma.y -= values.thickness/2
            pmb.x -= values.thickness/2
            pmb.y += values.thickness/2
          } else {
            p1a.x -= values.thickness/2
            p1b.x += values.thickness/2
            pma.x -= values.thickness/2
            pma.y -= values.thickness/2
            pmb.x += values.thickness/2
            pmb.y += values.thickness/2
          }
        }
      } else if c.type == u16(CellType.DIAGONAL) {
        t1 := (values.thickness/2) / math.sqrt_f32(2)
        if c.p1.y < c.p2.y {
          //   p1a
          // p1b
          //       p2a
          //     p2b
          p1a.x += t1
          p1a.y -= t1
          p1b.x -= t1
          p1b.y += t1
          p2a.x += t1
          p2a.y -= t1
          p2b.x -= t1
          p2b.y += t1
        } else {
          //      p2a
          //       p2b
          // p1a
          //   p1b
          p1a.x -= t1
          p1a.y -= t1
          p1b.x += t1
          p1b.y += t1
          p2a.x -= t1
          p2a.y -= t1
          p2b.x += t1
          p2b.y += t1
        }
      } else { // CellType.ELBOW AND ARCS
        a := y * (values.grid.x*2) + x
        c := values.cells[a]

        // compare thickness to different c0-c9 pair distances
        elbs := ELBOWS
        if c.type == u16(CellType.SHORT_ARC) {
          elbs = SHORT_ARCS
        }
        if c.type == u16(CellType.LONG_ARC) {
          elbs = LONG_ARCS
        }
        i := 0
        c0 := elbs[0]
        c9 := elbs[9]
        prev_c0 := elbs[0]
        prev_c9 := elbs[9]
        t : f32 = 0.0
        for ; i < 5; i+=1 {
          c0 = elbs[i]
          c9 = elbs[9-i]
          dist := linalg.vector_length(c0.xy - c9.xy)
          prev_dist := linalg.vector_length(prev_c0.xy - prev_c9.xy)          
          if (values.thickness) < (dist/32) {
            prev_c0 = c0
            prev_c9 = c9
            continue
          }
          t = (((values.thickness) - (dist/32)) / ((prev_dist/32) - (dist/32)))
          break
        }

        t1 := (values.thickness/2) / math.sqrt_f32(2)
        flip_h :: proc(c: Cell, c0: ^[4]f32, c9: ^[4]f32, prev_c0: ^[4]f32, prev_c9: ^[4]f32) {
          if c.type == u16(CellType.LONG_ARC) {
            c0.x = 32-c0.x; c0.z = 64-c0.z; c9.x = 32-c9.x; c9.z = 64-c9.z
            prev_c0.x = 32-prev_c0.x; prev_c0.z = 64-prev_c0.z; prev_c9.x = 32-prev_c9.x; prev_c9.z = 64-prev_c9.z
          } else {
            c0.x = 32-c0.x; c0.z = 32-c0.z; c9.x = 32-c9.x; c9.z = 32-c9.z
            prev_c0.x = 32-prev_c0.x; prev_c0.z = 32-prev_c0.z; prev_c9.x = 32-prev_c9.x; prev_c9.z = 32-prev_c9.z
          }
        }
        flip_v :: proc(c: Cell, c0: ^[4]f32, c9: ^[4]f32, prev_c0: ^[4]f32, prev_c9: ^[4]f32) {
          c0.y = 32-c0.y; c0.w = 32-c0.w; c9.y = 32-c9.y; c9.w = 32-c9.w
          prev_c0.y = 32-prev_c0.y; prev_c0.w = 32-prev_c0.w; prev_c9.y = 32-prev_c9.y; prev_c9.w = 32-prev_c9.w
        }
        // there are 8 types of elbows:
        // .     .  | . p2  . | p1    . | p1    . | .    p2 | .      . | .  p1  . | .     p2 |
        //          |         |         |         |         |          |          |          |
        //      p2  |         |      p2 |         | p1      | p1       |          |          |
        //          |         |         |         |         |          |          |          |
        // p1    .  | p1    . | .     . | .  p2 . | .     . | .     p2 | .     p2 | .  p1  . |
        //     1        2         3         4         5           6         7         8
        // here pma and pmb are not middlepoints, but control points for bezier curve
        if c.type == u16(CellType.ELBOW) || c.type == u16(CellType.SHORT_ARC) || c.type == u16(CellType.LONG_ARC) {
          if c.elbow_type == 1 {
            p1a.x -= t1
            p1a.y -= t1
            p1b.x += t1
            p1b.y += t1
            p2a.y -= values.thickness/2
            p2b.y += values.thickness/2
            // flip_vert for c0c9
            flip_v(c, &c0, &c9, &prev_c0, &prev_c9)
            pma = linalg.lerp(c0, prev_c0, t) / 32
            pmb = linalg.lerp(c9, prev_c9, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              p2a.x = 2; p2b.x = 2
            }
          } else if c.elbow_type == 2 {
            p1a.x -= t1
            p1a.y -= t1
            p1b.x += t1
            p1b.y += t1
            p2a.x -= values.thickness/2
            p2b.x += values.thickness/2
            // swap x-y then flip_vert for c0c9
            c0.xyzw = c0.yxwz; c9.xyzw = c9.yxwz
            prev_c0.xyzw = prev_c0.yxwz; prev_c9.xyzw = prev_c9.yxwz
            flip_v(c, &c0, &c9, &prev_c0, &prev_c9)
            pma = linalg.lerp(c9, prev_c9, t) / 32
            pmb = linalg.lerp(c0, prev_c0, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              p2a.y = -1; p2b.y = -1
            }
          } else if c.elbow_type == 3 {
            p1a.x += t1
            p1a.y -= t1
            p1b.x -= t1
            p1b.y += t1
            p2a.y -= values.thickness/2
            p2b.y += values.thickness/2
            // just change bottom and top curve points c0 to c9
            pma = linalg.lerp(c9, prev_c9, t) / 32
            pmb = linalg.lerp(c0, prev_c0, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              p2a.x = 2; p2b.x = 2
            }
          } else if c.elbow_type == 4 {
            p1a.x += t1
            p1a.y -= t1
            p1b.x -= t1
            p1b.y += t1
            p2a.x += values.thickness/2
            p2b.x -= values.thickness/2
            // swap x-y
            c0.xyzw = c0.yxwz; c9.xyzw = c9.yxwz
            prev_c0.xyzw = prev_c0.yxwz; prev_c9.xyzw = prev_c9.yxwz
            pma = linalg.lerp(c0, prev_c0, t) / 32
            pmb = linalg.lerp(c9, prev_c9, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              p2a.y = 2; p2b.y = 2
            }
          } else if c.elbow_type == 5 {
            p1a.y -= values.thickness/2
            p1b.y += values.thickness/2
            p2a.x -= t1
            p2a.y -= t1
            p2b.x += t1
            p2b.y += t1
            // flip_horz for c0c9
            flip_h(c, &c0, &c9, &prev_c0, &prev_c9)
            pma = linalg.lerp(c9, prev_c9, t) / 32
            pmb = linalg.lerp(c0, prev_c0, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              pma.z = pma.z - 1
              pmb.z = pmb.z - 1
              p1a.x = -1; p1b.x = -1
              pmb.xyzw = pmb.zwxy
              pma.xyzw = pma.zwxy
            }
          } else if c.elbow_type == 6 {
            p1a.y -= values.thickness/2
            p1b.y += values.thickness/2
            p2a.x += t1
            p2a.y -= t1
            p2b.x -= t1
            p2b.y += t1
            // flip_ vert and horz for c0c9
            flip_h(c, &c0, &c9, &prev_c0, &prev_c9)
            flip_v(c, &c0, &c9, &prev_c0, &prev_c9)
            pma = linalg.lerp(c0, prev_c0, t) / 32
            pmb = linalg.lerp(c9, prev_c9, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              pma.z = pma.z - 1
              pmb.z = pmb.z - 1
              p1a.x = -1; p1b.x = -1
              pmb.xyzw = pmb.zwxy
              pma.xyzw = pma.zwxy
            }
          } else if c.elbow_type == 7 {
            p1a.x += values.thickness/2
            p1b.x -= values.thickness/2
            p2a.x += t1
            p2a.y -= t1
            p2b.x -= t1
            p2b.y += t1
            // flip_v and h, swap x-y
            flip_h(c, &c0, &c9, &prev_c0, &prev_c9)
            flip_v(c, &c0, &c9, &prev_c0, &prev_c9)
            c0.xyzw = c0.yxwz; c9.xyzw = c9.yxwz
            prev_c0.xyzw = prev_c0.yxwz; prev_c9.xyzw = prev_c9.yxwz
            pma = linalg.lerp(c9, prev_c9, t) / 32
            pmb = linalg.lerp(c0, prev_c0, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              pma.w = pma.w - 1
              pmb.w = pmb.w - 1
              p1a.y = -1; p1b.y = -1
              pmb.xyzw = pmb.zwxy
              pma.xyzw = pma.zwxy
            }
          } else if c.elbow_type == 8 {
            p1a.x -= values.thickness/2
            p1b.x += values.thickness/2
            p2a.x -= t1
            p2a.y -= t1
            p2b.x += t1
            p2b.y += t1
            // flip_vert, swap x-y
            flip_v(c, &c0, &c9, &prev_c0, &prev_c9)
            c0.xyzw = c0.yxwz; c9.xyzw = c9.yxwz
            prev_c0.xyzw = prev_c0.yxwz; prev_c9.xyzw = prev_c9.yxwz
            pma = linalg.lerp(c0, prev_c0, t) / 32
            pmb = linalg.lerp(c9, prev_c9, t) / 32
            if c.type == u16(CellType.LONG_ARC) {
              p1a.y = 2; p1b.y = 2
              pmb.xyzw = pmb.zwxy
              pma.xyzw = pma.zwxy
            }
          }
        }
      }

      if c.type == u16(CellType.ELBOW) || c.type == u16(CellType.SHORT_ARC) || c.type == u16(CellType.LONG_ARC) {
        append(&tmp_path, [2]f32{xx + p1a.x * f32(values.grid_spacing)/2,
                                 yy + p1a.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p1b.x * f32(values.grid_spacing)/2,
                                 yy + p1b.y * f32(values.grid_spacing)/2})
        for i in 0..<values.elbow_segments {
          tc := get_spline_pt_bezier_cubic(p1a.xy, pmb.xy, pmb.zw, p2a.xy, f32(i)/f32(values.elbow_segments))
          bc := get_spline_pt_bezier_cubic(p1b.xy, pma.xy, pma.zw, p2b.xy, f32(i)/f32(values.elbow_segments))
          append(&tmp_path, [2]f32{xx + tc.x * f32(values.grid_spacing)/2,
                                   yy + tc.y * f32(values.grid_spacing)/2})
          append(&tmp_path, [2]f32{xx + bc.x * f32(values.grid_spacing)/2,
                                   yy + bc.y * f32(values.grid_spacing)/2})
        }
        append(&tmp_path, [2]f32{xx + p2a.x * f32(values.grid_spacing)/2,
                                 yy + p2a.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p2b.x * f32(values.grid_spacing)/2,
                                 yy + p2b.y * f32(values.grid_spacing)/2})
      } else if c.needsMiddlePoint {
        append(&tmp_path, [2]f32{xx + p1a.x * f32(values.grid_spacing)/2,
                                 yy + p1a.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p1b.x * f32(values.grid_spacing)/2,
                                 yy + p1b.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + pma.x * f32(values.grid_spacing)/2,
                                 yy + pma.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + pmb.x * f32(values.grid_spacing)/2,
                                 yy + pmb.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p2a.x * f32(values.grid_spacing)/2,
                                 yy + p2a.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p2b.x * f32(values.grid_spacing)/2,
                                 yy + p2b.y * f32(values.grid_spacing)/2})
      } else {
        append(&tmp_path, [2]f32{xx + p1a.x * f32(values.grid_spacing)/2,
                                 yy + p1a.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p1b.x * f32(values.grid_spacing)/2,
                                 yy + p1b.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p2a.x * f32(values.grid_spacing)/2,
                                 yy + p2a.y * f32(values.grid_spacing)/2})
        append(&tmp_path, [2]f32{xx + p2b.x * f32(values.grid_spacing)/2,
                                 yy + p2b.y * f32(values.grid_spacing)/2})
      }

      k : KnotPath
      k.path_pts = len(tmp_path)
      k.path = make([^]([2]f32), k.path_pts)
      for p,idx in tmp_path {
        k.path[idx] = p
      }
      append(knot, k)
      clear(&tmp_path)
    }
  }
  delete(tmp_path)

  if values.ringify {
    // put every row onto a circle/ring making each row/ring smaller and smaller as the rows go down
    W := f32(values.grid.x * values.grid_spacing)
    H := f32(values.grid.y * values.grid_spacing)
    center := [2]f32{H + f32(values.margin.x), H + f32(values.margin.y)}
    
    for k in knot {
      for i in 0..<k.path_pts {
        ang := (k.path[i].x / W) * (2*math.PI) // .x controls angle
        r   := (H - k.path[i].y)/2 + (H/2)     // .y controls radius (note: innner blank part is just half H)
        xx  := r * math.cos(ang)
        yy  := r * math.sin(ang)
        
        k.path[i] = [2]f32{xx + center.x, yy + center.y}
      }
    }
  }

  return
}
/* Celtic Knots:4 ends here */
