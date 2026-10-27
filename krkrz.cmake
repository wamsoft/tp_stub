# krkrz.cmake - 吉里吉里プラグイン用共通CMakeマクロ

cmake_minimum_required(VERSION 3.16)

set(TPSTUB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../tp_stub CACHE PATH "Path to tp_stub library")
set(NCBIND_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../ncbind CACHE PATH "Path to ncbind library")
set(SIMPLEBIND_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../simplebinder CACHE PATH "Path to simplebinder library")

function(krkrz_plugin PROJECT_NAME)
    set(options STATIC NCBIND SIMPLEBIND)
    set(oneValueArgs VERSION)
    set(multiValueArgs SOURCES INCLUDES LIBRARIES DEFINITIONS)
    cmake_parse_arguments(KRKRZ "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    if(NOT KRKRZ_VERSION)
        set(KRKRZ_VERSION "1.00")
    endif()
    project(${PROJECT_NAME} VERSION ${KRKRZ_VERSION})

    if(TVP_STATIC_PLUGIN OR KRKRZ_STATIC)
        set(TVP_LIBRARY_TYPE STATIC)
        list(APPEND KRKRZ_INCLUDES ${TPSTUB_DIR})
    else()
        set(TVP_LIBRARY_TYPE SHARED)        
        list(APPEND KRKRZ_SOURCES ${TPSTUB_DIR}/tp_stub.cpp)
        list(APPEND KRKRZ_INCLUDES ${TPSTUB_DIR})
    endif()

    if(KRKRZ_NCBIND)
        list(APPEND KRKRZ_SOURCES ${NCBIND_DIR}/ncbind.cpp)
        list(APPEND KRKRZ_INCLUDES ${NCBIND_DIR})
    endif()

    if(KRKRZ_SIMPLEBIND)
        list(APPEND KRKRZ_SOURCES ${SIMPLEBIND_DIR}/v2link.cpp)
        list(APPEND KRKRZ_INCLUDES ${SIMPLEBIND_DIR})
    endif()
        
    add_compile_options("$<$<AND:$<C_COMPILER_ID:MSVC>,$<COMPILE_LANGUAGE:C>>:/utf-8>")
    add_compile_options("$<$<AND:$<CXX_COMPILER_ID:MSVC>,$<COMPILE_LANGUAGE:CXX>>:/utf-8>")
    add_compile_options("$<$<AND:$<CXX_COMPILER_ID:MSVC>,$<COMPILE_LANGUAGE:CXX>>:/Zc:__cplusplus>")

    add_library(${PROJECT_NAME} ${TVP_LIBRARY_TYPE} ${KRKRZ_SOURCES})

    # 生成したプラグインターゲット名を GLOBAL プロパティに登録する。
    # 本体側 (src/core の TVP_PLUGINS ループ) は add_subdirectory 前後の差分から
    # このリストを参照し、フォルダ名と異なるターゲット名や 1 フォルダ複数
    # プラグイン (例: motion → krkrmotion + krkremote) を検出する。
    set_property(GLOBAL APPEND PROPERTY KRKRZ_PLUGIN_TARGETS ${PROJECT_NAME})

    if (TVP_STATIC_PLUGIN OR KRKRZ_STATIC)
        target_compile_definitions(${PROJECT_NAME} PRIVATE
            TVP_STATIC_PLUGIN
            TVP_PLUGIN_NAME=${PROJECT_NAME}
        )
        set_property(TARGET ${PROJECT_NAME} PROPERTY
            INTERFACE_LINK_OPTIONS
            $<$<CXX_COMPILER_ID:MSVC>:/WHOLEARCHIVE:$<TARGET_FILE:${PROJECT_NAME}>>
            $<$<OR:$<CXX_COMPILER_ID:GNU>,$<CXX_COMPILER_ID:Clang>>:-Wl,--whole-archive,$<TARGET_FILE:${PROJECT_NAME}>,--no-whole-archive>
            # Apple の ld64 は --whole-archive を持たない。 NCB_REGISTER_* だけを持つ
            # オブジェクトが捨てられないよう -force_load で全メンバを取り込む
            $<$<CXX_COMPILER_ID:AppleClang>:-Wl,-force_load,$<TARGET_FILE:${PROJECT_NAME}>>
        )
    endif()

    # Linux: プラグインが同梱 .so に依存するとき、plugin/ フォルダ ($ORIGIN) と
    # exe のフォルダ ($ORIGIN/..) から確実に読ませる。DT_RPATH にするのは、Steam
    # 起動時は LD_LIBRARY_PATH の先頭に /usr/lib 等が入り RUNPATH では負けるため。
    # また RUNPATH を持つと exe 側の DT_RPATH ($ORIGIN) も使われなくなる。
    if (TVP_LIBRARY_TYPE STREQUAL "SHARED" AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set_target_properties(${PROJECT_NAME} PROPERTIES INSTALL_RPATH "\$ORIGIN;\$ORIGIN/..")
        target_link_options(${PROJECT_NAME} PRIVATE "LINKER:--disable-new-dtags")
    endif()

    # 共有プラグイン (Windows 以外): シンボルを既定で非公開にし、 明示指定した
    # V2Link / V2Unlink (DLL_EXPORT = visibility("default")) だけを公開する。
    # Linux では inline static なクラス静的メンバ (ncbind の自動登録リスト
    # ncbAutoRegister::_top 等) が STB_GNU_UNIQUE で公開され、 RTLD_LOCAL で
    # dlopen してもプロセス全体で 1 つにまとめられる。 そのため ncbind を使う
    # プラグインを 2 本読むと、 後の V2Link が前のプラグインのクラスまで登録しようと
    # して二重登録の例外で abort していた (layerExVector + layerExImage など)。
    # Windows の DLL はモジュールごとに別のコピーなので元から起きない。
    if (TVP_LIBRARY_TYPE STREQUAL "SHARED" AND NOT WIN32)
        set_target_properties(${PROJECT_NAME} PROPERTIES
            C_VISIBILITY_PRESET hidden
            CXX_VISIBILITY_PRESET hidden
            VISIBILITY_INLINES_HIDDEN ON
        )
    endif()

    # Linux (gcc): 例外の巻き戻し処理を共有の libgcc_s.so.1 に一本化する (本体と同じ指定。
    # 本体の src/core/CMakeLists.txt の説明を参照)。 exe とプラグインが libgcc を静的に
    # 抱えていると、 プラグインのフレームを越える例外で unwinder の複製が混ざって abort する。
    # -shared-libgcc は効かない gcc がある (libgcc を常に静的に使う specs) ので libgcc_s.so.1 を直接リンクする。
    if (TVP_LIBRARY_TYPE STREQUAL "SHARED" AND CMAKE_SYSTEM_NAME STREQUAL "Linux"
        AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        target_link_options(${PROJECT_NAME} PRIVATE
            "SHELL:-Wl,--push-state,--no-as-needed -l:libgcc_s.so.1 -Wl,--pop-state")
    endif()

    # 共有プラグイン (Linux / macOS): 公開するのは V2Link / V2Unlink だけにする。
    # 上の hidden はプラグイン自身のコードにしか効かず、 静的リンクしたライブラリ
    # (libstdc++ / zlib / expat / threepp / Effekseer など) のシンボルは既定の公開の
    # まま残っていた (多いもので 2 万個超)。 同じライブラリを別々に静的リンクした
    # プラグインを 2 本読むと、 上の ncbind と同じ形で互いの実装が混ざりうる。
    # Linux はバージョンスクリプトで、 macOS (ld64) は -exported_symbol で絞る。
    if (TVP_LIBRARY_TYPE STREQUAL "SHARED" AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set(_krkrz_export_map "${CMAKE_BINARY_DIR}/krkrz_plugin_exports.map")
        if (NOT EXISTS "${_krkrz_export_map}")
            file(WRITE "${_krkrz_export_map}" "{
  global: V2Link; V2Unlink;
  local: *;
};
")
        endif()
        target_link_options(${PROJECT_NAME} PRIVATE "LINKER:--version-script=${_krkrz_export_map}")
        set_property(TARGET ${PROJECT_NAME} APPEND PROPERTY LINK_DEPENDS "${_krkrz_export_map}")
    elseif (TVP_LIBRARY_TYPE STREQUAL "SHARED" AND APPLE)
        target_link_options(${PROJECT_NAME} PRIVATE
            "LINKER:-exported_symbol,_V2Link"
            "LINKER:-exported_symbol,_V2Unlink"
        )
    endif()

    if (KRKRZ_DEFINITIONS)
        target_compile_definitions(${PROJECT_NAME} PRIVATE ${KRKRZ_DEFINITIONS})
    endif()

    if(KRKRZ_INCLUDES)
        target_include_directories(${PROJECT_NAME} PRIVATE ${KRKRZ_INCLUDES})
    endif()

    if(KRKRZ_LIBRARIES)
        target_link_libraries(${PROJECT_NAME} PUBLIC ${KRKRZ_LIBRARIES})
    endif()

    # プラグインの挙動調整用
    if (KRKRZ_VARIANT STREQUAL "LIB" OR KRKRZ_VARIANT STREQUAL "SDL")
        target_compile_definitions(${PROJECT_NAME} PRIVATE
            __GENERIC__
        )
    endif()

    if (MSVC)
        target_compile_definitions(${PROJECT_NAME} PRIVATE
            _CRT_SECURE_NO_WARNINGS
            UNICODE
            _UNICODE
        )
    endif()

endfunction()
