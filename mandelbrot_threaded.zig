/// Generates Mandelbrot set visualizations in ASCII or for gnuplot (multithreaded).
///
/// A modern Zig implementation with thread pool parallelization.
/// It parses command-line arguments in the format key=value.
///
/// Build:
/// zig build-exe mandelbrot_threaded.zig -O ReleaseFast
///
/// Usage:
/// ./mandelbrot_threaded
/// ./mandelbrot_threaded width=120 ll_x=-0.75 ll_y=0.1 ur_x=-0.74 ur_y=0.11
/// ./mandelbrot_threaded png=1 width=800 height=600 > mandelbrot.dat
const std = @import("std");

const NUM_THREADS = 9; // Adjust based on CPU core count
const CHUNK_SIZE = 1; // Number of rows to process per task

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

/// Calculates the escape time for a point in the complex plane.
inline fn escape_time(cr: f64, ci: f64, max_iter: i32) i32 {
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

/// Thread work context
const WorkContext = struct {
    config: *const Config,
    result_buffer: []i32,
    next_y: *std.atomic.Value(i32),
};

/// Worker function that processes chunks of rows
fn workerFunction(ctx: *WorkContext) void {
    const config = ctx.config;
    const buffer = ctx.result_buffer;
    const fwidth = config.ur_x - config.ll_x;
    const fheight = config.ur_y - config.ll_y;

    while (true) {
        // Atomically get the next chunk of rows to process
        const y_start = ctx.next_y.fetchAdd(CHUNK_SIZE, .monotonic);
        if (y_start >= config.height) {
            break;
        }

        const y_end = @min(y_start + CHUNK_SIZE, config.height);

        var y = y_start;
        while (y < y_end) : (y += 1) {
            var x: i32 = 0;
            while (x < config.width) : (x += 1) {
                const real = config.ll_x + @as(f64, @floatFromInt(x)) * fwidth / @as(f64, @floatFromInt(config.width));
                const imag = config.ur_y - @as(f64, @floatFromInt(y)) * fheight / @as(f64, @floatFromInt(config.height));
                const iter = escape_time(real, imag, config.max_iter);
                const idx = @as(usize, @intCast(y * config.width + x));
                buffer[idx] = iter;
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = Config{};

    // Set up buffered I/O
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    // Parse arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        try parse_arg(arg, &config, stderr);
    }

    // Allocate result buffer
    const total_pixels = @as(usize, @intCast(config.width * config.height));
    const result_buffer = try allocator.alloc(i32, total_pixels);
    defer allocator.free(result_buffer);

    // Initialize thread pool
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator, .n_jobs = NUM_THREADS });
    defer pool.deinit();

    // Atomic counter for distributing work
    var next_y = std.atomic.Value(i32).init(0);

    // Create work context
    var ctx = WorkContext{
        .config = &config,
        .result_buffer = result_buffer,
        .next_y = &next_y,
    };

    // Use WaitGroup to synchronize threads
    var wg = std.Thread.WaitGroup{};

    // Spawn worker threads
    var i: usize = 0;
    while (i < NUM_THREADS) : (i += 1) {
        pool.spawnWg(&wg, workerFunction, .{&ctx});
    }

    // Wait for all workers to complete
    wg.wait();

    // Output results
    try finalOutput(&config, result_buffer, stdout);
    try stdout.flush();
    try stderr.flush();
}
