# Makefile for Mandelbrot Zig implementations

ZIG = zig
ZIGFLAGS = -O ReleaseFast

SRC_SINGLE = mandelbrot.zig
SRC_THREADED = mandelbrot_threaded.zig

BIN_SINGLE = mandelbrot
BIN_THREADED = mandelbrot_threaded

.PHONY: all
all: $(BIN_SINGLE) $(BIN_THREADED)

$(BIN_SINGLE): $(SRC_SINGLE)
	$(ZIG) build-exe $(SRC_SINGLE) $(ZIGFLAGS)

$(BIN_THREADED): $(SRC_THREADED)
	$(ZIG) build-exe $(SRC_THREADED) $(ZIGFLAGS)

# Format source code using zig fmt
.PHONY: fmt
fmt:
	$(ZIG) fmt $(SRC_SINGLE) $(SRC_THREADED)

# Check formatting without modifying files
.PHONY: check-fmt
check-fmt:
	$(ZIG) fmt --check $(SRC_SINGLE) $(SRC_THREADED)

# Run tests (if any test files exist)
.PHONY: test
test:
	@if [ -f "test.zig" ]; then \
		$(ZIG) test test.zig; \
	else \
		echo "No test files found"; \
	fi

# Quick ASCII demo
.PHONY: demo
demo: $(BIN_SINGLE)
	./$(BIN_SINGLE)

.PHONY: png
png: $(BIN_THREADED)
	./$(BIN_THREADED) png=1 width=1000 height=750 > image.dat
	@echo "Generated image.dat - run 'gnuplot topng.gp' to create PNG"

.PHONY: bench-single
bench-single: $(BIN_SINGLE)
	time ./$(BIN_SINGLE) png=1 width=5000 height=5000 > /dev/null

.PHONY: bench-threaded
bench-threaded: $(BIN_THREADED)
	time ./$(BIN_THREADED) png=1 width=5000 height=5000 > /dev/null

.PHONY: bench
bench: bench-single bench-threaded

.PHONY: clean
clean:
	rm -f $(BIN_SINGLE) $(BIN_THREADED)
	rm -f *.o *.dat *.png
	rm -rf zig-cache zig-out

.PHONY: help
help:
	@echo "Mandelbrot Zig Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all             Build both single and multi-threaded versions (default)"
	@echo "  mandelbrot      Build single-threaded version"
	@echo "  mandelbrot_threaded  Build multi-threaded version"
	@echo "  fmt             Format source code with zig fmt"
	@echo "  check-fmt       Check if code is properly formatted"
	@echo "  test            Run tests (if test files exist)"
	@echo "  demo            Run ASCII art demo"
	@echo "  png             Generate sample PNG data file"
	@echo "  bench-single    Benchmark single-threaded version"
	@echo "  bench-threaded  Benchmark multi-threaded version"
	@echo "  bench           Run both benchmarks"
	@echo "  clean           Remove build artifacts"
	@echo "  help            Show this help message"
