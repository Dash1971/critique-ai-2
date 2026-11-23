# Included by CMAKE_PROJECT_INCLUDE in the pinned llama.cpp configure. This adds
# the app bridge without modifying vendor sources or enabling network/server code.
include_guard(GLOBAL)
get_filename_component(CRITIQUE_RUNTIME_DIR "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
set(CRITIQUE_VENDOR_DIR "${CMAKE_SOURCE_DIR}")
add_library(critique-bridge STATIC
    "${CRITIQUE_RUNTIME_DIR}/CoachBridge.cpp"
    "${CRITIQUE_VENDOR_DIR}/common/json.cpp"
    "${CRITIQUE_VENDOR_DIR}/common/unicode.cpp"
    "${CRITIQUE_VENDOR_DIR}/common/jinja/lexer.cpp"
    "${CRITIQUE_VENDOR_DIR}/common/jinja/parser.cpp"
    "${CRITIQUE_VENDOR_DIR}/common/jinja/runtime.cpp"
    "${CRITIQUE_VENDOR_DIR}/common/jinja/value.cpp"
    "${CRITIQUE_VENDOR_DIR}/common/jinja/string.cpp")
target_compile_features(critique-bridge PUBLIC cxx_std_17)
target_include_directories(critique-bridge PUBLIC "${CRITIQUE_RUNTIME_DIR}/include"
    PRIVATE "${CRITIQUE_VENDOR_DIR}/include" "${CRITIQUE_VENDOR_DIR}/ggml/include"
    "${CRITIQUE_VENDOR_DIR}/common" "${CRITIQUE_VENDOR_DIR}/vendor")
target_link_libraries(critique-bridge PUBLIC llama)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_executable(critique-coach "${CRITIQUE_RUNTIME_DIR}/CoachCLI.cpp")
    target_link_libraries(critique-coach PRIVATE critique-bridge)
    target_include_directories(critique-coach PRIVATE "${CRITIQUE_VENDOR_DIR}/common")
    add_executable(critique-bridge-tests "${CRITIQUE_RUNTIME_DIR}/BridgeTests.cpp")
    target_link_libraries(critique-bridge-tests PRIVATE critique-bridge)
    target_include_directories(critique-bridge-tests PRIVATE "${CRITIQUE_VENDOR_DIR}/common" "${CRITIQUE_VENDOR_DIR}/vendor")
    set_target_properties(critique-coach critique-bridge-tests PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()
