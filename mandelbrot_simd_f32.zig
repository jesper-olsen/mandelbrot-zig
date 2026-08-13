/// Generates Mandelbrot set visualizations in ASCII or for gnuplot (SIMD, f32).
///
/// f32 + FMA variant of mandelbrot_simd.zig, structured to mirror the
/// mandelbrot-mojo kernel as closely as possible for a like-for-like
/// comparison, for a cross-language comparison project.
/// It parses command-line arguments in the format key=value.
///
/// Build:
/// zig build-exe mandelbrot_simd_f32.zig -O ReleaseFast
///
/// Usage:
/// ./mandelbrot_simd_f32
/// ./mandelbrot_simd_f32 width=120 ll_x=-0.75 ll_y=0.1 ur_x=-0.74 ur_y=0.11
/// ./mandelbrot_simd_f32 png=1 width=800 height=600 > mandelbrot.dat
const std = @import("std");

const VEC_LEN = 8; // 2x native f32 NEON width (4), matching mandelbrot-mojo

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
    const idx: usize = @intFromFloat(@as(f64, @floatFromInt(value)) / @as(f64, @floatFromInt(max_iter)) * @as(f64, @floatFromInt(ns - 1)));
    return symbols[idx];
}

/// Calculates the escape time for a single point (used for the remainder
/// of a row that doesn't fill a full SIMD batch). Same FMA-friendly
/// ordering as the vectorized kernel, so tail pixels behave identically.
fn escape_time(cr: f32, ci: f32, max_iter: i32) i32 {
    var x: f32 = 0.0;
    var y: f32 = 0.0;
    var iters: i32 = 0;
    var t = true;

    var iter: i32 = 0;
    while (iter < max_iter) : (iter += 1) {
        if (!t) break;

        const y2 = y * y;
        y = @mulAdd(f32, x, y + y, ci);
        t = @mulAdd(f32, x, x, y2) <= 4.0;
        x = @mulAdd(f32, x, x, cr - y2);

        if (t) iters += 1;
    }

    return max_iter - iters;
}

/// Calculates the escape time for `n` points at once, mirroring the
/// mandelbrot-mojo kernel: three fused multiply-adds per iteration, and
/// `t` recomputed fresh each pass rather than ANDed with prior state -
/// safe because once |z| > 2 the orbit provably diverges from there on.
fn escape_time_vec(comptime n: usize, cr: @Vector(n, f32), ci: @Vector(n, f32), max_iter: i32) @Vector(n, i32) {
    var x: @Vector(n, f32) = @splat(0.0);
    var y: @Vector(n, f32) = @splat(0.0);
    var iters: @Vector(n, i32) = @splat(0);
    var t: @Vector(n, bool) = @splat(true);

    const ones: @Vector(n, i32) = @splat(1);
    const zeros: @Vector(n, i32) = @splat(0);
    const bound: @Vector(n, f32) = @splat(4.0);

    var iter: i32 = 0;
    while (iter < max_iter) : (iter += 1) {
        if (!@reduce(.Or, t)) break;

        const y2 = y * y;
        y = @mulAdd(@Vector(n, f32), x, y + y, ci);
        t = @mulAdd(@Vector(n, f32), x, x, y2) <= bound;
        x = @mulAdd(@Vector(n, f32), x, x, cr - y2);

        iters += @select(i32, t, ones, zeros);
    }

    const max_vec: @Vector(n, i32) = @splat(max_iter);
    return max_vec - iters;
}

/// Renders the Mandelbrot set as ASCII art to stdout.
fn ascii_output(config: Config, stdout: anytype) !void {
    const fwidth = config.ur_x - config.ll_x;
    const fheight = config.ur_y - config.ll_y;
    const width_f: f32 = @floatFromInt(config.width);

    var y: i32 = 0;
    while (y < config.height) : (y += 1) {
        const imag = config.ur_y - @as(f32, @floatFromInt(y)) * fheight / @as(f32, @floatFromInt(config.height));
        const imag_vec: @Vector(VEC_LEN, f32) = @splat(imag);

        var x: i32 = 0;
        while (x + VEC_LEN <= config.width) : (x += VEC_LEN) {
            const x_f: f32 = @floatFromInt(x);
            var real_arr: [VEC_LEN]f32 = undefined;
            for (0..VEC_LEN) |lane| {
                const lane_f: f32 = @floatFromInt(lane);
                real_arr[lane] = config.ll_x + (x_f + lane_f) * fwidth / width_f;
            }
            const real_vec: @Vector(VEC_LEN, f32) = real_arr;

            const values_vec = escape_time_vec(VEC_LEN, real_vec, imag_vec, config.max_iter);
            const values: [VEC_LEN]i32 = values_vec;

            for (values) |v| {
                try stdout.writeByte(cnt2char(v, config.max_iter));
            }
        }

        while (x < config.width) : (x += 1) {
            const real = config.ll_x + @as(f32, @floatFromInt(x)) * fwidth / width_f;
            const iter = escape_time(real, imag, config.max_iter);
            try stdout.writeByte(cnt2char(iter, config.max_iter));
        }

        try stdout.writeByte('\n');
    }
}

/// Generates text output suitable for gnuplot to stdout.
fn gptext_output(config: Config, stdout: anytype) !void {
    const fwidth = config.ur_x - config.ll_x;
    const fheight = config.ur_y - config.ll_y;
    const width_f: f32 = @floatFromInt(config.width);

    var y: i32 = config.height;
    while (y > 0) : (y -= 1) {
        const imag = config.ur_y - @as(f32, @floatFromInt(y)) * fheight / @as(f32, @floatFromInt(config.height));
        const imag_vec: @Vector(VEC_LEN, f32) = @splat(imag);

        var x: i32 = 0;
        while (x + VEC_LEN <= config.width) : (x += VEC_LEN) {
            const x_f: f32 = @floatFromInt(x);
            var real_arr: [VEC_LEN]f32 = undefined;
            for (0..VEC_LEN) |lane| {
                const lane_f: f32 = @floatFromInt(lane);
                real_arr[lane] = config.ll_x + (x_f + lane_f) * fwidth / width_f;
            }
            const real_vec: @Vector(VEC_LEN, f32) = real_arr;

            const values_vec = escape_time_vec(VEC_LEN, real_vec, imag_vec, config.max_iter);
            const values: [VEC_LEN]i32 = values_vec;

            for (values, 0..) |v, lane| {
                const idx = x + @as(i32, @intCast(lane));
                if (idx > 0) {
                    try stdout.writeAll(", ");
                }
                try stdout.print("{d}", .{v});
            }
        }

        while (x < config.width) : (x += 1) {
            if (x > 0) {
                try stdout.writeAll(", ");
            }
            const real = config.ll_x + @as(f32, @floatFromInt(x)) * fwidth / width_f;
            const iter = escape_time(real, imag, config.max_iter);
            try stdout.print("{d}", .{iter});
        }

        try stdout.writeByte('\n');
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

    if (config.png) {
        try gptext_output(config, stdout);
    } else {
        try ascii_output(config, stdout);
    }

    try stdout.flush();
    try stderr.flush();
}
