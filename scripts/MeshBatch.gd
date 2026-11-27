extends RefCounted
class_name MeshBatch

# Shared unit primitives reused for SurfaceTool.append_from() batching
static var _unit_box: BoxMesh
static var _unit_plane: PlaneMesh
static var _unit_cyl: CylinderMesh
static var _unit_cyl_smooth: CylinderMesh
static var _unit_sphere: SphereMesh

var _batches: Dictionary = {} # Material -> SurfaceTool

static func _ensure_units() -> void:
	if _unit_box != null:
		return
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE

	_unit_plane = PlaneMesh.new()
	_unit_plane.size = Vector2.ONE

	_unit_cyl = CylinderMesh.new()
	_unit_cyl.top_radius = 0.5
	_unit_cyl.bottom_radius = 0.5
	_unit_cyl.height = 1.0
	_unit_cyl.radial_segments = 12
	_unit_cyl.rings = 1

	_unit_cyl_smooth = CylinderMesh.new()
	_unit_cyl_smooth.top_radius = 0.5
	_unit_cyl_smooth.bottom_radius = 0.5
	_unit_cyl_smooth.height = 1.0
	_unit_cyl_smooth.radial_segments = 48
	_unit_cyl_smooth.rings = 1

	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 0.5
	_unit_sphere.height = 1.0
	_unit_sphere.radial_segments = 14
	_unit_sphere.rings = 8

func _get_st(mat: Material) -> SurfaceTool:
	_ensure_units()
	if _batches.has(mat):
		return _batches[mat]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	_batches[mat] = st
	return st

func add_box(pos: Vector3, sz: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	_ensure_units()
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(sz)
	_get_st(mat).append_from(_unit_box, 0, Transform3D(b, pos))

func add_plane_xz(pos: Vector3, sz_xz: Vector2, mat: Material, rot_y_rad: float = 0.0) -> void:
	_ensure_units()
	var b := Basis(Vector3.UP, rot_y_rad).scaled(Vector3(sz_xz.x, 1.0, sz_xz.y))
	_get_st(mat).append_from(_unit_plane, 0, Transform3D(b, pos))

func add_cylinder(pos: Vector3, radius: float, height: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO, smooth: bool = false) -> void:
	_ensure_units()
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(Vector3(radius * 2.0, height, radius * 2.0))
	var src := _unit_cyl_smooth if smooth else _unit_cyl
	_get_st(mat).append_from(src, 0, Transform3D(b, pos))

func add_tapered_cylinder(pos: Vector3, top_r: float, bot_r: float, height: float, mat: Material, segs: int = 12) -> void:
	_ensure_units()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	_get_st(mat).append_from(cm, 0, Transform3D(Basis.IDENTITY, pos))

func add_sphere(pos: Vector3, radius_xz: float, height: float, mat: Material) -> void:
	_ensure_units()
	var b := Basis.IDENTITY.scaled(Vector3(radius_xz * 2.0, height, radius_xz * 2.0))
	_get_st(mat).append_from(_unit_sphere, 0, Transform3D(b, pos))

func add_quad_up(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, mat: Material) -> void:
	# Godot front-face winding for +Y upward normal: (v1-v0).cross(v2-v0).y <= 0
	var st := _get_st(mat)
	st.set_normal(Vector3.UP)
	var n := (p1 - p0).cross(p2 - p0)
	if n.y <= 0.0:
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p0)
		st.add_vertex(p2)
		st.add_vertex(p3)
	else:
		st.add_vertex(p0)
		st.add_vertex(p2)
		st.add_vertex(p1)
		st.add_vertex(p0)
		st.add_vertex(p3)
		st.add_vertex(p2)

func commit_multi_surface() -> ArrayMesh:
	var arr := ArrayMesh.new()
	for mat in _batches.keys():
		var st: SurfaceTool = _batches[mat]
		st.commit(arr)
	return arr

func commit_as_nodes(parent: Node3D, cast_shadows: bool) -> void:
	for mat in _batches.keys():
		var st: SurfaceTool = _batches[mat]
		var arr := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = arr
		if not cast_shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
