use std::os::raw::c_int;
use std::sync::Mutex;

const COLS: usize = 100; // terminal columns
const ROWS: usize = 48;  // terminal rows
const RAMPS: &[u8; 9] = b".:-=+*#%@"; // brightness ramp (dim to bright)

#[derive(Clone, Copy, Debug)]
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    const fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }
}

struct Polyhedron {
    name: &'static str,
    type_label: &'static str,
    faces: i32,
    verts: Vec<Vec3>,
    edges: Vec<(usize, usize)>,
}

struct State {
    shapes: Vec<Polyhedron>,
    current_shape: usize,
    render_mode: i32, // 0: single, 1: dual comparison, 2: gallery
    auto_rotate: bool,
    auto_cycle: bool,
    rot_speed: f32,
    rot_x: f32,
    rot_y: f32,
    rot_z: f32,
    cycle_timer: f32,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

extern "C" {
    fn emscripten_set_main_loop(f: extern "C" fn(), fps: c_int, simulate_infinite_loop: c_int);
    fn push_terminal_frame(ptr: *const u8, len: usize);
}

// Helper to calculate edges for regular / semi-regular polyhedra by minimum distance
fn compute_edges_by_distance(poly: &mut Polyhedron, tolerance_factor: f32) {
    if poly.verts.is_empty() {
        return;
    }
    let mut min_dist_sq = 1e9f32;
    let n = poly.verts.len();
    for i in 0..n {
        for j in (i + 1)..n {
            let dx = poly.verts[i].x - poly.verts[j].x;
            let dy = poly.verts[i].y - poly.verts[j].y;
            let dz = poly.verts[i].z - poly.verts[j].z;
            let d2 = dx * dx + dy * dy + dz * dz;
            if d2 > 1e-4 && d2 < min_dist_sq {
                min_dist_sq = d2;
            }
        }
    }
    let max_dist_sq = min_dist_sq * tolerance_factor * tolerance_factor;
    for i in 0..n {
        for j in (i + 1)..n {
            let dx = poly.verts[i].x - poly.verts[j].x;
            let dy = poly.verts[i].y - poly.verts[j].y;
            let dz = poly.verts[i].z - poly.verts[j].z;
            let d2 = dx * dx + dy * dy + dz * dz;
            if d2 <= max_dist_sq {
                poly.edges.push((i, j));
            }
        }
    }
}

fn init_shapes() -> Vec<Polyhedron> {
    let mut shapes = Vec::new();
    let phi = (1.0f32 + 5.0f32.sqrt()) * 0.5f32; // Golden ratio ~ 1.618034

    // 1. Tetrahedron (Platonic solid: 4 Vertices, 6 Edges, 4 Faces)
    {
        let s = 1.30f32;
        shapes.push(Polyhedron {
            name: "TETRAHEDRON",
            type_label: "PLATONIC SOLID",
            faces: 4,
            verts: vec![
                Vec3::new(s, s, s),
                Vec3::new(s, -s, -s),
                Vec3::new(-s, s, -s),
                Vec3::new(-s, -s, s),
            ],
            edges: vec![
                (0, 1), (0, 2), (0, 3),
                (1, 2), (1, 3), (2, 3),
            ],
        });
    }

    // 2. Cube / Hexahedron (Platonic solid: 8 Vertices, 12 Edges, 6 Faces)
    {
        let s = 1.00f32;
        shapes.push(Polyhedron {
            name: "HEXAHEDRON (CUBE)",
            type_label: "PLATONIC SOLID",
            faces: 6,
            verts: vec![
                Vec3::new(-s, -s, -s), Vec3::new(s, -s, -s), Vec3::new(s, s, -s), Vec3::new(-s, s, -s),
                Vec3::new(-s, -s, s), Vec3::new(s, -s, s), Vec3::new(s, s, s), Vec3::new(-s, s, s),
            ],
            edges: vec![
                (0, 1), (1, 2), (2, 3), (3, 0),
                (4, 5), (5, 6), (6, 7), (7, 4),
                (0, 4), (1, 5), (2, 6), (3, 7),
            ],
        });
    }

    // 3. Octahedron (Platonic solid: 6 Vertices, 12 Edges, 8 Faces)
    {
        let s = 1.50f32;
        shapes.push(Polyhedron {
            name: "OCTAHEDRON",
            type_label: "PLATONIC SOLID",
            faces: 8,
            verts: vec![
                Vec3::new(s, 0.0, 0.0), Vec3::new(-s, 0.0, 0.0),
                Vec3::new(0.0, s, 0.0), Vec3::new(0.0, -s, 0.0),
                Vec3::new(0.0, 0.0, s), Vec3::new(0.0, 0.0, -s),
            ],
            edges: vec![
                (0, 2), (0, 3), (0, 4), (0, 5),
                (1, 2), (1, 3), (1, 4), (1, 5),
                (2, 4), (4, 3), (3, 5), (5, 2),
            ],
        });
    }

    // 4. Dodecahedron (Platonic solid: 20 Vertices, 30 Edges, 12 Faces)
    {
        let s = 0.85f32;
        let mut p = Polyhedron {
            name: "DODECAHEDRON",
            type_label: "PLATONIC SOLID",
            faces: 12,
            verts: Vec::new(),
            edges: Vec::new(),
        };
        // 8 vertices of cube
        for &x in &[-s, s] {
            for &y in &[-s, s] {
                for &z in &[-s, s] {
                    p.verts.push(Vec3::new(x, y, z));
                }
            }
        }
        // 12 vertices on coordinate planes
        for &y in &[-s / phi, s / phi] {
            for &z in &[-s * phi, s * phi] {
                p.verts.push(Vec3::new(0.0, y, z));
            }
        }
        for &x in &[-s / phi, s / phi] {
            for &y in &[-s * phi, s * phi] {
                p.verts.push(Vec3::new(x, y, 0.0));
            }
        }
        for &x in &[-s * phi, s * phi] {
            for &z in &[-s / phi, s / phi] {
                p.verts.push(Vec3::new(x, 0.0, z));
            }
        }
        compute_edges_by_distance(&mut p, 1.05);
        shapes.push(p);
    }

    // 5. Icosahedron (Platonic solid: 12 Vertices, 30 Edges, 20 Faces)
    {
        let s = 0.95f32;
        let mut p = Polyhedron {
            name: "ICOSAHEDRON",
            type_label: "PLATONIC SOLID",
            faces: 20,
            verts: Vec::new(),
            edges: Vec::new(),
        };
        for &y in &[-s, s] {
            for &z in &[-s * phi, s * phi] {
                p.verts.push(Vec3::new(0.0, y, z));
            }
        }
        for &x in &[-s, s] {
            for &y in &[-s * phi, s * phi] {
                p.verts.push(Vec3::new(x, y, 0.0));
            }
        }
        for &x in &[-s * phi, s * phi] {
            for &z in &[-s, s] {
                p.verts.push(Vec3::new(x, 0.0, z));
            }
        }
        compute_edges_by_distance(&mut p, 1.05);
        shapes.push(p);
    }

    // 6. Cuboctahedron (Archimedean solid: 12 Vertices, 24 Edges, 14 Faces)
    {
        let s = 1.15f32;
        let mut p = Polyhedron {
            name: "CUBOCTAHEDRON",
            type_label: "ARCHIMEDEAN SOLID",
            faces: 14,
            verts: vec![
                Vec3::new(s, s, 0.0), Vec3::new(s, -s, 0.0), Vec3::new(-s, s, 0.0), Vec3::new(-s, -s, 0.0),
                Vec3::new(s, 0.0, s), Vec3::new(s, 0.0, -s), Vec3::new(-s, 0.0, s), Vec3::new(-s, 0.0, -s),
                Vec3::new(0.0, s, s), Vec3::new(0.0, s, -s), Vec3::new(0.0, -s, s), Vec3::new(0.0, -s, -s),
            ],
            edges: Vec::new(),
        };
        compute_edges_by_distance(&mut p, 1.05);
        shapes.push(p);
    }

    // 7. Stella Octangula (Kepler's Star Polyhedron: 8 Vertices, 24 Edges, 8 Faces)
    {
        let s = 1.25f32;
        shapes.push(Polyhedron {
            name: "STELLA OCTANGULA",
            type_label: "KEPLER STAR POLYHEDRON",
            faces: 8,
            verts: vec![
                // Tetrahedron A
                Vec3::new(s, s, s), Vec3::new(s, -s, -s), Vec3::new(-s, s, -s), Vec3::new(-s, -s, s),
                // Tetrahedron B
                Vec3::new(-s, -s, -s), Vec3::new(-s, s, s), Vec3::new(s, -s, s), Vec3::new(s, s, -s),
            ],
            edges: vec![
                // Tet A edges
                (0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3),
                // Tet B edges
                (4, 5), (4, 6), (4, 7), (5, 6), (5, 7), (6, 7),
            ],
        });
    }

    shapes
}

// 3D 3-axis Euler rotation
fn rotate_point(v: &mut Vec3, ax: f32, ay: f32, az: f32) {
    // Rotate Y
    let cy = ay.cos();
    let sy = ay.sin();
    let x1 = cy * v.x + sy * v.z;
    let z1 = -sy * v.x + cy * v.z;
    let y1 = v.y;

    // Rotate X
    let cx = ax.cos();
    let sx = ax.sin();
    let y2 = cx * y1 - sx * z1;
    let z2 = sx * y1 + cx * z1;
    let x2 = x1;

    // Rotate Z
    let cz = az.cos();
    let sz = az.sin();
    v.x = cz * x2 - sz * y2;
    v.y = sz * x2 + cz * y2;
    v.z = z2;
}

// 3D Perspective Projection
fn project_point(
    v: Vec3,
    offset_x: f32,
    offset_y: f32,
    scale: f32,
    px: &mut i32,
    py: &mut i32,
    depth_z: &mut f32,
) -> bool {
    let camera_z = v.z + 3.2;
    if camera_z <= 0.1 {
        return false;
    }
    *depth_z = camera_z;
    let factor = scale / camera_z;
    *px = ((v.x * factor + offset_x + 1.0) * COLS as f32 * 0.5) as i32;
    *py = ((-v.y * factor * 0.95 + offset_y + 1.0) * ROWS as f32 * 0.5) as i32;
    true
}

// Bresenham's line algorithm with depth buffer and brightness ramp shading
fn draw_line_depth(
    buf: &mut [u8; COLS * ROWS],
    zbuf: &mut [f32; COLS * ROWS],
    x0: i32,
    y0: i32,
    z0: f32,
    x1: i32,
    y1: i32,
    z1: f32,
    forced_ch: u8,
) {
    let dx = (x1 - x0).abs();
    let sx = if x0 < x1 { 1 } else { -1 };
    let dy = -(y1 - y0).abs();
    let sy = if y0 < y1 { 1 } else { -1 };
    let mut err = dx + dy;

    let mut total_dist = ((x1 - x0) as f32).hypot((y1 - y0) as f32);
    if total_dist < 1.0 {
        total_dist = 1.0;
    }

    let mut cur_x = x0;
    let mut cur_y = y0;
    loop {
        if cur_x >= 0 && cur_x < COLS as i32 && cur_y >= 0 && cur_y < ROWS as i32 {
            let traveled = ((cur_x - x0) as f32).hypot((cur_y - y0) as f32);
            let t = (traveled / total_dist).clamp(0.0, 1.0);
            let z = z0 + t * (z1 - z0);

            let idx = (cur_y * COLS as i32 + cur_x) as usize;
            if z < zbuf[idx] {
                zbuf[idx] = z;
                if forced_ch != 0 {
                    buf[idx] = forced_ch;
                } else {
                    // Depth brightness ramp: 1/z
                    let brightness = (3.4 / z - 0.65) / 0.85;
                    let mut ramp_idx = (brightness * 8.0) as i32;
                    if ramp_idx < 0 {
                        ramp_idx = 0;
                    }
                    if ramp_idx > 8 {
                        ramp_idx = 8;
                    }
                    buf[idx] = RAMPS[ramp_idx as usize];
                }
            }
        }
        if cur_x == x1 && cur_y == y1 {
            break;
        }
        let e2 = 2 * err;
        if e2 >= dy {
            err += dy;
            cur_x += sx;
        }
        if e2 <= dx {
            err += dx;
            cur_y += sy;
        }
    }
}

// Draw vertex point marker
fn draw_vertex_point(
    buf: &mut [u8; COLS * ROWS],
    zbuf: &mut [f32; COLS * ROWS],
    px: i32,
    py: i32,
    z: f32,
) {
    if px >= 0 && px < COLS as i32 && py >= 0 && py < ROWS as i32 {
        let idx = (py * COLS as i32 + px) as usize;
        if z - 0.02 <= zbuf[idx] {
            zbuf[idx] = z - 0.02;
            buf[idx] = b'@';
        }
    }
}

// Text printing onto terminal buffer
fn draw_string(buf: &mut [u8; COLS * ROWS], x: i32, y: i32, s: &str) {
    if y < 0 || y >= ROWS as i32 {
        return;
    }
    for (i, b) in s.bytes().enumerate() {
        let px = x + i as i32;
        if px >= 0 && px < COLS as i32 {
            buf[(y * COLS as i32 + px) as usize] = b;
        }
    }
}

#[derive(Clone, Copy)]
struct ProjV {
    px: i32,
    py: i32,
    z: f32,
    ok: bool,
}

// Draw a single polyhedron in the viewport
fn render_polyhedron(
    buf: &mut [u8; COLS * ROWS],
    zbuf: &mut [f32; COLS * ROWS],
    poly: &Polyhedron,
    off_x: f32,
    off_y: f32,
    scale: f32,
    ax: f32,
    ay: f32,
    az: f32,
    forced_ch: u8,
) {
    let mut proj = Vec::with_capacity(poly.verts.len());
    for v_orig in &poly.verts {
        let mut v = *v_orig;
        rotate_point(&mut v, ax, ay, az);
        let mut px = 0;
        let mut py = 0;
        let mut z = 0.0;
        let ok = project_point(v, off_x, off_y, scale, &mut px, &mut py, &mut z);
        proj.push(ProjV { px, py, z, ok });
    }

    // Draw all edges
    for &(i0, i1) in &poly.edges {
        let p0 = proj[i0];
        let p1 = proj[i1];
        if p0.ok && p1.ok {
            draw_line_depth(buf, zbuf, p0.px, p0.py, p0.z, p1.px, p1.py, p1.z, forced_ch);
        }
    }

    // Draw vertices
    for p in &proj {
        if p.ok {
            draw_vertex_point(buf, zbuf, p.px, p.py, p.z);
        }
    }
}

extern "C" fn main_loop() {
    let mut guard = match STATE.lock() {
        Ok(g) => g,
        Err(_) => return,
    };
    let state = match guard.as_mut() {
        Some(s) => s,
        None => return,
    };

    // Clear frame and depth buffer
    let mut buf = [b' '; COLS * ROWS];
    let mut zbuf = [1e9f32; COLS * ROWS];

    // Advance rotation animation
    if state.auto_rotate {
        state.rot_y += 0.018 * state.rot_speed;
        state.rot_x += 0.012 * state.rot_speed;
        state.rot_z += 0.007 * state.rot_speed;
    }

    // Handle auto cycling through shapes
    if state.auto_cycle {
        state.cycle_timer += 0.016;
        if state.cycle_timer >= 4.0 {
            state.cycle_timer = 0.0;
            state.current_shape = (state.current_shape + 1) % state.shapes.len();
        }
    }

    // Header UI
    let mut header_border = String::with_capacity(COLS);
    header_border.push('+');
    for _ in 0..(COLS - 2) {
        header_border.push('-');
    }
    header_border.push('+');
    draw_string(&mut buf, 0, 0, &header_border);

    let title_bar = format!(
        "| POLYWA :: 70s CRT 3D POLYHEDRA TERMINAL  [AUTO-ROT: {:3} | SPEED: {:.1}x | CYCLE: {:3}] |",
        if state.auto_rotate { "ON " } else { "OFF" },
        state.rot_speed,
        if state.auto_cycle { "ON " } else { "OFF" }
    );
    draw_string(&mut buf, 0, 1, &title_bar);
    draw_string(&mut buf, 0, 2, &header_border);

    // Render Mode Selection
    if state.render_mode == 0 {
        // Mode 0: Single Large Polyhedron Centered
        if state.current_shape < state.shapes.len() {
            render_polyhedron(
                &mut buf,
                &mut zbuf,
                &state.shapes[state.current_shape],
                0.0,
                0.0,
                1.45,
                state.rot_x,
                state.rot_y,
                state.rot_z,
                0,
            );
        }
    } else if state.render_mode == 1 {
        // Mode 1: Dual comparison (Current shape vs Next shape side-by-side)
        let shape1 = state.current_shape;
        let shape2 = (state.current_shape + 1) % state.shapes.len();
        render_polyhedron(
            &mut buf,
            &mut zbuf,
            &state.shapes[shape1],
            -0.52,
            0.0,
            0.95,
            state.rot_x,
            state.rot_y,
            state.rot_z,
            b'#',
        );
        render_polyhedron(
            &mut buf,
            &mut zbuf,
            &state.shapes[shape2],
            0.52,
            0.0,
            0.95,
            state.rot_x * 0.8,
            -state.rot_y,
            state.rot_z,
            b'*',
        );

        let label1 = format!("< {} >", state.shapes[shape1].name);
        let label2 = format!("< {} >", state.shapes[shape2].name);
        draw_string(&mut buf, 25 - (label1.len() as i32) / 2, ROWS as i32 - 8, &label1);
        draw_string(&mut buf, 75 - (label2.len() as i32) / 2, ROWS as i32 - 8, &label2);
    } else if state.render_mode == 2 {
        // Mode 2: Gallery View (all Platonic solids)
        let offsets = [-0.75f32, -0.38, 0.0, 0.38, 0.75];
        for i in 0..5.min(state.shapes.len()) {
            render_polyhedron(
                &mut buf,
                &mut zbuf,
                &state.shapes[i],
                offsets[i],
                0.0,
                0.48,
                state.rot_x + i as f32 * 0.4,
                state.rot_y + i as f32 * 0.6,
                state.rot_z,
                0,
            );
            let name = state.shapes[i].name;
            let short_len = name.len().min(8);
            let short_name = &name[..short_len];
            let x_pos = (((offsets[i] + 1.0) * COLS as f32 * 0.5) as i32) - (short_name.len() as i32) / 2;
            draw_string(&mut buf, x_pos, ROWS as i32 - 8, short_name);
        }
    }

    // Bottom Footer / Info Bar
    draw_string(&mut buf, 0, ROWS as i32 - 6, &header_border);

    let cur = &state.shapes[state.current_shape];
    let info_line = format!(
        "| SHAPE [{}/{}]: {:<18} | CLASS: {:<18} | V:{:<2} E:{:<2} F:{:<2} |",
        state.current_shape + 1,
        state.shapes.len(),
        cur.name,
        cur.type_label,
        cur.verts.len(),
        cur.edges.len(),
        cur.faces
    );
    draw_string(&mut buf, 0, ROWS as i32 - 5, &info_line);

    let help_line = "| [1-7] SELECT SOLID  [SPACE] PAUSE/RESUME  [TAB] AUTO-CYCLE  [M] VIEW MODE  [+/-] SPEED |";
    draw_string(&mut buf, 0, ROWS as i32 - 4, help_line);

    let controls_line = "| [ARROWS / MOUSE DRAG] ROTATE 3D  [N/P] NEXT/PREV SHAPE  [RAMP: .:-=+*#%@]             |";
    draw_string(&mut buf, 0, ROWS as i32 - 3, controls_line);
    draw_string(&mut buf, 0, ROWS as i32 - 2, &header_border);

    // Build terminal byte slice output
    let mut out = Vec::with_capacity((COLS + 1) * ROWS);
    for y in 0..ROWS {
        out.extend_from_slice(&buf[y * COLS..(y + 1) * COLS]);
        out.push(b'\n');
    }

    // Push frame to JavaScript
    unsafe {
        push_terminal_frame(out.as_ptr(), out.len());
    }
}

#[no_mangle]
pub extern "C" fn set_shape(index: i32) {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            if index >= 0 && (index as usize) < state.shapes.len() {
                state.current_shape = index as usize;
                state.auto_cycle = false;
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn next_shape() {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            if !state.shapes.is_empty() {
                state.current_shape = (state.current_shape + 1) % state.shapes.len();
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn prev_shape() {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            if !state.shapes.is_empty() {
                state.current_shape = (state.current_shape + state.shapes.len() - 1) % state.shapes.len();
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn toggle_auto_rotate() {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            state.auto_rotate = !state.auto_rotate;
        }
    }
}

#[no_mangle]
pub extern "C" fn toggle_auto_cycle() {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            state.auto_cycle = !state.auto_cycle;
            state.cycle_timer = 0.0;
        }
    }
}

#[no_mangle]
pub extern "C" fn set_rotation_speed(mut speed: f32) {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            if speed < 0.1 {
                speed = 0.1;
            }
            if speed > 5.0 {
                speed = 5.0;
            }
            state.rot_speed = speed;
        }
    }
}

#[no_mangle]
pub extern "C" fn rotate_manual(dx: f32, dy: f32) {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            state.rot_y += dx * 0.015;
            state.rot_x += dy * 0.015;
        }
    }
}

#[no_mangle]
pub extern "C" fn set_render_mode(mode: i32) {
    if let Ok(mut guard) = STATE.lock() {
        if let Some(state) = guard.as_mut() {
            state.render_mode = mode;
        }
    }
}

#[no_mangle]
pub extern "C" fn get_current_shape() -> i32 {
    if let Ok(guard) = STATE.lock() {
        if let Some(state) = guard.as_ref() {
            return state.current_shape as i32;
        }
    }
    0
}

#[no_mangle]
pub extern "C" fn get_shape_count() -> i32 {
    if let Ok(guard) = STATE.lock() {
        if let Some(state) = guard.as_ref() {
            return state.shapes.len() as i32;
        }
    }
    0
}

fn main() {
    let shapes = init_shapes();
    if let Ok(mut guard) = STATE.lock() {
        *guard = Some(State {
            shapes,
            current_shape: 0,
            render_mode: 0,
            auto_rotate: true,
            auto_cycle: false,
            rot_speed: 1.0,
            rot_x: 0.35,
            rot_y: 0.50,
            rot_z: 0.15,
            cycle_timer: 0.0,
        });
    }
    unsafe {
        emscripten_set_main_loop(main_loop, 0, 1);
    }
}
