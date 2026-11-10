#!/bin/bash

set -o pipefail

MIN_KERNEL="4.15.0-20-generic"
CURRENT_KERNEL=$(uname -r)
APP_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/myprogram"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/myprogram"
LOG_FILE="$LOG_DIR/install.log"
MODEL_NAME="qwen2-1.5b-instruct-q4_k_m.gguf"
MODEL_URL="https://huggingface.co/Qwen/Qwen2-1.5B-Instruct-GGUF/resolve/main/qwen2-1_5b-instruct-q4_k_m.gguf"

mkdir -p "$APP_HOME" "$LOG_DIR" || exit 1
exec 2>>"$LOG_FILE"

if ! command -v zenity >/dev/null 2>&1; then
    printf 'Zenity is unavailable. Rebuild the AppImage with its GTK runtime dependencies.\n' >&2
    exit 1
fi

if ! dpkg --compare-versions "$CURRENT_KERNEL" ge "$MIN_KERNEL"; then
    zenity --error --title="커널 버전 확인" --no-markup \
        --text="현재 커널은 이 프로그램의 최소 요구 조건을 충족하지 않습니다.\n\n현재 버전: $CURRENT_KERNEL\n요구 버전: $MIN_KERNEL 이상"
    exit 1
fi

run_step() {
    local title="$1"
    shift

    if (
        printf '# %s\n' "$title"
        if "$@" >>"$LOG_FILE" 2>&1; then
            printf '100\n'
        else
            exit "$?"
        fi
    ) | zenity --progress --title="진행 중" --text="$title" --pulsate --no-cancel --auto-close --width=420; then
        return 0
    fi

    local details
    details=$(tail -n 30 "$LOG_FILE" 2>/dev/null)
    zenity --error --title="작업 실패" --no-markup \
        --text="$title 작업에 실패했습니다.\n\n로그: $LOG_FILE\n\n$details"
    return 1
}

selection_has() {
    grep -Fxq -- "$1" <<< "$SELECTION"
}

install_kitware_cmake() {
    pkexec bash -c '
        set -e
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git curl ca-certificates software-properties-common
        add-apt-repository -y ppa:ubuntu-toolchain-r/test
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-11 g++-11
    ' || return 1
    local installer="$APP_HOME/cmake-3.28.4-linux-x86_64.sh"
    curl --fail --location --retry 3 \
        --output "$installer" \
        https://github.com/Kitware/CMake/releases/download/v3.28.4/cmake-3.28.4-linux-x86_64.sh || return 1
    pkexec bash "$installer" --skip-license --prefix=/usr/local || return 1
    hash -r
}

fetch_llama_source() {
    local source_dir="$APP_HOME/llama.cpp"

    if [[ -d "$source_dir/.git" ]]; then
        git -C "$source_dir" pull --ff-only
    else
        mkdir -p "$APP_HOME"
        git clone https://github.com/ggml-org/llama.cpp.git "$source_dir"
    fi
}

build_llama() {
    local source_dir="$APP_HOME/llama.cpp"
    local build_dir="$source_dir/build"
    local model_dir="$APP_HOME/models"

    export CC=/usr/bin/gcc-11
    export CXX=/usr/bin/g++-11
    printf 'CC=%s\nCXX=%s\n' "$CC" "$CXX"

    if [[ ! -x "$CC" || ! -x "$CXX" ]]; then
        echo "Error: GCC 11 is required at $CC and $CXX" >&2
        return 1
    fi

    rm -rf "$build_dir" || return 1

    cmake -S "$source_dir" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=OFF \
        -DGGML_AVX=ON \
        -DGGML_AVX2=ON \
        -DLLAMA_BUILD_SERVER=ON || return 1
    cmake --build "$build_dir" --config Release -j2 || return 1

    if [[ ! -x "$build_dir/bin/llama-server" ]]; then
        echo "Error: llama-server was not produced by the CMake build" >&2
        return 1
    fi

    mkdir -p "$model_dir" || return 1
}

download_model() {
    local model_path="$APP_HOME/models/$MODEL_NAME"
    local model_dir
    model_dir="$(dirname "$model_path")"

    mkdir -p "$model_dir" || return 1

    # 모델 파일 다운로드
    if [[ ! -s "$model_path" ]]; then
        echo "Downloading model: $MODEL_NAME"

        curl --fail --location --retry 3 \
            --output "$model_path.tmp" \
            "$MODEL_URL" &&
            mv "$model_path.tmp" "$model_path" || {
                rm -f "$model_path.tmp"
                return 1
            }
    else
        echo "Model already exists: $model_path"
    fi

    # 다운로드 결과 확인
    ls -lh "$model_path"
}

install_llama() {
    local source_dir="$APP_HOME/llama.cpp"
    local model_path="$APP_HOME/models/$MODEL_NAME"
    local server_path="$source_dir/build/bin/llama-server"

    run_step "빌드 도구 설치 및 패키지 목록 갱신" install_kitware_cmake || return 1
    run_step "llama.cpp 소스 준비" fetch_llama_source || return 1
    run_step "llama.cpp와 서버 빌드 (시간이 오래걸립니다)" build_llama || return 1
    run_step "Qwen2 모델 다운로드 (파일 크기가 큽니다)" download_model || return 1

    zenity --info --title="설치 완료" --no-markup \
        --text="llama.cpp와 모델 설치가 완료되었습니다.\n\n모델: $model_path\n서버 주소: http://127.0.0.1:8080"

    if zenity --question --title="서버 실행" --no-markup \
        --text="API 서버를 지금 실행할까요?\n모든 네트워크 인터페이스에서 수신하므로, 네트워크의 다른 기기에서도 이 PC의 IP 주소와 8080 포트로 접속할 수 있습니다."; then
        nohup "$server_path" -m "$model_path" -c 2048 -t 2 --host 0.0.0.0 --port 8080 \
            >>"$LOG_DIR/llama-server.log" 2>&1 </dev/null &
        zenity --info --title="서버 실행" --no-markup \
            --text="서버를 백그라운드에서 시작했습니다.\n이 PC: http://127.0.0.1:8080\n다른 기기: 이 PC의 IP 주소와 포트 8080\n\n로그: $LOG_DIR/llama-server.log"
    fi
}

install_barrier() {
    if ! command -v flatpak >/dev/null 2>&1; then
        run_step "Flatpak 설치" pkexec bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y flatpak' || return 1
    fi

    run_step "Flathub 등록 및 Barrier 설치" bash -c \
        'flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && flatpak install --user --assumeyes flathub com.github.debauchee.barrier' || return 1

    zenity --info --title="설치 완료" --no-markup --text="Barrier 설치가 완료되었습니다."
    if zenity --question --title="Barrier 실행" --text="Barrier를 지금 실행할까요?"; then
        nohup flatpak run --user com.github.debauchee.barrier >>"$LOG_DIR/barrier.log" 2>&1 </dev/null &
    fi
}

configure_swap() {
    local input size suffix swap_id swap_path
    input=$(zenity --forms --title="가상 메모리 설정" \
        --text="swap 파일 크기와 식별 이름을 지정하세요." \
        --add-entry="크기 (예: 8G 또는 512M)" --entry-text="8G" \
        --add-entry="이름 (영문, 숫자, - 또는 _)" --entry-text="8" \
        --separator="|") || return 2

    IFS='|' read -r size swap_id <<< "$input"
    if [[ ! "$size" =~ ^[1-9][0-9]*[MG]$ ]]; then
        zenity --error --title="입력 확인" --text="크기는 8G 또는 512M 형식으로 입력하세요."
        return 1
    fi
    if [[ ! "$swap_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        zenity --error --title="입력 확인" --text="이름에는 영문, 숫자, 하이픈, 밑줄만 사용할 수 있습니다."
        return 1
    fi

    swap_path="/swapfile_$swap_id"
    if ! zenity --question --title="설정 확인" --no-markup \
        --text="다음 swap 파일을 만들고 부팅 시 자동 활성화합니다.\n\n크기: $size\n경로: $swap_path\n\n계속할까요?"; then
        return 2
    fi

    run_step "swap 파일 생성 및 재부팅 설정" pkexec bash -c '
        set -e
        size=$1
        swap_path=$2
        if [[ -e "$swap_path" ]]; then
            echo "이미 존재하는 파일입니다: $swap_path" >&2
            exit 1
        fi
        fallocate -l "$size" "$swap_path"
        chmod 600 "$swap_path"
        mkswap "$swap_path"
        swapon "$swap_path"
        grep -Fqx "$swap_path none swap sw 0 0" /etc/fstab || printf "%s none swap sw 0 0\n" "$swap_path" >> /etc/fstab
    ' _ "$size" "$swap_path" || return 1

    zenity --info --title="설정 완료" --no-markup \
        --text="$swap_path ($size)가 활성화되었으며, 재부팅 후에도 유지됩니다."
}

if ! SELECTION=$(zenity --list --checklist --title="설치 항목 선택" \
    --text="실행할 작업을 선택하세요.\n현재 커널: $CURRENT_KERNEL" \
    --width=720 --height=420 --separator="|" \
    --column="선택" --column="항목" --column="설명" \
    FALSE "llama" "llama.cpp와 Qwen2 로컬 모델 설치 (대용량 다운로드)" \
    FALSE "barrier" "Barrier 설치 (Flatpak, 사용자 계정에 설치)" \
    FALSE "swap" "swap 파일 생성 (관리자 인증 필요, 재부팅 후에도 유지)"); then
    exit 0
fi

if [[ -z "$SELECTION" ]]; then
    zenity --info --title="선택된 작업 없음" --text="설치 항목을 선택하지 않았습니다."
    exit 0
fi

SUMMARY=""
selection_has "llama" && SUMMARY+="• llama.cpp와 Qwen2 모델 설치\n"
selection_has "barrier" && SUMMARY+="• Barrier 설치\n"
selection_has "swap" && SUMMARY+="• swap 파일 설정\n"
if ! zenity --question --title="작업 확인" --no-markup \
    --text="다음 작업을 순서대로 진행합니다.\n\n$SUMMARY\n계속할까요?"; then
    exit 0
fi

if selection_has "llama"; then
    install_llama || exit 1
fi
if selection_has "barrier"; then
    install_barrier || exit 1
fi
if selection_has "swap"; then
    configure_swap
    result=$?
    [[ $result -eq 2 ]] && exit 0
    [[ $result -eq 0 ]] || exit "$result"
fi

zenity --info --title="작업 완료" --text="선택한 작업이 모두 완료되었습니다."

