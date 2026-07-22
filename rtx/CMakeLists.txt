cmake_minimum_required(VERSION 3.20)
project(sov_rtx C Fortran)

option(SOV_BUILD_CUDA  "Build CUDA PTX kernels" ON)
option(SOV_ZERO_LIBC   "Zero-libc entry point"  ON)

# Core static library
add_library(sov_rtx STATIC
    src/loader/gguf.c
    src/fortran/transformer_kernel.f90
    windows_rtx/cuda_driver_loader.c
    windows_rtx/power_handler.c
)
target_include_directories(sov_rtx PUBLIC include)

# Fortran 2018
set_property(TARGET sov_rtx PROPERTY Fortran_STANDARD 2018)

# Zero-libc executable
if(SOV_ZERO_LIBC)
    add_executable(sov_main windows_rtx/main.c)
    target_link_libraries(sov_main PRIVATE sov_rtx)
    if(MSVC)
        target_link_options(sov_main PRIVATE /NODEFAULTLIB /ENTRY:sov_main)
    else()
        target_link_options(sov_main PRIVATE -nostdlib -e sov_main)
    endif()
endif()

# CUDA PTX validation (requires nvcc)
if(SOV_BUILD_CUDA)
    find_program(NVCC nvcc)
    if(NVCC)
        add_custom_target(validate_ptx
            COMMAND ${NVCC} --ptx -arch=sm_89 --dryrun
                    ${CMAKE_CURRENT_SOURCE_DIR}/src/cuda/flash_attention.ptx
            COMMENT "Validating flash_attention.ptx for sm_89"
        )
    endif()
endif()

# C-- scheduler (documentation target — compiled by GHC/CM2)
add_custom_target(cmm_info
    COMMAND ${CMAKE_COMMAND} -E echo "C-- scheduler: src/c--/scheduler.cmm (GHC C-- backend)"
)
