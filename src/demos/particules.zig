const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const glfw = @import("glfw");
const gl = @import("zgl");
const math = @import("zlm");

const common = @import("common");
const rend = common.particules;
const shaders = common.shaders;

fn mix(a: f32, b: f32, amount: f32) f32 {
    return (1 - amount) * a + amount * b;
}

const Particle = struct {
    pub const zero = Particle{ .pos = math.Vec2.zero, .pre_pos = math.Vec2.zero, .radius = 1.0, .mass = 1.0 };
    pos: math.Vec2,
    pre_pos: math.Vec2,
    radius: f32,
    mass: f32,
    pub fn is_colliding(a: Particle, b: Particle) bool {
        return (a.pos.x - b.pos.x) * (a.pos.x - b.pos.x) + (a.pos.y - b.pos.y) * (a.pos.y - b.pos.y) <= (a.radius + b.radius) * (a.radius + b.radius);
    }
};

const World = struct {
    pub const Width = 1_280;
    pub const Height = 720;
    pub const AspectRatio: f32 = @intToFloat(f32, Width) / @intToFloat(f32, Height);

    const N = 100;
    const Stiffness = 0.5;
    const Gravity = -0.1;
    const Iterations = 4;
    const Density = 10;

    particles: [N]Particle,
    pos: [4 * N]f32,
    view_proj: math.Mat4 = math.Mat4.identity,
    random: std.rand.Random,
    pub fn init() World {
        var world = World{ .particles = [_]Particle{Particle.zero} ** N, .pos = [_]f32{0.0} ** (4 * N), .random = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp())).random() };
        const view_mat = math.Mat4.createLookAt(math.Vec3.new(0.0, 0.0, 1.0), math.Vec3.new(0.0, 0.0, 0.0), math.Vec3.new(0, 1.0, 0));
        const projection_mat = math.Mat4.createPerspective(math.toRadians(90.0), AspectRatio, 0.1, 100);
        world.view_proj = math.Mat4.mul(view_mat, projection_mat);
        world.set_random_particles();
        return world;
    }
    pub fn update(self: *World, dt: f32) void {
        var tmp: math.Vec2 = math.Vec2.zero;
        for (self.particles) |*p| {
            tmp = p.pos;
            p.pos.x = 2 * p.pos.x - p.pre_pos.x;
            p.pos.y = 2 * p.pos.y - p.pre_pos.y + dt * dt * Gravity;
            p.pre_pos = tmp;
        }

        var k: u32 = 0;
        while (k < Iterations) : (k += 1) {
            // Compute collisions
            for (self.particles) |*a| {
                for (self.particles) |*b| {
                    if (a != b and a.is_colliding(b.*)) {
                        var a2b = math.Vec2.new(b.pos.x - a.pos.x, b.pos.y - a.pos.y);
                        const a2b_norm = std.math.sqrt(a2b.x * a2b.x + a2b.y * a2b.y);
                        a2b.x = (1.0 / a2b_norm) * a2b.x;
                        a2b.y = (1.0 / a2b_norm) * a2b.y;
                        const overlap = (a.radius + b.radius) - a2b_norm;
                        const ab_mass = a.mass + b.mass;
                        a.pos.x = a.pos.x - a2b.x * (Stiffness * overlap * b.mass / ab_mass);
                        a.pos.y = a.pos.y - a2b.y * (Stiffness * overlap * b.mass / ab_mass);
                        b.pos.x = b.pos.x + a2b.x * (Stiffness * overlap * a.mass / ab_mass);
                        b.pos.y = b.pos.y + a2b.y * (Stiffness * overlap * a.mass / ab_mass);
                    }
                }
            }
            // Stay on screen
            for (self.particles) |*p| {
                const clamped_x = std.math.clamp(p.pos.x, p.radius - AspectRatio, AspectRatio - p.radius);
                const clamped_y = std.math.clamp(p.pos.y, p.radius - 1.0, 1.0 - p.radius);

                if (clamped_x != p.pos.x) {
                    p.pos.x = mix(p.pos.x, clamped_x, Stiffness);
                }
                if (clamped_x != p.pos.y) {
                    p.pos.y = mix(p.pos.y, clamped_y, Stiffness);
                }
            }
        }
    }
    pub fn draw(self: *World, pr: *rend.ParticuleRenderer) void {
        // Copy particles positions to pos
        var i: u32 = 0;
        while (i < self.particles.len) : (i += 1) {
            self.pos[4 * i] = self.particles[i].pos.x;
            self.pos[4 * i + 1] = self.particles[i].pos.y;
            self.pos[4 * i + 3] = self.particles[i].radius;
        }
        pr.draw(&self.pos, self.view_proj);
    }
    fn set_random_particles(self: *World) void {
        for (self.particles) |*p| {
            p.radius = 0.05 * self.random.float(f32);
            p.mass = Density * p.radius * p.radius;
            p.pos.x = std.math.clamp(2 * AspectRatio * self.random.float(f32) - AspectRatio, p.radius - AspectRatio, AspectRatio - p.radius);
            p.pos.y = std.math.clamp(2 * self.random.float(f32) - 1, p.radius - 1.0, 1.0 - p.radius);
            p.pre_pos = p.pos;
        }
    }
};

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

fn cursor_callback(window: glfw.Window, xpos: f64, ypos: f64) void {
    const x: f32 = @floatCast(f32, xpos);
    const y: f32 = @floatCast(f32, ypos);
    const Width: f32 = @intToFloat(f32, World.Width);
    const Height: f32 = @intToFloat(f32, World.Height);

    const world: *World = window.getUserPointer(World).?;

    var curs = Particle.zero;
    curs.pos = math.Vec2.new(-mix(-World.AspectRatio, World.AspectRatio, x / Width), -mix(-1, 1, y / Height));
    curs.radius = 0.01;
    curs.mass = World.Density * curs.radius * curs.radius;

    for (world.particles) |*p| {
        if (p.is_colliding(curs)) {
            p.pos = curs.pos;
        }
    }
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());

    const gpa = general_purpose_allocator.allocator();
    _ = gpa;

    std.log.debug("{}", .{SpatialHashMap.Width});
    std.log.debug("{}", .{SpatialHashMap.Height});

    try glfw.init(.{});
    defer glfw.terminate();

    // Create our window
    const window = try glfw.Window.create(World.Width, World.Height, "Particles demo", null, null, .{});
    defer window.destroy();

    var world = World.init();

    window.setUserPointer(&world);
    window.setKeyCallback(key_callback);
    window.setCursorPosCallback(cursor_callback);

    try glfw.makeContextCurrent(window);

    // Set colors
    var colors: [4 * World.N]f32 = [_]f32{0.0} ** (4 * World.N);
    {
        var i: u32 = 0;
        while (i < colors.len) : (i += 4) {
            colors[i] = 0.5 * world.random.float(f32) + 0.5;
            colors[i + 1] = 0.5 * world.random.float(f32) + 0.5;
            colors[i + 2] = 0.5 * world.random.float(f32) + 0.5;
        }
    }

    var pr = try rend.ParticuleRenderer.init(&colors);
    defer pr.deinit();

    const fps_limit: f64 = 1.0 / 60.0;
    var last_draw: f64 = 0.0;

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        try glfw.pollEvents();

        const now = glfw.getTime();

        if ((now - last_draw) >= fps_limit) {
            std.log.info("fps: {}", .{@floatToInt(u32, 1.0 / (now - last_draw))});

            gl.clear(.{ .color = true });

            world.update(@floatCast(f32, now - last_draw));
            world.draw(&pr);

            last_draw = now;

            try window.swapBuffers();
        }
    }
}
