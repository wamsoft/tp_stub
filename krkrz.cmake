# krkrz.cmake - 吉里吉里プラグイン用共通CMakeマクロ

cmake_minimum_required(VERSION 3.16)

# プラグイン用共通マクロ
define_property(GLOBAL PROPERTY KRKRZ_PLUGINS)

function(krkrz_plugin PROJECT_NAME)
    set(options STATIC NCBIND)
    set(oneValueArgs VERSION)
    set(multiValueArgs SOURCES INCLUDES LIBRARIES)
    cmake_parse_arguments(KRKRZ "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(KRKRZ_NCBIND)
        list(APPEND KRKRZ_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../ncbind/ncbind.cpp)
        list(APPEND KRKRZ_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/../ncbind)
    endif()

    list(APPEND KRKRZ_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../tp_stub/tp_stub.cpp)
    list(APPEND KRKRZ_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/../tp_stub)
    
    if(NOT KRKRZ_VERSION)
        set(KRKRZ_VERSION "1.00")
    endif()
    project(${PROJECT_NAME} VERSION ${KRKRZ_VERSION})

    if(TVP_STATIC_PLUGIN OR KRKRZ_STATIC)
        set(TVP_LIBRARY_TYPE STATIC)
    else()
        set(TVP_LIBRARY_TYPE SHARED)
    endif()

    set(CMAKE_POSITION_INDEPENDENT_CODE ON)

    add_compile_options("$<$<AND:$<C_COMPILER_ID:MSVC>,$<COMPILE_LANGUAGE:C>>:/utf-8>")
    add_compile_options("$<$<AND:$<CXX_COMPILER_ID:MSVC>,$<COMPILE_LANGUAGE:CXX>>:/utf-8>")
    add_compile_options("$<$<AND:$<CXX_COMPILER_ID:MSVC>,$<COMPILE_LANGUAGE:CXX>>:/Zc:__cplusplus>")

    add_library(${PROJECT_NAME} ${TVP_LIBRARY_TYPE} ${KRKRZ_SOURCES})

    if (TVP_STATIC_PLUGIN OR KRKRZ_STATIC)
        target_compile_definitions(${PROJECT_NAME} PRIVATE
            TVP_STATIC_PLUGIN
            TVP_PLUGIN_NAME=${PROJECT_NAME}
        )
    endif()

   if(CMAKE_SYSTEM_NAME MATCHES "Linux" AND NOT KRKRZ_STATIC)

        string(TOLOWER "${PROJECT_NAME}" PROJECT_NAME_LOWER)
        
        set_target_properties(${PROJECT_NAME} PROPERTIES
            OUTPUT_NAME "${PROJECT_NAME_LOWER}"
            PREFIX "lib"
        )
    endif()

    if(KRKRZ_INCLUDES)
        target_include_directories(${PROJECT_NAME} PRIVATE ${KRKRZ_INCLUDES})
    endif()

    if(KRKRZ_LIBRARIES)
        target_link_libraries(${PROJECT_NAME} PUBLIC ${KRKRZ_LIBRARIES})
    endif()

    target_compile_definitions(${PROJECT_NAME} PRIVATE
        UNICODE
        _UNICODE
    )

endfunction()
