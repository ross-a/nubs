@echo off

rem 1 meg and 64 megs
set STACK_SIZE=1048576
set HEAP_SIZE=67108864
set SHELL_FILE="c:/dev/emsdk/upstream/emscripten/src/shell_minimal.html"

call emsdk_env.bat
call emsdk.bat activate latest

call odin build stars_test.odin -target=freestanding_wasm32 -microarch=bleeding-edge -out:odin -build-mode:obj -debug -show-system-calls -file
call emcc.bat --shell-file %SHELL_FILE% -o index.html main.c odin.wasm.o libraylib.a -sFULL_ES2 -s USE_GLFW=3 -s GL_ENABLE_GET_PROC_ADDRESS -DWEB_BUILD -sSTACK_SIZE=%STACK_SIZE% -s TOTAL_MEMORY=%HEAP_SIZE% -sERROR_ON_UNDEFINED_SYMBOLS=0 -pthread -sPTHREAD_POOL_SIZE=2

copy index.html C:\dev\nginx-1.27.1\html
copy index.js C:\dev\nginx-1.27.1\html
rem TODO wasm_workers
rem copy index.ww.js C:\dev\nginx-1.27.1\html
copy index.wasm C:\dev\nginx-1.27.1\html
