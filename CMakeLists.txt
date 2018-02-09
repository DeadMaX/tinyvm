cmake_minimum_required(VERSION 2.6)
project(otcet)

add_executable(otcet main.c)

install(TARGETS otcet RUNTIME DESTINATION bin)
