@echo off

rem 1 meg and 64 megs
set STACK_SIZE=1048576
set HEAP_SIZE=67108864
set SHELL_FILE="c:/dev/emsdk/upstream/emscripten/src/shell_minimal.html"

call emsdk_env.bat
call emsdk.bat activate latest

rem find a .odin file to use as NAME
setlocal enabledelayedexpansion
for %%A in (*.odin) do (
    set "NAME=%%~nA"
    echo Using !NAME!
)
set EMDIR="c:/dev/Odin/nubs/emscripten_threads"


call odin build %NAME%.odin -target=freestanding_wasm32 -microarch=bleeding-edge -out:odin -build-mode:obj -debug -show-system-calls -file
call emcc.bat --shell-file %SHELL_FILE% -o %NAME%.html %EMDIR%/main.c odin.wasm.o %EMDIR%/libraylib.a -sFULL_ES2 -s USE_GLFW=3 -s GL_ENABLE_GET_PROC_ADDRESS -DWEB_BUILD -sSTACK_SIZE=%STACK_SIZE% -s TOTAL_MEMORY=%HEAP_SIZE% -sERROR_ON_UNDEFINED_SYMBOLS=0 -pthread -sPTHREAD_POOL_SIZE=2


set Arr[0]="html"
set Arr[1]="js"
set Arr[2]="wasm"
set "x=0"
:Loop
if defined Arr[%x%] (
	 rem copy to localhost server too?
	 rem call copy %NAME%.%%Arr[%x%]%% C:\dev\nginx-1.27.1\html
	 call copy %NAME%.%%Arr[%x%]%% C:\dev\ross-a.github.io
	 set /a "x+=1"
	 GOTO :Loop
)
