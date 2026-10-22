# Runs from a temporary copy outside the install directory, so it carries its
# own C runtime instead of loading the one bundled next to the app.
add_executable(uninstall WIN32 "main.cpp" "uninstall.rc")
target_compile_features(uninstall PRIVATE cxx_std_17)
target_compile_options(uninstall PRIVATE /W4 /WX /utf-8)
set_property(TARGET uninstall PROPERTY
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(uninstall PRIVATE shell32 advapi32 ole32)
