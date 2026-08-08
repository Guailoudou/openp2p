cmake_minimum_required(VERSION 3.5.0)
project(openp2p_ohos)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a)

set(OPENP2P_LIB "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libopenp2p_ohos.so")
if(NOT EXISTS "${OPENP2P_LIB}")
    message(FATAL_ERROR "OpenP2P OHOS library was not found: ${OPENP2P_LIB}")
endif()

add_library(entry SHARED napi_init.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so libdl.a)
