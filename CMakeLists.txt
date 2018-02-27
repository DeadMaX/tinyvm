cmake_minimum_required(VERSION 2.6)
project(octet)

add_executable(octet main.c)
if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
	target_link_libraries(octet PUBLIC dl)
endif (CMAKE_SYSTEM_NAME STREQUAL "Linux")


install(TARGETS octet RUNTIME DESTINATION bin)
