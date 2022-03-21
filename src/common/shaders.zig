const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const glfw = @import("glfw");
const gl = @import("zgl");

pub fn check_shader_compilation(shader: gl.Shader, allocator: Allocator) !void {
    var result = try gl.getShaderInfoLog(shader, allocator);
    defer allocator.free(result);
    if (result.len > 0) {
        std.log.err("vertex shader compilation error: {s}", .{result});
    }
}

pub fn check_program_linking(program: gl.Program, allocator: Allocator) !void {
    var result = try gl.getProgramInfoLog(program, allocator);
    defer allocator.free(result);
    if (result.len > 0) {
        std.log.err("program link error: {s}", .{result});
    }
}
