#!/bin/sh

# Script (part of the pre-commit hook suite) that checks the case sensitivity 
# of shader includes in staged files.
# Windows is case-insensitive when it comes to path management.
# This can be problematic on other platforms where we want to ensure the #included path is correct.

check_shaders_on_windows()
{
  echo "Windows detected. Running powershell script..."
  cd ../../../
  path=`git rev-parse --show-toplevel` # Get path of repo, if executed from .git/hooks/pre-commit.d
  cd - > /dev/null
  exec powershell.exe -File './check-shader-includes.ps1' "$path"
  exit
}

echo "Shader includes path checking. This will make sure that all #include refer to an existing path (case sensitive)."
echo "Checking your OS..."
uname_out="$(uname -s)"
case "${uname_out}" in
    Linux*)     echo "Linux detected. There's no script to check shader includes for this OS." ;;
    Darwin*)    echo "OSX detected. There's no script to check shader includes for this OS." ;; 
    CYGWIN*)    check_shaders_on_windows ;;
    MINGW*)     check_shaders_on_windows ;;
    *)          echo "unknown OS: $uname_out detected. There's no script to check shader includes for this OS." ;;
esac