CC := g++
HIPCC := hipcc
AS := as
ROCM_PATH ?= /opt/rocm

# Enable ASM primitives (comment out to disable)
USE_ASM_PRIMITIVES := 1

# AMD 7900 XTX uses gfx1100 architecture (RDNA 3)
# Aggressive optimization flags for maximum performance
CCFLAGS := -O3 -march=native -mtune=native -ffast-math -funroll-loops \
           -finline-functions -fomit-frame-pointer \
           -fno-stack-protector -fno-plt -fprefetch-loop-arrays \
           -ftree-vectorize \
           -I$(ROCM_PATH)/include -D__HIP_PLATFORM_AMD__

# Assembly flags for x86-64 with AVX2
# --64: Generate 64-bit code
# --noexecstack: Mark stack as non-executable (security)
# Note: GNU as doesn't support -march, CPU features are in the assembly code
ASFLAGS := --64 --noexecstack

ifdef USE_ASM_PRIMITIVES
CCFLAGS += -DUSE_ASM_PRIMITIVES
endif

# GPU optimization flags for AMD RDNA 3
# -O3: Maximum optimization
# -ffast-math: Aggressive math optimizations (safe for crypto operations)
# -fgpu-rdc: Relocatable device code for separate compilation
# -munsafe-fp-atomics: Faster atomic operations
# RDNA 3 uses wave32 natively
# LLVM optimizations for aggressive inlining and loop unrolling
HIPCCFLAGS := -O3 --offload-arch=gfx1100 -fgpu-rdc -D__HIP_PLATFORM_AMD__ \
              -ffast-math -munsafe-fp-atomics \
              -mllvm -amdgpu-early-inline-all=true \
              -mllvm -unroll-threshold=1000 \
              -mllvm -inline-threshold=10000 \
              -Rpass-analysis=kernel-resource-usage

LDFLAGS := -L$(ROCM_PATH)/lib -lamdhip64 -pthread

CPU_SRC := AMDKangaroo.cpp GpuKang.cpp Ec.cpp utils.cpp
GPU_SRC := AMDGpuCore.hip

CPP_OBJECTS := $(CPU_SRC:.cpp=.o)
HIP_OBJECTS := $(GPU_SRC:.hip=.o)

# ASM primitives (only if enabled)
ifdef USE_ASM_PRIMITIVES
ASM_SRC := secp256k1_asm_full.s inverse256_skylake.s
ASM_OBJECTS := $(ASM_SRC:.s=.o)
CPU_SRC += InvModP_wrapper.cpp
CPP_OBJECTS := $(CPU_SRC:.cpp=.o)
else
ASM_OBJECTS :=
endif

TARGET := amdkangaroo

all: $(TARGET)

$(TARGET): $(CPP_OBJECTS) $(HIP_OBJECTS) $(ASM_OBJECTS)
	$(HIPCC) --offload-arch=gfx1100 -fgpu-rdc $(CCFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.cpp
	$(CC) $(CCFLAGS) -c $< -o $@

%.o: %.hip
	$(HIPCC) $(HIPCCFLAGS) -c $< -o $@

%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@

clean:
	rm -f $(CPP_OBJECTS) $(HIP_OBJECTS) $(ASM_OBJECTS) $(TARGET)
