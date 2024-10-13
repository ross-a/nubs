## Threading support in Odin when -target=freestanding_wasm

method is same as: https://github.com/Caedo/raylib_wasm_odin/tree/master

## How does that work

This method abuses emscripten compiler and its toolchain by using small C program, that calls Odin code:
```c
#include <emscripten/emscripten.h>

extern void _main();
extern void step();

int main() {
    _main();

    emscripten_set_main_loop(step, 0, 1);
    return 0;
}
```

This way we can use Odin compiler to create object files that will be used by emcc. Check `build.bat` for calls and flags.

-------------------------------------------------------------------------------

Odin should compile to an object file (-build-mode:obj) then compile with Emscripten
(this is so odin+wasm+raylib+pthread works)

TODO: wasm_workers? in addition to pthreads

-------------------------------------------------------------------------------

> 
	@echo off

	rem 1 meg and 64 megs
	set STACK_SIZE=1048576
	set HEAP_SIZE=67108864
	set SHELL_FILE="c:/dev/emsdk/upstream/emscripten/src/shell_minimal.html"

	call emsdk_env.bat
	call emsdk.bat activate latest

	call odin build some_cool_file.odin -target=freestanding_wasm32 -microarch=bleeding-edge -out:odin -build-mode:obj -debug -show-system-calls -file
	call emcc.bat --shell-file %SHELL_FILE% -o index.html main.c odin.wasm.o libraylib.a -sFULL_ES2 -s USE_GLFW=3 -s GL_ENABLE_GET_PROC_ADDRESS -DWEB_BUILD -sSTACK_SIZE=%STACK_SIZE% -s TOTAL_MEMORY=%HEAP_SIZE% -sERROR_ON_UNDEFINED_SYMBOLS=0 -pthread -sPTHREAD_POOL_SIZE=2
