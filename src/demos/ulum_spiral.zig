const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const glfw = @import("glfw");
const gl = @import("zgl");
const math = @import("zlm");

const common = @import("common");
const s = common.shapes;
const shaders = common.shaders;

const vertex_shader_source = @embedFile("../../shaders/shapes.vert");
const frag_shader_source = @embedFile("../../shaders/shapes.frag");

var wireframe_mode = false;
fn key_callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = action;
    _ = scancode;
    _ = mods;
    switch (key) {
        .e => {
            if (action == glfw.Action.press) {
                if (wireframe_mode) {
                    gl.polygonMode(gl.CullMode.front_and_back, gl.DrawMode.fill);
                } else {
                    gl.polygonMode(gl.CullMode.front_and_back, gl.DrawMode.line);
                }
                wireframe_mode = !wireframe_mode;
            }
        },
        .escape => {
            window.setShouldClose(true);
        },
        else => {},
    }
}

pub fn isPrime(n: u32) bool {
    var i: u32 = 2;
    while (i <= std.math.sqrt(n)) : (i += 1) {
        if (n % i == 0) {
            return false;
        }
    }
    return true;
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());

    const gpa = general_purpose_allocator.allocator();

    try glfw.init(.{});
    defer glfw.terminate();

    // Create our window
    const window = try glfw.Window.create(1_280, 720, "bite", null, null, .{});
    defer window.destroy();

    window.setKeyCallback(key_callback);

    try glfw.makeContextCurrent(window);

    var vertex_shader = gl.createShader(gl.ShaderType.vertex);
    vertex_shader.source(1, &[1][]const u8{vertex_shader_source});
    vertex_shader.compile();
    try shaders.check_shader_compilation(vertex_shader, gpa);
    defer vertex_shader.delete();

    // Fragment shader
    var frag_shader = gl.createShader(gl.ShaderType.fragment);
    frag_shader.source(1, &[1][]const u8{frag_shader_source});
    frag_shader.compile();
    try shaders.check_shader_compilation(frag_shader, gpa);
    defer frag_shader.delete();

    // Shader program
    var shader_program = gl.createProgram();
    shader_program.attach(vertex_shader);
    shader_program.attach(frag_shader);
    shader_program.link();
    try shaders.check_program_linking(shader_program, gpa);

    var sr = s.ShapeRenderer.init(shader_program);
    defer sr.deinit();

    const fps_limit: f64 = 1.0 / 30.0;
    var last_draw: f64 = 0.0;

    const view_id = shader_program.uniformLocation("view").?;

    const projection_id = shader_program.uniformLocation("projection").?;

    shader_program.use();
    sr.vao.bind();

    const view_mat = math.Mat4.createLookAt(math.Vec3.new(0.0, 0.0, 1.0), math.Vec3.new(0.0, 0.0, 0.0), math.Vec3.new(0, 1.0, 0));
    const projection_mat = math.Mat4.createPerspective(math.toRadians(90.0), 16.0 / 9.0, 0.1, 100);

    gl.uniformMatrix4fv(view_id, false, &[_][4][4]f32{view_mat.fields});
    gl.uniformMatrix4fv(projection_id, false, &[_][4][4]f32{projection_mat.fields});

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        try glfw.pollEvents();

        const now = glfw.getTime();

        if ((now - last_draw) >= fps_limit) {
            gl.clear(.{ .color = true });

            var n: u32 = 1; // current number
            var state: u32 = 0;
            var number_steps: u32 = 1;
            var x: f32 = 0.0;
            var y: f32 = 0.0;
            const step_size: f32 = 0.005;
            var turn_counter: u32 = 1;

            while (n <= 1000000) : (n += 1) {
                if (isPrime(n)) {
                    sr.drawCircle(x, y, 0.4 * step_size);
                }

                switch (state) {
                    0 => x += step_size,
                    1 => y -= step_size,
                    2 => x -= step_size,
                    3 => y += step_size,
                    else => unreachable,
                }

                // Change state
                if (n % number_steps == 0) {
                    state = (state + 1) % 4;
                    turn_counter += 1;
                    if (turn_counter % 2 == 0) {
                        number_steps += 1;
                    }
                }

                if (x > 1.0 or y > 1.0) {
                    std.log.info("{}", .{n});
                    break;
                }
            }

            last_draw = now;

            try window.swapBuffers();
        }
    }
}
