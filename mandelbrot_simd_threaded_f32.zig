/// Generates Mandelbrot set visualizations in ASCII or for gnuplot
/// (multithreaded + SIMD).
///
/// A modern Zig implementation combining thread pool parallelization
/// with @Vector SIMD, for a cross-language comparison project.
/// It parses command-line arguments in the format key=value.
///
/// Build:
/// zig build-exe mandelbrot_simd_threaded.zig -O ReleaseFast
///
/// Usage:
/// ./mandelbrot_simd_threaded
/// ./mandelbrot_simd_threaded width=120 ll_x=-0.75 ll_y=0.1 ur_x=-0.74 ur_y=0.11
/// ./mandelbrot_simd_threaded png=1 width=800 height=600 > mandelbrot.dat
const std = @import("std");

const NUM_THREADS = 9; // Adjust based on CPU core count
const CHUNK_SIZE = 1; // Number of rows to process per task
const VEC_LEN = 4; // SIMD lane count - tune to taste

const Config = struct {
    width: i32 = 100,
    height: i32 = 75,
    png: bool = false,
    ll_x: f32 = -1.2,
    ll_y: f32 = 0.20,
    ur_x: f32 = -1.0,
    ur_y: f32 = 0.35,
    max_iter: i32 = 255,
};

/// Maps an iteration count to an ASCII character.
fn cnt2char(value: i32, max_iter: i32) u8 {
    const symbols = "MW2a_. ";
    const ns = symbols.len;
    const idx: usize = @intFromFloat(@as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(max_iter)) * @as(f32, @floatFromInt(ns - 1)));
    return symbols[idx];
}

/// Calculates the escape time for a single point (used for the remainder
/// of a row that doesn't fill a full SIMD batch).
inline fn escape_time(cr: f32, ci: f32, max_iter: i32) i32 {
    var zr: f32 = 0.0;
    var zi: f32 = 0.0;
    var iter: i32 = 0;

    while (iter < max_iter) : (iter += 1) {
        const zr2 = zr * zr;
        const zi2 = zi * zi;
        if (zr2 + zi2 > 4.0) {
            break;
        }
        const tmp = zr2 - zi2 + cr;
        zi = 2.0 * zr * zi + ci;
        zr = tmp;
    }
    return max_iter - iter;
}

/// Calculates the escape time for `n` points at once. See the note in
/// mandelbrot_simd.zig - `active` only ever goes true -> false, so lane
/// counts stop advancing exactly where the scalar version would `break`.
fn escape_time_vec(comptime n: usize, cr: @Vector(n, f32), ci: @Vector(n, f32), max_iter: i32) @Vector(n, i32) {
    var zr: @Vector(n, f32) = @splat(0.0);
    var zi: @Vector(n, f32) = @splat(0.0);
    var iter_count: @Vector(n, i32) = @splat(0);
    var active: @Vector(n, bool) = @splat(true);

    const ones: @Vector(n, i32) = @splat(1);
    const zeros: @Vector(n, i32) = @splat(0);
    const bound: @Vector(n, f32) = @splat(4.0);
    const two: @Vector(n, f32) = @splat(2.0);

    var iter: i32 = 0;
    while (iter < max_iter) : (iter += 1) {
        const zr2 = zr * zr;
        const zi2 = zi * zi;
        const mag2 = zr2 + zi2;
        active = active & (mag2 <= bound);

        if (!@reduce(.Or, active)) break;

        iter_count += @select(i32, active, ones, zeros);

        const tmp = zr2 - zi2 + cr;
        zi = two * zr * zi + ci;
        zr = tmp;
    }

    const max_vec: @Vector(n, i32) = @splat(max_iter);
    return max_vec - iter_count;
}

/// Thread work context
const WorkContext = struct {
    config: *const Config,
    result_buffer: []i32,
    next_y: *std.atomic.Value(i32),
};

/// Worker function that processes chunks of rows, VEC_LEN pixels at a time.
/// Each worker only ever touches rows nobody else has claimed (via
/// next_y.fetchAdd), so writes into result_buffer need no locking.
fn workerFunction(ctx: *WorkContext) void {
    const config = ctx.config;
    const buffer = ctx.result_buffer;
    const fwidth = config.ur_x - config.ll_x;
    const fheight = config.ur_y - config.ll_y;
    const width_f = @as(f32, @floatFromInt(config.width));

    while (true) {
        const y_start = ctx.next_y.fetchAdd(CHUNK_SIZE, .monotonic);
        if (y_start >= config.height) {
            break;
        }

        const y_end = @min(y_start + CHUNK_SIZE, config.height);

        var y = y_start;
        while (y < y_end) : (y += 1) {
            const imag = config.ur_y - @as(f32, @floatFromInt(y)) * fheight / @as(f32, @floatFromInt(config.height));
            const imag_vec: @Vector(VEC_LEN, f32) = @splat(imag);
            const row_base = @as(usize, @intCast(y * config.width));

            var x: i32 = 0;
            while (x + VEC_LEN <= config.width) : (x += VEC_LEN) {
                const x_f = @as(f32, @floatFromInt(x));
                var real_arr: [VEC_LEN]f32 = undefined;
                for (0..VEC_LEN) |lane| {
                    const lane_f = @as(f32, @floatFromInt(lane));
                    real_arr[lane] = config.ll_x + (x_f + lane_f) * fwidth / width_f;
                }
                const real_vec: @Vector(VEC_LEN, f32) = real_arr;

                const values_vec = escape_time_vec(VEC_LEN, real_vec, imag_vec, config.max_iter);
                const values: [VEC_LEN]i32 = values_vec; // coerce to array before indexing

                const base_idx = row_base + @as(usize, @intCast(x));
                for (values, 0..) |v, lane| {
                    buffer[base_idx + lane] = v;
                }
            }

            // Remainder pixels that don't fill a full SIMD batch
            while (x < config.width) : (x += 1) {
                const real = config.ll_x + @as(f32, @floatFromInt(x)) * fwidth / width_f;
                const iter = escape_time(real, imag, config.max_iter);
                buffer[row_base + @as(usize, @intCast(x))] = iter;
            }
        }
    }
}

/// Output final results
fn finalOutput(config: *const Config, result_buffer: []const i32, stdout: anytype) !void {
    if (config.png) {
        // Output for gnuplot (reversed Y axis)
        var y: i32 = config.height - 1;
        while (y >= 0) : (y -= 1) {
            var x: i32 = 0;
            while (x < config.width) : (x += 1) {
                if (x > 0) {
                    try stdout.writeAll(", ");
                }
                const idx = @as(usize, @intCast(y * config.width + x));
                try stdout.print("{d}", .{result_buffer[idx]});
            }
            try stdout.writeByte('\n');
        }
    } else {
        // ASCII output
        var y: i32 = 0;
        while (y < config.height) : (y += 1) {
            var x: i32 = 0;
            while (x < config.width) : (x += 1) {
                const idx = @as(usize, @intCast(y * config.width + x));
                const iter = result_buffer[idx];
                try stdout.writeByte(cnt2char(iter, config.max_iter));
            }
            try stdout.writeByte('\n');
        }
    }
}

/// Parses a single "key=value" command-line argument.
fn parse_arg(arg: []const u8, config: *Config, stderr: anytype) !void {
    const eq_pos = std.mem.indexOf(u8, arg, "=") orelse {
        try stderr.print("Warning: Ignoring invalid argument '{s}'\n", .{arg});
        return;
    };

    const key = arg[0..eq_pos];
    const value = arg[eq_pos + 1 ..];

    if (std.mem.eql(u8, key, "width")) {
        config.width = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "height")) {
        config.height = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "png")) {
        const val = try std.fmt.parseInt(i32, value, 10);
        config.png = val != 0;
    } else if (std.mem.eql(u8, key, "ll_x")) {
        config.ll_x = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "ll_y")) {
        config.ll_y = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "ur_x")) {
        config.ur_x = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "ur_y")) {
        config.ur_y = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "max_iter")) {
        config.max_iter = try std.fmt.parseInt(i32, value, 10);
    } else {
        try stderr.print("Warning: Unknown parameter '{s}'\n", .{key});
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = Config{};

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    var args = init.minimal.args.iterate();
    _ = args.next(); // Skip program name

    while (args.next()) |arg| {
        try parse_arg(arg, &config, stderr);
    }

    const total_pixels = @as(usize, @intCast(config.width * config.height));
    const result_buffer = try allocator.alloc(i32, total_pixels);
    defer allocator.free(result_buffer);

    var next_y = std.atomic.Value(i32).init(0);

    var ctx = WorkContext{
        .config = &config,
        .result_buffer = result_buffer,
        .next_y = &next_y,
    };

    var group: std.Io.Group = .init;
    defer group.cancel(io);

    var i: usize = 0;
    while (i < NUM_THREADS) : (i += 1) {
        try group.concurrent(io, workerFunction, .{&ctx});
    }

    try group.await(io);

    try finalOutput(&config, result_buffer, stdout);
    try stdout.flush();
    try stderr.flush();
}
