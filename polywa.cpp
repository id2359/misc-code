#include <emscripten.h>
#include <emscripten/html5.h>
#include <cmath>
#include <vector>
#include <string>
#include <algorithm>
#include <cstdio>

const int COLS = 100; // terminal columns
const int ROWS = 48;  // terminal rows
const char* RAMPS = ".:-=+*#%@"; // brightness ramp (dim to bright)

struct Vec3 { float x, y, z; };

struct Polyhedron {
    std::string name;
    std::string type_label;
    int faces;
    std::vector<Vec3> verts;
    std::vector<std::pair<int, int>> edges;
};

std::vector<Polyhedron> shapes;
int current_shape = 0;
int render_mode = 0; // 0: single, 1: dual comparison, 2: gallery
bool auto_rotate = true;
bool auto_cycle = false;
float rot_speed = 1.0f;
float rot_x = 0.35f;
float rot_y = 0.50f;
float rot_z = 0.15f;
float cycle_timer = 0.0f;

// Helper to calculate edges for regular / semi-regular polyhedra by minimum distance
void compute_edges_by_distance(Polyhedron& poly, float tolerance_factor = 1.06f) {
    if (poly.verts.empty()) return;
    float min_dist_sq = 1e9f;
    int n = (int)poly.verts.size();
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            float dx = poly.verts[i].x - poly.verts[j].x;
            float dy = poly.verts[i].y - poly.verts[j].y;
            float dz = poly.verts[i].z - poly.verts[j].z;
            float d2 = dx*dx + dy*dy + dz*dz;
            if (d2 > 1e-4f && d2 < min_dist_sq) {
                min_dist_sq = d2;
            }
        }
    }
    float max_dist_sq = min_dist_sq * tolerance_factor * tolerance_factor;
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            float dx = poly.verts[i].x - poly.verts[j].x;
            float dy = poly.verts[i].y - poly.verts[j].y;
            float dz = poly.verts[i].z - poly.verts[j].z;
            float d2 = dx*dx + dy*dy + dz*dz;
            if (d2 <= max_dist_sq) {
                poly.edges.push_back({i, j});
            }
        }
    }
}

void init_shapes() {
    shapes.clear();

    const float phi = (1.0f + std::sqrt(5.0f)) * 0.5f; // Golden ratio ~ 1.618034

    // 1. Tetrahedron (Platonic solid: 4 Vertices, 6 Edges, 4 Faces)
    {
        Polyhedron p;
        p.name = "TETRAHEDRON";
        p.type_label = "PLATONIC SOLID";
        p.faces = 4;
        float s = 1.30f;
        p.verts = {
            { s,  s,  s},
            { s, -s, -s},
            {-s,  s, -s},
            {-s, -s,  s}
        };
        p.edges = {
            {0, 1}, {0, 2}, {0, 3},
            {1, 2}, {1, 3}, {2, 3}
        };
        shapes.push_back(p);
    }

    // 2. Cube / Hexahedron (Platonic solid: 8 Vertices, 12 Edges, 6 Faces)
    {
        Polyhedron p;
        p.name = "HEXAHEDRON (CUBE)";
        p.type_label = "PLATONIC SOLID";
        p.faces = 6;
        float s = 1.00f;
        p.verts = {
            {-s, -s, -s}, { s, -s, -s}, { s,  s, -s}, {-s,  s, -s},
            {-s, -s,  s}, { s, -s,  s}, { s,  s,  s}, {-s,  s,  s}
        };
        p.edges = {
            {0,1}, {1,2}, {2,3}, {3,0},
            {4,5}, {5,6}, {6,7}, {7,4},
            {0,4}, {1,5}, {2,6}, {3,7}
        };
        shapes.push_back(p);
    }

    // 3. Octahedron (Platonic solid: 6 Vertices, 12 Edges, 8 Faces)
    {
        Polyhedron p;
        p.name = "OCTAHEDRON";
        p.type_label = "PLATONIC SOLID";
        p.faces = 8;
        float s = 1.50f;
        p.verts = {
            { s,  0,  0}, {-s,  0,  0},
            { 0,  s,  0}, { 0, -s,  0},
            { 0,  0,  s}, { 0,  0, -s}
        };
        p.edges = {
            {0,2}, {0,3}, {0,4}, {0,5},
            {1,2}, {1,3}, {1,4}, {1,5},
            {2,4}, {4,3}, {3,5}, {5,2}
        };
        shapes.push_back(p);
    }

    // 4. Dodecahedron (Platonic solid: 20 Vertices, 30 Edges, 12 Faces)
    {
        Polyhedron p;
        p.name = "DODECAHEDRON";
        p.type_label = "PLATONIC SOLID";
        p.faces = 12;
        float s = 0.85f;
        // 8 vertices of cube
        for (float x : {-s, s})
            for (float y : {-s, s})
                for (float z : {-s, s})
                    p.verts.push_back({x, y, z});
        // 12 vertices on coordinate planes
        for (float y : {-s/phi, s/phi})
            for (float z : {-s*phi, s*phi})
                p.verts.push_back({0, y, z});
        for (float x : {-s/phi, s/phi})
            for (float y : {-s*phi, s*phi})
                p.verts.push_back({x, y, 0});
        for (float x : {-s*phi, s*phi})
            for (float z : {-s/phi, s/phi})
                p.verts.push_back({x, 0, z});

        compute_edges_by_distance(p, 1.05f);
        shapes.push_back(p);
    }

    // 5. Icosahedron (Platonic solid: 12 Vertices, 30 Edges, 20 Faces)
    {
        Polyhedron p;
        p.name = "ICOSAHEDRON";
        p.type_label = "PLATONIC SOLID";
        p.faces = 20;
        float s = 0.95f;
        for (float y : {-s, s})
            for (float z : {-s*phi, s*phi})
                p.verts.push_back({0, y, z});
        for (float x : {-s, s})
            for (float y : {-s*phi, s*phi})
                p.verts.push_back({x, y, 0});
        for (float x : {-s*phi, s*phi})
            for (float z : {-s, s})
                p.verts.push_back({x, 0, z});

        compute_edges_by_distance(p, 1.05f);
        shapes.push_back(p);
    }

    // 6. Cuboctahedron (Archimedean solid: 12 Vertices, 24 Edges, 14 Faces)
    {
        Polyhedron p;
        p.name = "CUBOCTAHEDRON";
        p.type_label = "ARCHIMEDEAN SOLID";
        p.faces = 14;
        float s = 1.15f;
        p.verts = {
            { s,  s,  0}, { s, -s,  0}, {-s,  s,  0}, {-s, -s,  0},
            { s,  0,  s}, { s,  0, -s}, {-s,  0,  s}, {-s,  0, -s},
            { 0,  s,  s}, { 0,  s, -s}, { 0, -s,  s}, { 0, -s, -s}
        };
        compute_edges_by_distance(p, 1.05f);
        shapes.push_back(p);
    }

    // 7. Stella Octangula (Kepler's Star Polyhedron: 8 Vertices, 24 Edges, 8 Faces)
    {
        Polyhedron p;
        p.name = "STELLA OCTANGULA";
        p.type_label = "KEPLER STAR POLYHEDRON";
        p.faces = 8;
        float s = 1.25f;
        // Two interpenetrating regular tetrahedra
        p.verts = {
            // Tetrahedron A
            { s,  s,  s}, { s, -s, -s}, {-s,  s, -s}, {-s, -s,  s},
            // Tetrahedron B
            {-s, -s, -s}, {-s,  s,  s}, { s, -s,  s}, { s,  s, -s}
        };
        p.edges = {
            // Tet A edges
            {0, 1}, {0, 2}, {0, 3}, {1, 2}, {1, 3}, {2, 3},
            // Tet B edges
            {4, 5}, {4, 6}, {4, 7}, {5, 6}, {5, 7}, {6, 7}
        };
        shapes.push_back(p);
    }
}

// 3D 3-axis Euler rotation
void rotate_point(Vec3& v, float ax, float ay, float az) {
    // Rotate Y
    float cy = cos(ay), sy = sin(ay);
    float x1 = cy * v.x + sy * v.z;
    float z1 = -sy * v.x + cy * v.z;
    float y1 = v.y;

    // Rotate X
    float cx = cos(ax), sx = sin(ax);
    float y2 = cx * y1 - sx * z1;
    float z2 = sx * y1 + cx * z1;
    float x2 = x1;

    // Rotate Z
    float cz = cos(az), sz = sin(az);
    v.x = cz * x2 - sz * y2;
    v.y = sz * x2 + cz * y2;
    v.z = z2;
}

// 3D Perspective Projection
bool project_point(Vec3 v, float offset_x, float offset_y, float scale, int& px, int& py, float& depth_z) {
    float camera_z = v.z + 3.2f;
    if (camera_z <= 0.1f) return false;
    depth_z = camera_z;
    float factor = scale / camera_z;
    px = int((v.x * factor + offset_x + 1.0f) * COLS * 0.5f);
    py = int((-v.y * factor * 0.95f + offset_y + 1.0f) * ROWS * 0.5f);
    return true;
}

// Bresenham's line algorithm with depth buffer and brightness ramp shading
void draw_line_depth(char* buf, float* zbuf, int x0, int y0, float z0, int x1, int y1, float z1, char forced_ch = 0) {
    int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;

    float total_dist = std::hypot((float)(x1 - x0), (float)(y1 - y0));
    if (total_dist < 1.0f) total_dist = 1.0f;

    int cur_x = x0, cur_y = y0;
    while (true) {
        if (cur_x >= 0 && cur_x < COLS && cur_y >= 0 && cur_y < ROWS) {
            float traveled = std::hypot((float)(cur_x - x0), (float)(cur_y - y0));
            float t = std::min(1.0f, std::max(0.0f, traveled / total_dist));
            float z = z0 + t * (z1 - z0);

            int idx = cur_y * COLS + cur_x;
            if (z < zbuf[idx]) {
                zbuf[idx] = z;
                if (forced_ch != 0) {
                    buf[idx] = forced_ch;
                } else {
                    // Depth brightness ramp: 1/z
                    float brightness = (3.4f / z - 0.65f) / 0.85f;
                    int ramp_idx = int(brightness * 8.0f);
                    if (ramp_idx < 0) ramp_idx = 0;
                    if (ramp_idx > 8) ramp_idx = 8;
                    buf[idx] = RAMPS[ramp_idx];
                }
            }
        }
        if (cur_x == x1 && cur_y == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; cur_x += sx; }
        if (e2 <= dx) { err += dx; cur_y += sy; }
    }
}

// Draw vertex point marker
void draw_vertex_point(char* buf, float* zbuf, int px, int py, float z) {
    if (px >= 0 && px < COLS && py >= 0 && py < ROWS) {
        int idx = py * COLS + px;
        if (z - 0.02f <= zbuf[idx]) {
            zbuf[idx] = z - 0.02f;
            buf[idx] = '@';
        }
    }
}

// Text printing onto terminal buffer
void draw_string(char* buf, int x, int y, const std::string& str) {
    if (y < 0 || y >= ROWS) return;
    for (size_t i = 0; i < str.size(); i++) {
        int px = x + (int)i;
        if (px >= 0 && px < COLS) {
            buf[y * COLS + px] = str[i];
        }
    }
}

// Draw a single polyhedron in the viewport
void render_polyhedron(char* buf, float* zbuf, const Polyhedron& poly, float off_x, float off_y, float scale, float ax, float ay, float az, char forced_ch = 0) {
    struct ProjV { int px, py; float z; bool ok; };
    std::vector<ProjV> proj(poly.verts.size());

    for (size_t i = 0; i < poly.verts.size(); i++) {
        Vec3 v = poly.verts[i];
        rotate_point(v, ax, ay, az);
        int px, py;
        float z;
        bool ok = project_point(v, off_x, off_y, scale, px, py, z);
        proj[i] = {px, py, z, ok};
    }

    // Draw all edges
    for (const auto& e : poly.edges) {
        const auto& p0 = proj[e.first];
        const auto& p1 = proj[e.second];
        if (p0.ok && p1.ok) {
            draw_line_depth(buf, zbuf, p0.px, p0.py, p0.z, p1.px, p1.py, p1.z, forced_ch);
        }
    }

    // Draw vertices
    for (const auto& p : proj) {
        if (p.ok) {
            draw_vertex_point(buf, zbuf, p.px, p.py, p.z);
        }
    }
}

void main_loop() {
    static char buf[COLS * ROWS];
    static float zbuf[COLS * ROWS];

    // Clear frame and depth buffer
    for (int i = 0; i < COLS * ROWS; i++) {
        buf[i] = ' ';
        zbuf[i] = 1e9f;
    }

    // Advance rotation animation
    if (auto_rotate) {
        rot_y += 0.018f * rot_speed;
        rot_x += 0.012f * rot_speed;
        rot_z += 0.007f * rot_speed;
    }

    // Handle auto cycling through shapes
    if (auto_cycle) {
        cycle_timer += 0.016f;
        if (cycle_timer >= 4.0f) {
            cycle_timer = 0.0f;
            current_shape = (current_shape + 1) % (int)shapes.size();
        }
    }

    // Header UI
    std::string header_border(COLS, '-');
    header_border[0] = '+';
    header_border[COLS - 1] = '+';
    draw_string(buf, 0, 0, header_border);

    char title_bar[128];
    snprintf(title_bar, sizeof(title_bar), "| POLYWA :: 70s CRT 3D POLYHEDRA TERMINAL  [AUTO-ROT: %s | SPEED: %.1fx | CYCLE: %s] |",
             auto_rotate ? "ON " : "OFF", rot_speed, auto_cycle ? "ON " : "OFF");
    draw_string(buf, 0, 1, title_bar);
    draw_string(buf, 0, 2, header_border);

    // Render Mode Selection
    if (render_mode == 0) {
        // Mode 0: Single Large Polyhedron Centered
        if (current_shape >= 0 && current_shape < (int)shapes.size()) {
            render_polyhedron(buf, zbuf, shapes[current_shape], 0.0f, 0.0f, 1.45f, rot_x, rot_y, rot_z);
        }
    } else if (render_mode == 1) {
        // Mode 1: Dual comparison (Current shape vs Next shape side-by-side)
        int shape1 = current_shape;
        int shape2 = (current_shape + 1) % (int)shapes.size();
        render_polyhedron(buf, zbuf, shapes[shape1], -0.52f, 0.0f, 0.95f, rot_x, rot_y, rot_z, '#');
        render_polyhedron(buf, zbuf, shapes[shape2],  0.52f, 0.0f, 0.95f, rot_x * 0.8f, -rot_y, rot_z, '*');

        std::string label1 = "< " + shapes[shape1].name + " >";
        std::string label2 = "< " + shapes[shape2].name + " >";
        draw_string(buf, 25 - (int)label1.size() / 2, ROWS - 8, label1);
        draw_string(buf, 75 - (int)label2.size() / 2, ROWS - 8, label2);
    } else if (render_mode == 2) {
        // Mode 2: Gallery View (all Platonic solids)
        float offsets[5] = {-0.75f, -0.38f, 0.0f, 0.38f, 0.75f};
        for (int i = 0; i < 5 && i < (int)shapes.size(); i++) {
            render_polyhedron(buf, zbuf, shapes[i], offsets[i], 0.0f, 0.48f, rot_x + i * 0.4f, rot_y + i * 0.6f, rot_z);
            std::string short_name = shapes[i].name.substr(0, std::min((size_t)8, shapes[i].name.size()));
            int x_pos = int((offsets[i] + 1.0f) * COLS * 0.5f) - (int)short_name.size() / 2;
            draw_string(buf, x_pos, ROWS - 8, short_name);
        }
    }

    // Bottom Footer / Info Bar
    draw_string(buf, 0, ROWS - 6, header_border);

    const Polyhedron& cur = shapes[current_shape];
    char info_line[128];
    snprintf(info_line, sizeof(info_line), "| SHAPE [%d/%d]: %-18s | CLASS: %-18s | V:%-2d E:%-2d F:%-2d |",
             current_shape + 1, (int)shapes.size(), cur.name.c_str(), cur.type_label.c_str(),
             (int)cur.verts.size(), (int)cur.edges.size(), cur.faces);
    draw_string(buf, 0, ROWS - 5, info_line);

    char help_line[128];
    snprintf(help_line, sizeof(help_line), "| [1-7] SELECT SOLID  [SPACE] PAUSE/RESUME  [TAB] AUTO-CYCLE  [M] VIEW MODE  [+/-] SPEED |");
    draw_string(buf, 0, ROWS - 4, help_line);

    char controls_line[128];
    snprintf(controls_line, sizeof(controls_line), "| [ARROWS / MOUSE DRAG] ROTATE 3D  [N/P] NEXT/PREV SHAPE  [RAMP: .:-=+*#%%@]             |");
    draw_string(buf, 0, ROWS - 3, controls_line);
    draw_string(buf, 0, ROWS - 2, header_border);

    // Build terminal string output
    std::string out;
    out.reserve((COLS + 1) * ROWS);
    for (int y = 0; y < ROWS; y++) {
        out.append(buf + y * COLS, COLS);
        out.push_back('\n');
    }

    // Push frame to JavaScript
    EM_ASM({
        if (Module && Module.setTerminalText) {
            Module.setTerminalText(UTF8ToString($0));
        }
    }, out.c_str());
}

extern "C" {
    EMSCRIPTEN_KEEPALIVE void set_shape(int index) {
        if (index >= 0 && index < (int)shapes.size()) {
            current_shape = index;
            auto_cycle = false;
        }
    }

    EMSCRIPTEN_KEEPALIVE void next_shape() {
        current_shape = (current_shape + 1) % (int)shapes.size();
    }

    EMSCRIPTEN_KEEPALIVE void prev_shape() {
        current_shape = (current_shape - 1 + (int)shapes.size()) % (int)shapes.size();
    }

    EMSCRIPTEN_KEEPALIVE void toggle_auto_rotate() {
        auto_rotate = !auto_rotate;
    }

    EMSCRIPTEN_KEEPALIVE void toggle_auto_cycle() {
        auto_cycle = !auto_cycle;
        cycle_timer = 0.0f;
    }

    EMSCRIPTEN_KEEPALIVE void set_rotation_speed(float speed) {
        rot_speed = speed;
        if (rot_speed < 0.1f) rot_speed = 0.1f;
        if (rot_speed > 5.0f) rot_speed = 5.0f;
    }

    EMSCRIPTEN_KEEPALIVE void rotate_manual(float dx, float dy) {
        rot_y += dx * 0.015f;
        rot_x += dy * 0.015f;
    }

    EMSCRIPTEN_KEEPALIVE void set_render_mode(int mode) {
        render_mode = mode;
    }

    EMSCRIPTEN_KEEPALIVE int get_current_shape() {
        return current_shape;
    }

    EMSCRIPTEN_KEEPALIVE int get_shape_count() {
        return (int)shapes.size();
    }
}

int main() {
    init_shapes();
    emscripten_set_main_loop(main_loop, 0, 1);
    return 0;
}
