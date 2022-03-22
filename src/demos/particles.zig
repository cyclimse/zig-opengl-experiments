const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const glfw = @import("glfw");
const gl = @import("zgl");
const math = @import("zlm");

const common = @import("common");
const rend = common.particles;
const shaders = common.shaders;

fn mix(a: f32, b: f32, amount: f32) f32 {
    return (1 - amount) * a + amount * b;
}

const Particle = struct {
    pos: math.Vec2 = math.Vec2.zero,
    pre_pos: math.Vec2 = math.Vec2.zero,
    radius: f32 = 1.0,
    mass: f32 = 1.0,
    pub fn isColliding(a: Particle, b: Particle) bool {
        return (a.pos.x - b.pos.x) * (a.pos.x - b.pos.x) + (a.pos.y - b.pos.y) * (a.pos.y - b.pos.y) <= (a.radius + b.radius) * (a.radius + b.radius);
    }
    pub fn updateOnCollision(a: *Particle, b: *Particle) void {
        var a2b = math.Vec2.new(b.pos.x - a.pos.x, b.pos.y - a.pos.y);
        const a2b_norm = std.math.sqrt(a2b.x * a2b.x + a2b.y * a2b.y);
        a2b.x = (1.0 / a2b_norm) * a2b.x;
        a2b.y = (1.0 / a2b_norm) * a2b.y;
        const overlap = (a.radius + b.radius) - a2b_norm;
        const ab_mass = a.mass + b.mass;
        a.pos.x = a.pos.x - a2b.x * (World.Stiffness * overlap * b.mass / ab_mass);
        a.pos.y = a.pos.y - a2b.y * (World.Stiffness * overlap * b.mass / ab_mass);
        b.pos.x = b.pos.x + a2b.x * (World.Stiffness * overlap * a.mass / ab_mass);
        b.pos.y = b.pos.y + a2b.y * (World.Stiffness * overlap * a.mass / ab_mass);
    }
};

const AABB = struct {
    top_left: math.Vec2 = math.Vec2.zero,
    width: f32 = 1.0,
    height: f32 = 1.0,
    pub fn center(self: AABB) math.Vec2 {
        return math.Vec2.new(self.top_left.x + self.width / 2, self.top_left.y + self.height / 2);
    }
    pub fn isColliding(a: AABB, p: Particle) bool {
        const aabb_center = a.center();
        const a2b = math.Vec2.new(aabb_center.x - p.pos.x, aabb_center.y - p.pos.y);
        const a2b_clamp = math.Vec2.new(std.math.clamp(a2b.x, -a.width / 2.0, a.width / 2.0), std.math.clamp(a2b.y, -a.height / 2.0, a.height / 2.0));
        const dist = math.Vec2.new(aabb_center.x + a2b_clamp.x - p.pos.x, aabb_center.y + a2b_clamp.y - p.pos.y);
        return dist.x * dist.x + dist.y * dist.y > p.radius * p.radius;
    }
};

const SpatialHashMap = struct {
    const BucketSize = World.Height / 8.0;

    const Point = struct { x: i32, y: i32 }; // Coordinates in bucket grid
    const Map = std.AutoHashMap(Point, std.ArrayList(*Particle));

    pub const ParticlePair = struct { a: *Particle, b: *Particle };

    allocator: Allocator,
    buckets: Map,
    result: std.AutoHashMap(ParticlePair, bool),
    pub fn init(allocator: Allocator) !SpatialHashMap {
        return SpatialHashMap{ .allocator = allocator, .buckets = Map.init(allocator), .result = std.AutoHashMap(ParticlePair, bool).init(allocator) };
    }
    pub fn deinit(self: *SpatialHashMap) void {
        // Deinit the buckets arrays
        var iterator = self.buckets.valueIterator();
        while (iterator.next()) |arr| {
            arr.deinit();
        }
        self.buckets.deinit();
        self.result.deinit();
    }
    pub fn getCollisions(self: *SpatialHashMap, particles: *[World.N]Particle) !std.AutoHashMap(ParticlePair, bool).Iterator {
        self.clear();
        for (particles) |*p| {
            // The clamping is there as a safety precaution
            const x = std.math.clamp(p.pos.x, -World.AspectRatio, World.AspectRatio);
            const y = std.math.clamp(p.pos.y, -1.0, 1.0);
            var xmin = @floatToInt(i32, World.Width * (x - p.radius) / BucketSize);
            const xmax = @floatToInt(i32, World.Width * (x + p.radius) / BucketSize);
            while (xmin <= xmax) : (xmin += 1) {
                var ymin = @floatToInt(i32, World.Height * (y - p.radius) / BucketSize);
                const ymax = @floatToInt(i32, World.Height * (y + p.radius) / BucketSize);
                while (ymin <= ymax) : (ymin += 1) {
                    const vec = Point{ .x = xmin, .y = ymin };
                    if (!self.buckets.contains(vec)) {
                        try self.buckets.put(vec, std.ArrayList(*Particle).init(self.allocator));
                    } else {
                        for (self.buckets.get(vec).?.items) |a| {
                            try self.result.put(ParticlePair{ .a = a, .b = p }, a.isColliding(p.*));
                        }
                    }
                    try (self.buckets.getPtr(vec).?).append(p);
                }
            }
        }
        return self.result.iterator();
    }
    pub fn clear(self: *SpatialHashMap) void {
        // Clear the buckets arrays
        var iterator = self.buckets.valueIterator();
        while (iterator.next()) |arr| {
            arr.clearRetainingCapacity();
        }
        // Clear the result array
        self.result.clearRetainingCapacity();
    }
};

const World = struct {
    pub const Width = 1_280;
    pub const Height = 720;
    pub const AspectRatio: f32 = @intToFloat(f32, Width) / @intToFloat(f32, Height);

    const N = 1000;
    pub const Stiffness = 0.5;
    const Gravity = -0.2;
    const Iterations = 4;
    const Density = 10;

    particles: [N]Particle,
    pos: [4 * N]f32,
    view_proj: math.Mat4 = math.Mat4.identity,
    random: std.rand.Random,
    pub fn init() World {
        var world = World{ .particles = [_]Particle{Particle{}} ** N, .pos = [_]f32{0.0} ** (4 * N), .random = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp())).random() };
        const view_mat = math.Mat4.createLookAt(math.Vec3.new(0.0, 0.0, 1.0), math.Vec3.new(0.0, 0.0, 0.0), math.Vec3.new(0, 1.0, 0));
        const projection_mat = math.Mat4.createPerspective(math.toRadians(90.0), AspectRatio, 0.1, 100);
        world.view_proj = math.Mat4.mul(view_mat, projection_mat);
        world.setRandomParticles();
        // Set up the particle that will follow the cursor
        var cursor_particle = &world.particles[0];
        cursor_particle.mass = std.math.f16_max;
        cursor_particle.radius = 0.1;
        return world;
    }
    pub fn update(self: *World, spm: *SpatialHashMap, dt: f32) !void {
        var tmp: math.Vec2 = math.Vec2.zero;
        for (self.particles) |*p| {
            tmp = p.pos;
            p.pos.x = 2 * p.pos.x - p.pre_pos.x;
            p.pos.y = 2 * p.pos.y - p.pre_pos.y + dt * dt * Gravity;
            p.pre_pos = tmp;
        }

        var k: u32 = 0;
        while (k < Iterations) : (k += 1) {
            var iterator = try spm.getCollisions(&self.particles);
            // Compute collisions
            while (iterator.next()) |item| {
                if (item.value_ptr.*) {
                    const a = item.key_ptr.*.a;
                    const b = item.key_ptr.*.b;
                    Particle.updateOnCollision(a, b);
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
    pub fn draw(self: *World, pr: *rend.ParticleRenderer) void {
        // Copy particles positions to pos
        var i: u32 = 0;
        while (i < self.particles.len) : (i += 1) {
            self.pos[4 * i] = self.particles[i].pos.x;
            self.pos[4 * i + 1] = self.particles[i].pos.y;
            self.pos[4 * i + 3] = self.particles[i].radius;
        }
        pr.draw(&self.pos, self.view_proj);
    }
    fn setRandomParticles(self: *World) void {
        for (self.particles) |*p| {
            p.radius = 0.01 * self.random.floatNorm(f32) + 0.03;
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
    const Width: f32 = @intToFloat(f32, World.Width);
    const Height: f32 = @intToFloat(f32, World.Height);

    const world: *World = window.getUserPointer(World).?;

    const x: f32 = @floatCast(f32, xpos);
    const y: f32 = @floatCast(f32, ypos);
    const cursor_position = math.Vec2.new(-mix(-World.AspectRatio, World.AspectRatio, x / Width), -mix(-1, 1, y / Height));

    var p = &world.particles[0];

    p.pos.x = mix(p.pos.x, cursor_position.x, 0.1 * World.Stiffness);
    p.pos.y = mix(p.pos.y, cursor_position.y, 0.1 * World.Stiffness);
    p.pre_pos = p.pos;
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());

    const gpa = general_purpose_allocator.allocator();

    try glfw.init(.{});
    defer glfw.terminate();

    // Create our window
    const window = try glfw.Window.create(World.Width, World.Height, "Particles demo", null, null, .{});
    defer window.destroy();

    var shm = try SpatialHashMap.init(gpa);
    defer shm.deinit();

    var world = World.init();

    window.setUserPointer(&world);
    window.setKeyCallback(key_callback);
    window.setCursorPosCallback(cursor_callback);

    try glfw.makeContextCurrent(window);

    // Set colors
    var colors: [4 * World.N]f32 = [_]f32{0.0} ** (4 * World.N);
    {
        var i: u32 = 4; // The first particle is the one that follows the cursor
        while (i < colors.len) : (i += 4) {
            colors[i] = 0.5 * world.random.float(f32) + 0.5;
            colors[i + 1] = 0.5 * world.random.float(f32) + 0.5;
            colors[i + 2] = 0.5 * world.random.float(f32) + 0.5;
        }
    }

    var pr = try rend.ParticleRenderer.init(&colors);
    defer pr.deinit();

    const dt: f64 = 1.0 / 20.0;

    var current_time: f64 = glfw.getTime();
    var accumulator: f64 = 0.0;

    var fps_counter_state: u32 = 0;
    var last_fps_display: f64 = current_time;
    var n_frames: f64 = 0.0;

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        // Reference: https://gafferongames.com/post/fix_your_timestep/
        const new_time: f64 = glfw.getTime();
        const frame_time = new_time - current_time;
        current_time = new_time;

        // FPS display logic
        if (fps_counter_state % 10 == 0) {
            std.log.info("FPS: {d:.1}", .{n_frames / (current_time - last_fps_display)});
            n_frames = 0;
            last_fps_display = current_time;
        }
        fps_counter_state += 1;
        n_frames += 1;

        // Update loop
        accumulator += frame_time;
        while (accumulator >= dt) : (accumulator -= dt) {
            // Update
            try glfw.pollEvents();
            try world.update(&shm, @floatCast(f32, dt));
        }
        // Draw
        gl.clear(.{ .color = true });
        world.draw(&pr);
        try window.swapBuffers();
    }
}
