const gl = @import("zgl");
const math = @import("zlm");
const c = @import("c.zig");
const std = @import("std");

const buffer_size = 2048;

fn cs2gl(size: usize) gl.SizeI {
    return @intCast(gl.SizeI, size);
}

pub fn glDrawElementsBaseVertex(primitiveType: gl.PrimitiveType, count: usize, element_type: gl.ElementType, indices: usize, base_vertex: usize) void {
    c.glDrawElementsBaseVertex(@enumToInt(primitiveType), cs2gl(count), @enumToInt(element_type), @intToPtr(*allowzero const anyopaque, indices), cs2gl(base_vertex));
    // checkError();
}

pub const RenderableShape = struct {
    primitive_type: gl.PrimitiveType = gl.PrimitiveType.triangles,
    count: usize,
    start: usize,
    base_vertex: usize,
    pub fn draw(self: *RenderableShape) void {
        glDrawElementsBaseVertex(self.primitive_type, self.count, gl.ElementType.u32, self.start * @sizeOf(u32), self.base_vertex);
    }
};

pub const ShapeRenderer = struct {
    // Vertices
    current_vertex: usize = 0,
    vertices: [buffer_size]f32 = [_]f32{0.0} ** buffer_size,
    // Indices
    current_index: usize = 0,
    indices: [buffer_size]u32 = [_]u32{0} ** buffer_size,
    // Loaded shapes
    triangle_shape: ?RenderableShape = null,
    square_shape: ?RenderableShape = null,
    circle_shape: ?RenderableShape = null,
    // OpenGL
    vao: gl.VertexArray,
    vbo: gl.Buffer,
    ebo: gl.Buffer,
    pid: gl.Program,
    model_id: u32,
    pub fn init(pid: gl.Program) ShapeRenderer {
        var sr = ShapeRenderer{ .vao = gl.VertexArray.create(), .vbo = gl.Buffer.create(), .ebo = gl.Buffer.create(), .pid = pid, .model_id = pid.uniformLocation("model").? };
        // Load the shapes
        sr.triangle_shape = sr.loadTriangle();
        sr.square_shape = sr.loadSquare();
        sr.circle_shape = sr.loadCircle();
        // Upload meshes to GPU
        sr.vao.bind();
        sr.ebo.bind(gl.BufferTarget.element_array_buffer);
        sr.vbo.bind(gl.BufferTarget.array_buffer);
        gl.vertexAttribPointer(0, 3, gl.Type.float, false, 3 * @sizeOf(f32), 0);
        gl.enableVertexAttribArray(0);
        sr.ebo.data(u32, sr.indices[0..sr.current_index], gl.BufferUsage.static_draw);
        sr.vbo.data(f32, sr.vertices[0..sr.current_vertex], gl.BufferUsage.static_draw);
        return sr;
    }
    pub fn deinit(self: *ShapeRenderer) void {
        self.ebo.delete();
        self.vbo.delete();
        self.vao.delete();
    }
    pub fn drawTriangle(self: *ShapeRenderer) void {
        var model_mat = math.Mat4.identity;
        gl.uniformMatrix4fv(self.model_id, false, &[_][4][4]f32{model_mat.fields});
        self.triangle_shape.?.draw();
    }
    pub fn drawSquare(self: *ShapeRenderer) void {
        var model_mat = math.Mat4.identity;
        gl.uniformMatrix4fv(self.model_id, false, &[_][4][4]f32{model_mat.fields});
        self.square_shape.?.draw();
    }
    pub fn drawCircle(self: *ShapeRenderer, x: f32, y: f32, radius: f32) void {
        var model_mat = math.Mat4.mul(math.Mat4.createUniformScale(radius), math.Mat4.createTranslationXYZ(x, y, 0));
        gl.uniformMatrix4fv(self.model_id, false, &[_][4][4]f32{model_mat.fields});
        self.circle_shape.?.draw();
    }
    fn loadTriangle(self: *ShapeRenderer) RenderableShape {
        const vertices align(1) = [_]f32{
            0.5,  -0.5, 0.0,
            -0.5, -0.5, 0.0,
            0.0,  0.5,  0.0,
        };
        const indices align(1) = [_]u32{ 0, 1, 2 };
        return loadShape(self, &vertices, &indices, gl.PrimitiveType.triangles);
    }
    fn loadSquare(self: *ShapeRenderer) RenderableShape {
        const vertices align(1) = [_]f32{
            0.5, 0.5, 0.0, // top right
            0.5, -0.5, 0.0, // bottom right
            -0.5, -0.5, 0.0, // bottom left
            -0.5, 0.5, 0.0, // top left
        };
        const indices align(1) = [_]u32{
            0, 1, 3, // first triangle
            1, 2, 3,
        };
        return loadShape(self, &vertices, &indices, gl.PrimitiveType.triangles);
    }
    fn loadCircle(self: *ShapeRenderer) RenderableShape {
        const triangle_count = 20;

        var vertices align(1) = [_]f32{0.0} ** (3 * (triangle_count + 2));
        var indices align(1) = [_]u32{0} ** (triangle_count + 2);

        var i: u32 = 0;
        while (i <= triangle_count) : (i += 1) {
            vertices[3 * i + 3] = std.math.cos(@intToFloat(f32, i) * (2.0 * std.math.pi) / @as(f32, triangle_count));
            vertices[3 * i + 4] = std.math.sin(@intToFloat(f32, i) * (2.0 * std.math.pi) / @as(f32, triangle_count));
            indices[i + 1] = i + 1;
        }

        return loadShape(self, &vertices, &indices, gl.PrimitiveType.triangle_fan);
    }
    fn loadShape(self: *ShapeRenderer, shape_vertices: []align(1) const f32, shape_indices: []align(1) const u32, primitive_type: gl.PrimitiveType) RenderableShape {
        std.debug.assert(buffer_size >= self.current_index + shape_indices.len);
        std.debug.assert(buffer_size >= self.current_vertex + shape_vertices.len);
        for (shape_vertices) |vertex, i| {
            self.vertices[i + self.current_vertex] = vertex;
        }
        for (shape_indices) |index, i| {
            self.indices[i + self.current_index] = index;
        }
        const rs = RenderableShape{ .primitive_type = primitive_type, .count = shape_indices.len, .start = self.current_index, .base_vertex = self.current_vertex / 3 };
        self.current_index += shape_indices.len;
        self.current_vertex += shape_vertices.len;
        return rs;
    }
};
