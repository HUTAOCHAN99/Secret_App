cmake_minimum_required(VERSION 3.18.1)

project("steganography")

# Set compiler flags untuk Windows
if (WIN32)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DWIN32")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DWIN32")
endif()

add_library(
    steganography
    SHARED
    "../lib/steganography/steganography.c"
    "../lib/steganography/steganography.h"
)

# Untuk Windows, kita perlu export functions
if (WIN32)
    set_target_properties(steganography PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS TRUE
    )
endif()

target_include_directories(steganography PRIVATE "../lib/steganography")