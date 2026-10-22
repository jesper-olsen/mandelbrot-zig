# Mandelbrot in Zig

This repository contains a modern Zig (0.15.2) implementation for generating visualizations of the Mandelbrot set. It is part of a larger project comparing implementations across various programming languages.

The program compiles to a single native executable. It can render the Mandelbrot set directly to the terminal as ASCII art or produce a data file for `gnuplot` to generate a high-resolution PNG image.

### Other Language Implementations

This project compares the performance and features of Mandelbrot set generation in different languages.
Single Thread/Multi-thread shows the number of seconds it takes to do a 5000x5000 calculation.


| Language                                                       | Single Thread   | Multi-Thread | Simd | Multi-Thread + Simd |
| :------------------------------------------------------------- | ---------------:| -----------: | ----:| ------------------: |
| [Awk](https://github.com/jesper-olsen/mandelbrot-awk)          |           146.3 |              |      |                     |
| [C](https://github.com/jesper-olsen/mandelbrot-c)              |             3.6 |          0.6 |  0.7 |               0.2   |
| [C++](https://github.com/jesper-olsen/mandelbrot-cpp)          |             3.7 |          0.6 |  0.7 |               0.2   |
| [Erlang](https://github.com/jesper-olsen/mandelbrot_erl)       |            35.6 |          8.3 |      |                     |
| [Fortran](https://github.com/jesper-olsen/mandelbrot-f)        |             4.5 |              |      |                     |
| [Go](https://github.com/jesper-olsen/mandelbrot-go)            |             4.1 |          0.8 |  1.3 |               0.4   |
| [Goose](https://github.com/jesper-olsen/mandelbrot-goose)      |             3.9 |              |      |                     |
| [Java](https://github.com/jesper-olsen/mandelbrot-java)        |             3.9 |          0.8 |  1.4 |               0.5   |
| [Lean](https://github.com/jesper-olsen/mandelbrot-lean)        |             4.0 |              |      |                     |
| [Lua](https://github.com/jesper-olsen/mandelbrot-lua)          |            33.2 |              |      |                     |
| [Mojo](https://github.com/jesper-olsen/mandelbrot-mojo)        |             3.8 |          1.2 |  0.7 |               0.4   |
| [Odin](https://github.com/jesper-olsen/mandelbrot-odin)        |             4.4 |              |      |                     |
| [Py](https://github.com/jesper-olsen/mandelbrot-py)            |     (pure) 93.3 | (jax)    5.9 |      |                     |
| [R](https://github.com/jesper-olsen/mandelbrot-R)              |           335.0 |              |      |                     |
| [Rust](https://github.com/jesper-olsen/mandelbrot-rs)          |             4.7 |          1.3 |  1.4 |               0.8   |
| [Swift](https://github.com/jesper-olsen/mandelbrot-swift)      |             4.5 |          1.2 |  1.3 |               0.7   |
| [Tcl](https://github.com/jesper-olsen/mandelbrot-tcl)          |           306.9 |              |      |                     |
| [Typescript](https://github.com/jesper-olsen/mandelbrot-ts)    |             4.1 |          0.8 |      |                     |
| **[Zig](https://github.com/jesper-olsen/mandelbrot-zig)**      |             4.9 |          0.9 |  0.7 |               0.3   |
|                                                                |                 |              |      |                     |
| [Bash5.3](https://github.com/jesper-olsen/mandelbrot-bash)     |         10187.3 |              |      |                     |
| [Zsh](https://github.com/jesper-olsen/mandelbrot-bash)         |          2683.6 |              |      |                     |
| [Ksh (93u+m)](https://github.com/jesper-olsen/mandelbrot-bash) |          1271.5 |              |      |                     |
| [Nu](https://github.com/jesper-olsen/mandelbrot-nu)            |   (est) 17186.6 |              |      |                     |

---

## Prerequisites

You will need the following installed:

1.  **Zig 0.16.0** (or compatible version).
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
time ./mandelbrot png=1 width=1000 height=750 > image.dat
0.18s user 0.00s system 98% cpu 0.185 total
```

**Generating a 5000x5000 data file (single-threaded):**
```sh
time ./mandelbrot png=1 width=5000 height=5000 > image.dat
4.83s user 0.05s system 99% cpu 4.897 total

```

**Generating a 5000x5000 data file (multi-threaded, 9 threads):**
```sh
time ./mandelbrot_threaded png=1 width=5000 height=5000 > image.dat
6.69s user 0.10s system 744% cpu 0.912 total
```

**Generating a 5000x5000 data file with SIMD (f32):**
```sh
time ./mandelbrot_simd_f32 png=1 width=5000 height=5000 > image.dat
0.61s user 0.04s system 97% cpu 0.663 total
```

**Generating a 5000x5000 data file with SIMD and multi-threading:**
```sh
time ./mandelbrot_simd_threaded png=1 width=5000 height=5000 > image.dat
1.94s user 0.07s system 563% cpu 0.356 total
```

**Generating a 5000x5000 data file with SIMD (f32) and multi-threading:**
```sh
time ./mandelbrot_simd_threaded_f32 png=1 width=5000 height=5000 > image.dat
1.74s user 0.06s system 543% cpu 0.332 total
```

**Generating a 20000x20000 data file with SIMD (f32) and multi-threading:**
```sh
time ./mandelbrot_simd_threaded_f32 png=1 width=20000 height=20000 > image.dat
image.dat  25.94s user 0.85s system 532% cpu 5.029 total
```

---
