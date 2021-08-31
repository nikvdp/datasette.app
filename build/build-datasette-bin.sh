#!/usr/bin/env bash
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

# Build a self-contained single-file binary of datasette and all it's 
# dependencies. 

# Uses conda-pack [1] and dgiagio/warp [2] to create the binary instead of
# pyinstaller because while the pyinstaller recipe listed here [3] does build a
# runnable binary, using it to run the basic `select sqlite_version()` query
# results in a 'jinja2.exceptions.UndefinedError: 'path_with_added_args' is
# undefined' error. This is most likely due to pyinstaller's zipfile path
# machinations and is probably fixable with strong enough pyinstaller-fu, but
# since conda-pack + warp don't rely on python's zipfile support sidestepping
# the issue seemed simpler.
#
# [1] https://conda.github.io/conda-pack/
# [2] https://github.com/dgiagio/warp
# [3] https://github.com/simonw/datasette/issues/93#issuecomment-754219002 

main() {
    install_conda
    export PATH=$HOME/miniconda3/bin:$HOME/miniconda2/bin:$PATH
    local env_name="datasette-bin"

    # create a conda env for datasette
    conda create -n "$env_name" python=3

    # install conda-pack into the base conda env
    conda install conda-pack

    # activate the datasette conda env
    source activate "$env_name" 

    # install datasette deps
    pip install wheel datasette pyinstaller

    # use the excellent conda-pack to create a tarball containing a
    # self-contained and relocatable copy of the conda env with all
    # dependencies included 
    conda-pack --name "$env_name" --force --output datasette.tar.gz
    
    store_github_artifact datasette.tar.gz

    # since we want to create a single binary, re-extract the conda-pack 
    # tarball so that we can use warp to pack it up
    local bundle_work_dir="${SCRIPT_DIR}/datasette-bundle"
    mkdir -p "$bundle_work_dir"
    tar -C "$bundle_work_dir" -xzf datasette.tar.gz

    echo "Updating timestamps..."
    # make sure every file has a timestamp lest the codesign process 
    # break
    find "$bundle_work_dir" -type f -exec touch '{}' \;

#     install_warp
#
#     # create a minimal launcher script to allow warp to run datasette with the
#     # bundled python interpreter
#     cat > "${bundle_work_dir}/bin/launch.sh" <<'EOF'
# #!/bin/bash
# SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
# exec "$SCRIPT_DIR/python" "$SCRIPT_DIR/datasette"
# EOF
#     chmod +x "${bundle_work_dir}/bin/launch.sh"
#     
#     echo "Creating single-file binary with warp"
#     # and finally create the single-file binary with warp
#     local warp_arch="$(uname | sed 's/Darwin/macos/' | sed 's/Linux/linux/')-x64"
#     ./warp-packer --arch "$warp_arch" \
#         --input_dir "$bundle_work_dir" \
#         --exec bin/launch.sh \
#         --output ./datasette.bin
#
#     store_github_artifact ./datasette.bin
}

install_warp() {
    # downloads an executable of [warp-packer](https://github.com/dgiagio/warp)
    # to the current dir, or another path specified by $1
    local warp_path="${1:-./warp-packer}"
    echo "Installing warp-packer..."
    # download warp
    # mac: https://github.com/dgiagio/warp/releases/download/v0.3.0/macos-x64.warp-packer
    # lin: https://github.com/dgiagio/warp/releases/download/v0.3.0/linux-x64.warp-packer
    local arch="$(uname | sed 's/Darwin/macos/' | sed 's/Linux/linux/')-x64"
    local url="https://github.com/dgiagio/warp/releases/download/v0.3.0/$arch.warp-packer" 

    wget "$url" -O "$warp_path"
    chmod +x "$warp_path"
}

store_github_artifact() {
    local input_file="$1"
    local artifact_name="${2:-$input_file}"

    if [[ -z "$GITHUB_WORKSPACE" ]]; then
        echo "\$GITHUB_WORKSPACE not set (running locally?). Not creating an artifact..." >&2 
    else
        mkdir "$GITHUB_WORKSPACE/artifacts"
        cp "$input_file" "$GITHUB_WORKSPACE/artifacts/$artifact_name"
        echo ">> Stored artifact '$artifact_name'!"
    fi
} 

install_conda() {
  # download and install the latest miniconda release to ~/miniconda3
  echo "Installing conda..."
  local platform=$(uname)
  [[ "$platform" == "Darwin" ]] && platform="MacOSX"
  local miniconda="$(mktemp)"
  curl -L "https://repo.continuum.io/miniconda/Miniconda3-latest-$platform-x86_64.sh" >"$miniconda"
  bash "$miniconda" -b -p $HOME/miniconda3
  rm "$miniconda"
  if ! [[ -f ~/.condarc ]]; then
    echo ">>> Writing $HOME/.condarc"
    cat >$HOME/.condarc <<EOF
always_yes: true
channels:
    - conda-forge
    - defaults
EOF
  fi
  # ensure conda is on path for the rest of this script
  export PATH=$HOME/miniconda3/bin:$HOME/miniconda2/bin:$PATH
}

main
