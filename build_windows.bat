@echo off
echo Building Steganography Library for Windows...

:: Buat build directory
if not exist "build" mkdir build
cd build

:: Run CMake
cmake .. -G "Visual Studio 16 2019" -A x64
if %errorlevel% neq 0 (
    echo CMake configuration failed!
    pause
    exit /b 1
)

:: Build
cmake --build . --config Release
if %errorlevel% neq 0 (
    echo Build failed!
    pause
    exit /b 1
)

echo.
echo ✅ Build successful!
echo 📁 Library: build/Release/steganography.dll
echo 📁 Copy this file to your Flutter project root

pause