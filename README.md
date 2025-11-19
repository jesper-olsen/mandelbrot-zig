# Mandelbrot in Zig

This repository contains a modern Zig (0.15.2) implementation for generating visualizations of the Mandelbrot set. It is part of a larger project comparing implementations across various programming languages.

The program compiles to a single native executable. It can render the Mandelbrot set directly to the terminal as ASCII art or produce a data file for `gnuplot` to generate a high-resolution PNG image.

### Other Language Implementations

This project compares the performance and features of Mandelbrot set generation in different languages.
Single Thread/Multi-thread shows the number of seconds it takes to do a 5000x5000 calculation.

| Language    | Repository                                                         | Single Thread   | Multi-Thread |
| :--------   | :----------------------------------------------------------------- | ---------------:| -----------: |
| Awk         | [mandelbrot-awk](https://github.com/jesper-olsen/mandelbrot-awk)   |           805.9 |              |
| C           | [mandelbrot-c](https://github.com/jesper-olsen/mandelbrot-c)       |             9.1 |          3.0 |
| Erlang      | [mandelbrot_erl](https://github.com/jesper-olsen/mandelbrot_erl)   |            56.0 |           16 |
| Fortran     | [mandelbrot-f](https://github.com/jesper-olsen/mandelbrot-f)       |            11.6 |              |
| Lua         | [mandelbrot-lua](https://github.com/jesper-olsen/mandelbrot-lua)   |           158.2 |              |
| Mojo        | [mandelbrot-mojo](https://github.com/jesper-olsen/mandelbrot-mojo) |            39.6 |         39.2 |
| Nushell     | [mandelbrot-nu](https://github.com/jesper-olsen/mandelbrot-nu)     |   (est) 11488.5 |              |
| Python      | [mandelbrot-py](https://github.com/jesper-olsen/mandelbrot-py)     |    (pure) 177.2 | (jax)    7.5 |
| R           | [mandelbrot-R](https://github.com/jesper-olsen/mandelbrot-R)       |           562.0 |              |
| Rust        | [mandelbrot-rs](https://github.com/jesper-olsen/mandelbrot-rs)     |             8.9 |          2.5 |
| Tcl         | [mandelbrot-tcl](https://github.com/jesper-olsen/mandelbrot-tcl)   |           706.1 |              |
| **Zig**     | [mandelbrot-zig](https://github.com/jesper-olsen/mandelbrot-zig)   |             8.6 |          1.9 |

---

## Prerequisites

You will need the following installed:

1.  **Zig 0.15.2** (or compatible version).
2.  **Gnuplot** (required *only* for generating PNG images).

---

## Build

Zig makes building simple with its built-in build system.

**Single-threaded version:**
```sh
zig build-exe mandelbrot.zig -O ReleaseFast
```

**Multi-threaded version:**
```sh
zig build-exe mandelbrot_threaded.zig -O ReleaseFast
```

The `-O ReleaseFast` flag enables aggressive optimizations for maximum performance, similar to `-O3` in C compilers.

---

## Usage

The compiled executable can be configured via command-line arguments using a `key=value` format.

### 1. ASCII Art Output

To render the Mandelbrot set directly in your terminal, run the executable.

```sh
./mandelbrot
```

You can change the view and resolution by passing parameters:
```sh
# Zoom in on a different area with a wider view
./mandelbrot width=120 ll_x=-0.75 ll_y=0.1 ur_x=-0.74 ur_y=0.11
```

### 2. PNG Image Generation

To create a high-resolution PNG, you first generate a data file and then process it with `gnuplot`.

**Step 1: Generate the data file**
Set `png=1` and specify the desired dimensions. Redirect the output to a file.

```sh
./mandelbrot png=1 width=1000 height=750 > image.dat
```

**Step 2: Run gnuplot**
This will read `image.dat` and create `mandelbrot.png`.

```sh
gnuplot topng.gp
```
The result is a high-quality `mandelbrot.png` image.

![PNG Image of the Mandelbrot Set](mandelbrot.png)

---

## Performance

Benchmarks were run on an **Apple M1** system with Zig 0.15.2.

**Generating a 1000x750 data file (single-threaded):**
```sh
% time ./mandelbrot png=1 width=1000 height=750 > image.dat
0.29s user 0.01s system 97% cpu 0.308 total
```

**Generating a 5000x5000 data file (single-threaded):**
```sh
% time ./mandelbrot png=1 width=5000 height=5000 > image.dat
8.26s user 0.12s system 97% cpu 8.585 total
```

**Generating a 5000x5000 data file (multi-threaded, 9 threads):**
```sh
% time ./mandelbrot_threaded png=1 width=5000 height=5000 > image.dat
10.91s user 0.16s system 585% cpu 1.890 total
```

The multi-threaded version achieves approximately **4.5x speedup** over the single-threaded implementation, demonstrating excellent parallel scaling on the M1's performance cores.

---

## Implementation Notes

### Memory Safety
Zig provides compile-time memory safety guarantees that eliminate entire classes of bugs common in C:
- No buffer overflows
- No null pointer dereferences
- No use-after-free errors

### Threading
The multi-threaded implementation uses Zig's standard library threading primitives:
- `std.Thread` for thread management
- `std.atomic.Value` for lock-free work distribution
- Dynamic work stealing via atomic fetch-and-add pattern

### Performance
Zig's `-O ReleaseFast` mode produces highly optimized machine code comparable to C's `-O3`:
- Aggressive inlining of hot functions
- SIMD optimizations where applicable
- Minimal runtime overhead
- Zero-cost abstractions

The Zig implementation matches C's performance while providing better safety guarantees and a more modern development experience.
