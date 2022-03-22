const gl = @import("zgl");
const math = @import("zlm");
const c = @import("../c.zig");
const std = @import("std");

const shaders = @import("../shaders.zig");

const vertex_shader_source = @embedFile("../../../shaders/particules.vert");
const frag_shader_source = @embedFile("../../../shaders/particules.frag");

const triangle_count = 20;

pub const ParticleRenderer = struct {
    const RendererInner = struct {
        vao: gl.VertexArray,
        vbo: gl.Buffer,
        ibo: gl.Buffer,
        color_vbo: gl.Buffer,
        vertex_shader: gl.Shader,
        frag_shader: gl.Shader,
        pid: gl.Program,
        view_proj_id: u32,
        pub fn init() !RendererInner {
            var ri = RendererInner{
                // zig fmt: off
                .vao = gl.VertexArray.create(),
                .vbo = gl.Buffer.create(),
                .ibo = gl.Buffer.create(),
                .color_vbo = gl.Buffer.create(),
                .vertex_shader = gl.Shader.create(gl.ShaderType.vertex),
                .frag_shader = gl.Shader.create(gl.ShaderType.fragment),
                .pid = gl.Program.create(),
                .view_proj_id = 0
                // zig fmt: on
            };
            ri.vertex_shader.source(1, &[1][]const u8{vertex_shader_source});
            ri.vertex_shader.compile();
            if (std.debug.runtime_safety) {
                try shaders.check_shader_compilation(ri.vertex_shader, std.heap.c_allocator);
            }
            ri.frag_shader.source(1, &[1][]const u8{frag_shader_source});
            ri.frag_shader.compile();
            if (std.debug.runtime_safety) {
                try shaders.check_shader_compilation(ri.frag_shader, std.heap.c_allocator);
            }
            ri.pid.attach(ri.vertex_shader);
            ri.pid.attach(ri.frag_shader);
            ri.pid.link();
            if (std.debug.runtime_safety) {
                try shaders.check_program_linking(ri.pid, std.heap.c_allocator);
            }
            ri.view_proj_id = ri.pid.uniformLocation("view_proj").?;
            return ri;
        }
        pub fn deinit(self: *RendererInner) void {
            // Delete the shaders
            self.frag_shader.delete();
            self.vertex_shader.delete();
            self.pid.delete();
            // Free the buffers
            self.color_vbo.delete();
            self.ibo.delete();
            self.vbo.delete();
            self.vao.delete();
        }
    };

    inner: RendererInner,

    pub fn init(colors: []align(1) const f32) !ParticleRenderer {
        var pr = ParticleRenderer{ .inner = try RendererInner.init() };
        pr.inner.vao.bind();
        // Mesh
        pr.inner.vbo.bind(gl.BufferTarget.array_buffer);
        pr.loadParticleMesh();
        gl.vertexAttribPointer(0, 3, gl.Type.float, false, 3 * @sizeOf(f32), 0);
        gl.enableVertexAttribArray(0);
        gl.bindBuffer(gl.Buffer.invalid, gl.BufferTarget.array_buffer);
        // Offsets
        pr.inner.ibo.bind(gl.BufferTarget.array_buffer);
        gl.vertexAttribPointer(1, 4, gl.Type.float, false, 4 * @sizeOf(f32), 0);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribDivisor(1, 1);
        gl.bindBuffer(gl.Buffer.invalid, gl.BufferTarget.array_buffer);
        // Color
        pr.inner.color_vbo.bind(gl.BufferTarget.array_buffer);
        pr.inner.color_vbo.data(f32, colors, gl.BufferUsage.static_draw);
        gl.vertexAttribPointer(2, 4, gl.Type.float, false, 4 * @sizeOf(f32), 0);
        gl.enableVertexAttribArray(2);
        gl.vertexAttribDivisor(2, 1);
        gl.bindBuffer(gl.Buffer.invalid, gl.BufferTarget.array_buffer);
        return pr;
    }
    pub fn deinit(self: *ParticleRenderer) void {
        self.inner.deinit();
    }
    pub fn draw(self: *ParticleRenderer, pos: []align(1) const f32, view_proj: math.Mat4) void {
        self.inner.vao.bind();
        self.inner.ibo.data(f32, pos, gl.BufferUsage.stream_draw);

        self.inner.pid.use();
        gl.uniformMatrix4fv(self.inner.view_proj_id, false, &[_][4][4]f32{view_proj.fields});

        gl.drawArraysInstanced(gl.PrimitiveType.triangle_fan, 0, triangle_count + 2, pos.len / 4);
    }
    fn loadParticleMesh(self: *ParticleRenderer) void {
        var vertices align(1) = [_]f32{0.0} ** (3 * (triangle_count + 2));

        var i: u32 = 0;
        while (i <= triangle_count) : (i += 1) {
            vertices[3 * i + 3] = std.math.cos(@intToFloat(f32, i) * (2.0 * std.math.pi) / @as(f32, triangle_count));
            vertices[3 * i + 4] = std.math.sin(@intToFloat(f32, i) * (2.0 * std.math.pi) / @as(f32, triangle_count));
        }

        self.inner.vbo.data(f32, &vertices, gl.BufferUsage.static_draw);
    }
};
