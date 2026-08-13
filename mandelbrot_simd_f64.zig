/// Generates Mandelbrot set visualizations in ASCII or for gnuplot (SIMD).
///
/// A modern Zig implementation using @Vector for SIMD parallelism,
/// for a cross-language comparison project.
/// It parses command-line arguments in the format key=value.
///
/// Build:
/// zig build-exe mandelbrot_simd.zig -O ReleaseFast
///
/// Usage:
/// ./mandelbrot_simd
/// ./mandelbrot_simd width=120 ll_x=-0.75 ll_y=0.1 ur_x=-0.74 ur_y=0.11
/// ./mandelbrot_simd png=1 width=800 height=600 > mandelbrot.dat
const std = @import("std");

const VEC_LEN = 4; // Tune to taste - see note below on Apple Silicon NEON width

const Config = struct {
    width: i32 = 100,
    height: i32 = 75,
    png: bool = false,
    ll_x: f64 = -1.2,
    ll_y: f64 = 0.20,
    ur_x: f64 = -1.0,
    ur_y: f64 = 0.35,
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
/// of a row that doesn't fill a full SIMD batch).
fn escape_time(cr: f64, ci: f64, max_iter: i32) i32 {
    var zr: f64 = 0.0;
    var zi: f64 = 0.0;
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

/// Calculates the escape time for `n` points at once.
///
/// `active` tracks, per lane, whether that point hasn't escaped yet as of
/// the current check. Once a lane's magnitude exceeds the bound, `active`
/// for that lane goes false and stays false (false & anything = false),
/// so its count stops advancing - matching the scalar version's early
/// `break` exactly, just done per-lane instead of per-loop-exit.
fn escape_time_vec(comptime n: usize, cr: @Vector(n, f64), ci: @Vector(n, f64), max_iter: i32) @Vector(n, i32) {
    var zr: @Vector(n, f64) = @splat(0.0);
    var zi: @Vector(n, f64) = @splat(0.0);
    var iter_count: @Vector(n, i32) = @splat(0);
    var active: @Vector(n, bool) = @splat(true);

    const ones: @Vector(n, i32) = @splat(1);
    const zeros: @Vector(n, i32) = @splat(0);
    const bound: @Vector(n, f64) = @splat(4.0);
    const two: @Vector(n, f64) = @splat(2.0);

    var iter: i32 = 0;
    while (iter < max_iter) : (iter += 1) {
        const zr2 = zr * zr;
        const zi2 = zi * zi;
        const mag2 = zr2 + zi2;
        active = active & (mag2 <= bound);

        // Once every lane in this batch has escaped, stop early - the
        // SIMD equivalent of the scalar function's per-point break.
        if (!@reduce(.Or, active)) break;

        iter_count += @select(i32, active, ones, zeros);

        const tmp = zr2 - zi2 + cr;
        zi = two * zr * zi + ci;
        zr = tmp;
    }

    const max_vec: @Vector(n, i32) = @splat(max_iter);
    return max_vec - iter_count;
}

/// Renders the Mandelbrot set as ASCII art to stdout.
fn ascii_output(config: Config, stdout: anytype) !void {
    const fwidth = config.ur_x - config.ll_x;
    const fheight = config.ur_y - config.ll_y;
    const width_f = @as(f64, @floatFromInt(config.width));

    var y: i32 = 0;
    while (y < config.height) : (y += 1) {
        const imag = config.ur_y - @as(f64, @floatFromInt(y)) * fheight / @as(f64, @floatFromInt(config.height));
        const imag_vec: @Vector(VEC_LEN, f64) = @splat(imag);

        var x: i32 = 0;
        while (x + VEC_LEN <= config.width) : (x += VEC_LEN) {
            const x_f = @as(f64, @floatFromInt(x));
            var real_arr: [VEC_LEN]f64 = undefined;
            for (0..VEC_LEN) |lane| {
                const lane_f = @as(f64, @floatFromInt(lane));
                real_arr[lane] = config.ll_x + (x_f + lane_f) * fwidth / width_f;
            }
            const real_vec: @Vector(VEC_LEN, f64) = real_arr;

            const values_vec = escape_time_vec(VEC_LEN, real_vec, imag_vec, config.max_iter);
            const values: [VEC_LEN]i32 = values_vec; // coerce to array before indexing

            for (values) |v| {
                try stdout.writeByte(cnt2char(v, config.max_iter));
            }
        }

        // Remainder pixels that don't fill a full SIMD batch
        while (x < config.width) : (x += 1) {
            const real = config.ll_x + @as(f64, @floatFromInt(x)) * fwidth / width_f;
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
    const width_f = @as(f64, @floatFromInt(config.width));

    var y: i32 = config.height;
    while (y > 0) : (y -= 1) {
        const imag = config.ur_y - @as(f64, @floatFromInt(y)) * fheight / @as(f64, @floatFromInt(config.height));
        const imag_vec: @Vector(VEC_LEN, f64) = @splat(imag);

        var x: i32 = 0;
        while (x + VEC_LEN <= config.width) : (x += VEC_LEN) {
            const x_f = @as(f64, @floatFromInt(x));
            var real_arr: [VEC_LEN]f64 = undefined;
            for (0..VEC_LEN) |lane| {
                const lane_f = @as(f64, @floatFromInt(lane));
                real_arr[lane] = config.ll_x + (x_f + lane_f) * fwidth / width_f;
            }
            const real_vec: @Vector(VEC_LEN, f64) = real_arr;

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

        // Remainder pixels that don't fill a full SIMD batch
        while (x < config.width) : (x += 1) {
            if (x > 0) {
                try stdout.writeAll(", ");
            }
            const real = config.ll_x + @as(f64, @floatFromInt(x)) * fwidth / width_f;
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
        config.ll_x = try std.fmt.parseFloat(f64, value);
    } else if (std.mem.eql(u8, key, "ll_y")) {
        config.ll_y = try std.fmt.parseFloat(f64, value);
    } else if (std.mem.eql(u8, key, "ur_x")) {
        config.ur_x = try std.fmt.parseFloat(f64, value);
    } else if (std.mem.eql(u8, key, "ur_y")) {
        config.ur_y = try std.fmt.parseFloat(f64, value);
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
