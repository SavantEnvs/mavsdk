cmake_minimum_required(VERSION 3.22)
project(mavsdk_mayhem_harness C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(MAVSDK REQUIRED)
find_package(fmt REQUIRED)

set(MAVSDK_SRC "" CACHE PATH "MAVSDK checkout (for the internal log.hpp the harness includes)")
set(STANDALONE_FUZZ_MAIN "" CACHE FILEPATH "LLVM run-once driver (C source)")
set(FUZZER_NO_MAIN_LIB "" CACHE FILEPATH "libFuzzer runtime without main(): SanCov callbacks for the standalone")
set(LIB_FUZZING_ENGINE "-fsanitize=fuzzer" CACHE STRING "libFuzzer link flag")

set(LSAN_OFF_SRC "" CACHE FILEPATH "TU defining __lsan_is_turned_off()")
add_library(lsan_off OBJECT ${LSAN_OFF_SRC})
set_source_files_properties(${STANDALONE_FUZZ_MAIN} PROPERTIES LANGUAGE C)
add_library(standalone_main OBJECT ${STANDALONE_FUZZ_MAIN})

foreach(t mavlink_fuzzer mavlink_fuzzer-standalone)
    add_executable(${t} ${CMAKE_CURRENT_SOURCE_DIR}/../mavlink_fuzzer.cpp $<TARGET_OBJECTS:lsan_off>)
    target_compile_definitions(${t} PRIVATE MAVSDK_ENABLE_MAVLINK_C_API)
    target_include_directories(${t} PRIVATE ${MAVSDK_SRC}/cpp/src)
    target_link_libraries(${t} PRIVATE MAVSDK::mavsdk fmt::fmt)
endforeach()
target_link_libraries(mavlink_fuzzer PRIVATE ${LIB_FUZZING_ENGINE})
target_sources(mavlink_fuzzer-standalone PRIVATE $<TARGET_OBJECTS:standalone_main>)
target_link_libraries(mavlink_fuzzer-standalone PRIVATE ${FUZZER_NO_MAIN_LIB})
