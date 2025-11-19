/// Generates Mandelbrot set visualizations in ASCII or for gnuplot.
///
/// A modern Zig implementation for a cross-language comparison project.
/// It parses command-line arguments in the format key=value.
///
/// Build:
/// zig build-exe mandelbrot.zig -O ReleaseFast
///
/// Usage:
/// ./mandelbrot
/// ./mandelbrot width=120 ll_x=-0.75 ll_y=0.1 ur_x=-0.74 ur_y=0.11
/// ./mandelbrot png=1 width=800 height=600 > mandelbrot.dat

const std = @import("std");

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
    // Map the value [0, max_iter] to an index [0, ns-1]
    const idx: usize = @intFromFloat(@as(f64, @floatFromInt(value)) / @as(f64, @floatFromInt(max_iter)) * @as(f64, @floatFromInt(ns - 1)));
    return symbols[idx];
}

/// Calculates the escape time for a point in the complex plane.
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

/// Renders the Mandelbrot set as ASCII art to stdout.
fn ascii_output(config: Config, stdout: anytype) !void {
    const fwidth = config.ur_x - config.ll_x;
    const fheight = config.ur_y - config.ll_y;

    var y: i32 = 0;
    while (y < config.height) : (y += 1) {
        var x: i32 = 0;
        while (x < config.width) : (x += 1) {
            const real = config.ll_x + @as(f64, @floatFromInt(x)) * fwidth / @as(f64, @floatFromInt(config.width));
            const imag = config.ur_y - @as(f64, @floatFromInt(y)) * fheight / @as(f64, @floatFromInt(config.height));
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

    var y: i32 = config.height;
    while (y > 0) : (y -= 1) {
        var x: i32 = 0;
        while (x < config.width) : (x += 1) {
            const real = config.ll_x + @as(f64, @floatFromInt(x)) * fwidth / @as(f64, @floatFromInt(config.width));
            const imag = config.ur_y - @as(f64, @floatFromInt(y)) * fheight / @as(f64, @floatFromInt(config.height));
            const iter = escape_time(real, imag, config.max_iter);
            // Print comma separator for all but the first value in a row
            if (x > 0) {
                try stdout.writeAll(", ");
            }
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

pub fn main() !void {
    var config = Config{};

    // Set up buffered stdout
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Set up buffered stderr
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    while (args.next()) |arg| {
        try parse_arg(arg, &config, stderr);
    }

    if (config.png) {
        try gptext_output(config, stdout);
    } else {
        try ascii_output(config, stdout);
    }

    // Flush the output buffer
    try stdout.flush();
    try stderr.flush();
}
