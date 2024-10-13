/* [[file:../../nubs.org::*Celtic Knots][Celtic Knots:3]] */
package knots_cmd

/*
  Something like below python script can import generated knot as a mesh into Blender
  ---
  import bpy
  import bpy.path
  import subprocess

  # TODO: make ui elements in blender to control below values
  gridx = 80
  gridy = 5
  grid_spacing = 30
  thickness = 0.7
  gap = 0.2
  symmetry = "None"
  elbow_segments = 4
  ringify = 1
  border_x = "-border-x"
  border_y = ""
  breaks_percent = 0.5

  args = "%s %s -grid-spacing:%s -thickness:%s -gap:%s -symmetry:%s -elbow-segments:%s -ringify:%s %s %s -breaks-percent:%s" % (gridx, gridy, grid_spacing, thickness, gap, symmetry, elbow_segments, ringify, border_x, border_y, breaks_percent)
  ret = subprocess.run([bpy.path.abspath("//") + "src\\celtic_knots\\knots.exe"] + args.split(), shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

  # Define vertices, edges, faces for a mesh
  lines = ret.stdout.decode("utf-8")
  print(lines)
  vertices = []
  edges = []
  faces = []
  is_start = 2
  prev_prev = []
  prev = []
  idx = 0
  print(lines)
  for line in lines.split("\n"):
  if line == "":
  break
  if line == "-":
  is_start = 2
  continue
  vals = line.split()
  vertices.append((float(vals[0]), float(vals[1]), 0))
  if is_start > 0:
  is_start -= 1
  idx += 1
  if is_start == 1:
  prev_prev = vals
  continue
  if is_start == 0:
  prev = vals
  continue
  else:
  if is_start == 0:
  is_start -= 1
  edges.append((idx-2, idx-1))
  edges.append((idx-1, idx))
  edges.append((idx, idx-2))
  faces.append((idx-2, idx-1, idx))
  else:
  edges.append((idx-1, idx))
  edges.append((idx, idx-2))
  faces.append((idx-2, idx-1, idx))
  idx += 1

  # Create a new mesh object
  mesh = bpy.data.meshes.new("MyMesh")

  # Assign the vertices and edges to the mesh object
  mesh.from_pydata(vertices, edges, faces)
  mesh.update()

  new_object = bpy.data.objects.new('new_object', mesh)
  new_collection = bpy.data.collections.new('new_collection')
  bpy.context.scene.collection.children.link(new_collection)
  new_collection.objects.link(new_object)

  */

import "core:os"
import "core:fmt"
import "core:flags"
import knots "../"

main :: proc() {
	Options :: struct {
		grid_x: i32 `args:"pos=0,required" usage:"grid width."`,
		grid_y: i32 `args:"pos=1,required" usage:"grid height."`,
		grid_spacing: i32 `usage:"how big each grid cell is."`,
		thickness: f32 `usage:"thickness of knot [0..1]."`,
		gap: f32 `usage:"gap when knot goes under [0..1]."`,
		symmetry: string `usage:"None | 180 rotation | 4-fold mirror | 8-fold mirror."`,
		elbow_segments: i32 `usage:"segments used for rounded elbow corners."`,
		border_x: bool `usage:"loop around horizontally."`,
		border_y: bool `usage:"loop around vertically."`,
		breaks_percent: f32 `usage:"percentage of random breaks added."`,
		ringify: bool `usage:"turn grid into a ring."`,
	}
	opt: Options
	style : flags.Parsing_Style = .Odin

	flags.parse_or_exit(&opt, os.args, style)

	values : knots.Values
	values.grid = [?]i32{opt.grid_x,opt.grid_y}
	values.grid_spacing = 80
	values.rounding = 0.80  // unused
	values.thickness = 0.50
	values.gap = .07
	values.symmetry = "None"
	values.elbow_segments = 4
	values.show_breaks = false
	values.breaks_percent = 0.5
	if opt.grid_spacing != 0 {
		values.grid_spacing = opt.grid_spacing
	}
	if opt.thickness != 0 {
		values.thickness = opt.thickness
	}
	if opt.gap != 0 {
		values.gap = opt.gap
	}
	if opt.symmetry != "" {
		values.symmetry = opt.symmetry
	}
	if opt.elbow_segments != 0 {
		values.elbow_segments = opt.elbow_segments
	}
	if opt.border_x != false {
		values.border_x = opt.border_x
	}
	if opt.border_y != false {
		values.border_y = opt.border_y
	}
	if opt.breaks_percent != 0 {
		values.breaks_percent = opt.breaks_percent
	}
	if opt.ringify != false {
		values.ringify = opt.ringify
	}
	
	knots.alloc_breaks(&values); defer knots.clean_breaks(&values)
	knots.random_break_spots(&values)

	knot : [dynamic]knots.KnotPath; defer delete(knot)
	knots.get_knot(&values, &knot)

	for k in knot {
		for i in 0..<k.path_pts {
			fmt.printf("%f %f\n", k.path[i].x, k.path[i].y)
		}
		fmt.println("-")
	}
}
/* Celtic Knots:3 ends here */
