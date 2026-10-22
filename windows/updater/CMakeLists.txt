# Runs from a temporary copy outside the install directory, so it carries its
# own C runtime instead of loading the one bundled next to the app.
add_executable(updater WIN32 "main.cpp")
target_compile_features(updater PRIVATE cxx_std_17)
target_compile_options(updater PRIVATE /W4 /WX /utf-8)
set_property(TARGET updater PROPERTY
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(updater PRIVATE shell32 advapi32)
