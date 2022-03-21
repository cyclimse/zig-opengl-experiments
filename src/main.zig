const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const glfw = @import("glfw");
const gl = @import("zgl");
const math = @import("zlm");

const c = @import("c.zig");

const s = @import("shapes.zig");
const shaders = @import("shaders.zig");

const vertex_shader_source = @embedFile("../shaders/shapes.vert");
const frag_shader_source = @embedFile("../shaders/shapes.frag");

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

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());

    const gpa = general_purpose_allocator.allocator();

    try glfw.init(.{});
    defer glfw.terminate();

    // Create our window
    const window = try glfw.Window.create(640, 480, "Hello, mach-glfw!", null, null, .{});
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

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        gl.clearColor(0.2, 0.3, 0.3, 1.0);
        gl.clear(.{ .color = true });

        shader_program.use();
        sr.vao.bind();
        sr.drawTriangle();
        sr.drawSquare();
        sr.drawCircle(0, 0.1, 0.5);
        sr.drawCircle(0, -0.1, 0.5);

        try window.swapBuffers();

        try glfw.pollEvents();
    }
}
