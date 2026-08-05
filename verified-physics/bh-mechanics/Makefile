FC = gfortran
CC = gcc
AR = ar

FFLAGS = -O3 -fPIC -std=f2018 -Wall -fcheck=bounds
CFLAGS = -O3 -fPIC -std=c11 -Wall -I./c -lm
BUILD  = build

all: $(BUILD)/libbh_numerics.a $(BUILD)/test_runner

$(BUILD)/libbh_numerics.a: fortran/bh_numerics.f90
	@mkdir -p $(BUILD)
	$(FC) $(FFLAGS) -c $< -o $(BUILD)/bh_numerics.o
	$(AR) rcs $@ $(BUILD)/bh_numerics.o

$(BUILD)/test_runner: c/test_runner.c c/bh_bridge.h $(BUILD)/libbh_numerics.a
	$(CC) $(CFLAGS) -o $@ c/test_runner.c -L$(BUILD) -lbh_numerics

test: $(BUILD)/test_runner
	./$(BUILD)/test_runner

clean:
	rm -rf $(BUILD)

.PHONY: all test clean
