# Stripped Aquanode Modular plugins: one small LV2 per patch, without an editor window.
#
# This is a separate CMake project with its own build folder, so building a stripped
# plugin never reconfigures, recompiles or relinks anything of the full build. It only
# reads the full build's library (AQ_FULL_LIBRARY) to take the code of the modules from.
#
# Driven by ../build_stripped.sh. Every folder under AQ_SPECS_DIR was written by
# ../tools/make_stripped.py and becomes one plugin target.

cmake_minimum_required(VERSION 3.22)

get_filename_component(AQ_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

file(READ "${AQ_ROOT}/Aquanode_Modular.jucer" AQ_JUCER_TEXT)
string(REGEX MATCH "<JUCERPROJECT[^>]*>" AQ_HEADER "${AQ_JUCER_TEXT}")
string(REGEX MATCH " version=\"([0-9.]+)\"" _ "${AQ_HEADER}")
set(AQ_VERSION "${CMAKE_MATCH_1}")
string(REGEX MATCHALL "<FILE [^>]*resource=\"1\"[^>]*>" AQ_RESOURCE_TAGS "${AQ_JUCER_TEXT}")
set(AQ_RESOURCES "")
foreach(tag IN LISTS AQ_RESOURCE_TAGS)
    if(tag MATCHES " file=\"([^\"]+)\"")
        list(APPEND AQ_RESOURCES "${AQ_ROOT}/${CMAKE_MATCH_1}")
    endif()
endforeach()

project(AquanodeStripped VERSION "${AQ_VERSION}" LANGUAGES C CXX)

set(AQ_JUCE_DIR "${AQ_ROOT}/JUCE" CACHE PATH "Path to the JUCE checkout")
set(AQ_SPECS_DIR "" CACHE PATH "Folder with one sub-folder per stripped plugin")
set(AQ_FULL_LIBRARY "" CACHE FILEPATH "The full build's shared-code library (.a)")

if(NOT EXISTS "${AQ_FULL_LIBRARY}")
    message(FATAL_ERROR "Full build library not found: '${AQ_FULL_LIBRARY}'. Run ./build_aquanode.sh first.")
endif()

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT EXISTS "${AQ_JUCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "JUCE not found at ${AQ_JUCE_DIR}. Run ./build_aquanode.sh first.")
endif()
add_subdirectory("${AQ_JUCE_DIR}" JUCE EXCLUDE_FROM_ALL)

juce_add_binary_data(AquanodeBinaryData
    HEADER_NAME BinaryData.h
    NAMESPACE   BinaryData
    SOURCES     ${AQ_RESOURCES})

string(REPLACE "." ";" AQ_VERSION_PARTS "${AQ_VERSION}")
list(GET AQ_VERSION_PARTS 0 AQ_V0)
list(GET AQ_VERSION_PARTS 1 AQ_V1)
list(GET AQ_VERSION_PARTS 2 AQ_V2)
math(EXPR AQ_VERSION_HEX "(${AQ_V0} << 16) + (${AQ_V1} << 8) + ${AQ_V2}" OUTPUT_FORMAT HEXADECIMAL)

# These two lists must stay the same as in ../CMakeLists.txt, so the engine compiled here
# fits the module code taken from the full build's library.
set(AQ_MODULES
    animation audio_basics audio_devices audio_formats audio_plugin_client audio_processors
    audio_processors_headless audio_utils box2d core data_structures dsp events graphics
    gui_basics gui_extra javascript midi_ci opengl osc video)
set(AQ_DEFINITIONS
    JUCE_STRICT_REFCOUNTEDPOINTER=1
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_USE_MP3AUDIOFORMAT=1
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_ALSA=1
    JUCE_JACK=1
    JUCE_PLUGINHOST_VST3=1)

set(AQ_INCLUDES "")
set(AQ_LINK_MODULES AquanodeBinaryData)
foreach(m IN LISTS AQ_MODULES)
    string(APPEND AQ_INCLUDES "#include <juce_${m}/juce_${m}.h>\n")
    list(APPEND AQ_LINK_MODULES juce::juce_${m})
endforeach()

file(GLOB AQ_SPECS "${AQ_SPECS_DIR}/*/stripped.cmake")
foreach(spec IN LISTS AQ_SPECS)
    get_filename_component(AQS_DIR "${spec}" DIRECTORY)
    include("${spec}")   # AQS_NAME, AQS_SLUG, AQS_CODE, AQS_IS_FX, AQS_SOURCES
    string(MAKE_C_IDENTIFIER "aqs_${AQS_SLUG}" target)

    if(AQS_IS_FX)
        set(kind IS_SYNTH FALSE NEEDS_MIDI_INPUT TRUE NEEDS_MIDI_OUTPUT FALSE)
    else()
        set(kind IS_SYNTH TRUE NEEDS_MIDI_INPUT TRUE NEEDS_MIDI_OUTPUT TRUE)
    endif()

    juce_add_plugin(${target}
        PRODUCT_NAME             "${AQS_NAME}"
        VERSION                  "${AQ_VERSION}"
        COMPANY_NAME             "aquanodemusic"
        PLUGIN_MANUFACTURER_CODE Aqnd
        PLUGIN_CODE              ${AQS_CODE}
        LV2URI                   "https://github.com/maarthome/aquanode-modular/stripped/${AQS_SLUG}"
        FORMATS                  LV2
        ${kind}
        COPY_PLUGIN_AFTER_BUILD  FALSE)

    set(generated "${CMAKE_CURRENT_BINARY_DIR}/generated/${target}")
    file(WRITE "${generated}/JuceHeader.h.new"
"// Generated: stands in for the JuceHeader.h that Projucer writes.
#pragma once
${AQ_INCLUDES}
#include \"BinaryData.h\"

namespace ProjectInfo
{
    const char* const  projectName    = \"${AQS_NAME}\";
    const char* const  companyName    = \"aquanodemusic\";
    const char* const  versionString  = \"${AQ_VERSION}\";
    const int          versionNumber  = ${AQ_VERSION_HEX};
}
")
    configure_file("${generated}/JuceHeader.h.new" "${generated}/JuceHeader.h" COPYONLY)

    list(TRANSFORM AQS_SOURCES PREPEND "${AQ_ROOT}/")
    file(GLOB spec_sources "${AQS_DIR}/*.cpp")
    target_sources(${target} PRIVATE ${AQS_SOURCES} ${spec_sources})
    # Source/Engine: the generated copy of PluginProcessor.cpp includes its neighbours from there
    target_include_directories(${target} PRIVATE "${generated}" "${AQ_ROOT}" "${AQ_ROOT}/Source/Engine")

    target_compile_definitions(${target} PUBLIC ${AQ_DEFINITIONS} AQUANODE_STRIPPED=1)
    if(AQS_IS_FX)
        target_compile_definitions(${target} PUBLIC AQUANODE_FX_BUILD=1)
    endif()
    target_compile_options(${target} PRIVATE -w -ffunction-sections -fdata-sections)

    # The full build's library comes last: the linker takes from it only the objects that
    # the generated registry (and what those objects need) refers to.
    target_link_libraries(${target}
        PRIVATE
            ${AQ_LINK_MODULES}
            "${AQ_FULL_LIBRARY}"
        PUBLIC
            juce::juce_recommended_config_flags)
    target_link_options(${target}_LV2 PRIVATE -Wl,--gc-sections)

    file(WRITE "${AQS_DIR}/artefacts.txt" "${CMAKE_CURRENT_BINARY_DIR}/${target}_artefacts/${CMAKE_BUILD_TYPE}/LV2\n")
    file(WRITE "${AQS_DIR}/target.txt" "${target}_LV2\n")
endforeach()
