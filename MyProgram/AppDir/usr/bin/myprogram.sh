#!/bin/bash

# 스크립트 위치 기준으로 작업 디렉터리 설정
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# PATH 보정
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# 오류 로그 저장
exec 2>> /tmp/zenity_debug.log

echo "========================"
echo "실행 시간: $(date)"
echo "사용자: $USER"
echo "DISPLAY: $DISPLAY"
echo "WAYLAND_DISPLAY: $WAYLAND_DISPLAY"
echo "========================"

# 필수 명령어 확인
for CMD in zenity uname linux-version; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        zenity --error --text="$CMD 명령어를 찾을 수 없습니다." 2>/dev/null
        exit 1
    fi
done

#!/bin/bash

# =====================================
# 1. 커널 버전 검사
# =====================================

MIN_KERNEL="4.15.0-20-generic"
CURRENT_KERNEL=$(uname -r)

if ! command -v linux-version >/dev/null 2>&1; then
    zenity --error \
        --title="시스템 오류" \
        --text="linux-version 명령어를 찾을 수 없습니다."
    exit 1
fi

if ! linux-version compare "$CURRENT_KERNEL" ge "$MIN_KERNEL"; then
    zenity --error \
        --title="커널 버전 확인" \
        --text="현재 커널 버전이 요구 조건에 미달합니다.\n\n현재 버전: $CURRENT_KERNEL\n요구 버전: $MIN_KERNEL 이상"
    exit 1
fi

# =====================================
# 2. 체크박스 선택
# =====================================

if ! CHECK=$(zenity --list \
    --checklist \
    --title="항목 선택" \
    --text="실행할 항목을 선택하세요.\n커널 버전: $CURRENT_KERNEL" \
    --width=600 \
    --height=400 \
    --column="선택" \
    --column="항목                     " \
    --column="설명                     " \
    FALSE "구형llama 설치" "로컬 AI모델(qwen2-1.5b-instruct-q4_k_m)을 설치합니다" \
    FALSE "barrier 설치" "2대 이상의 pc를 제어하는 프로그램을 설치합니다" \
    FALSE "가상메모리 확장" "pc의 가상메모리를 확장합니다" \
    --separator=","); then

    exit 0
fi

# =====================================
# 3. llama 설치
# =====================================

if [[ ",$CHECK," == *",구형llama 설치,"* ]]; then
    # CMAKE 재설치
    apt remove -y cmake
    apt install -y ca-certificates gpg wget
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc \
      2>/dev/null | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg
    cat /etc/os-release

    cd /tmp
    wget https://github.com/Kitware/CMake/releases/download/v3.28.4/cmake-3.28.4-linux-x86_64.sh

    chmod +x cmake-3.28.4-linux-x86_64.sh
    ./cmake-3.28.4-linux-x86_64.sh --skip-license --prefix=/usr/local
    hash -r
    cmake --version


    # old llama설치
    cd /root
    git clone https://github.com/ggml-org/llama.cpp.git llama.cpp
    cd llama.cpp

    make clean
    make -j2
    ls -lh main

    mkdir -p /root/models
    cd /root/models

    # 모델 설치
    wget -O qwen2-1.5b-instruct-q4_k_m.gguf \
    https://huggingface.co/Qwen/Qwen2-1.5B-Instruct-GGUF/resolve/main/qwen2-1_5b-instruct-q4_k_m.gguf

    ls -lh /root/models/qwen2-1.5b-instruct-q4_k_m.gguf

    # 모델 작동Test
    cd /root/llama.cpp
    ./llama-cli \
      -m /root/models/qwen2-1.5b-instruct-q4_k_m.gguf \
      -p "안녕하세요. 자기소개를 해주세요." \
      -n 128 \
      -t 2

    # API SERVER 실행
    cd /root/llama.cpp
    find . -maxdepth 2 -type f \( -name "llama-server" -o -name "server" \)

    cd /root/llama.cpp

    ./server \
      -m /root/models/qwen2-1.5b-instruct-q4_k_m.gguf \
      -c 2048 \
      -t 2 \
      --host 0.0.0.0 \
      --port 8080

    zenity --info \
        --title="완료" \
        --text="llama 설치완료"

fi

# =====================================
# 4. barrier 설치
# =====================================

if [[ ",$CHECK," == *",barrier 설치,"* ]]; then
    sudo add-apt-repository ppa:flatpak/stable
    sudo apt update
    sudo apt install --only-upgrade flatpak
    flatpak install flathub com.github.debauchee.barrier
    flatpak run com.github.debauchee.barrier

    zenity --info \
        --title="완료" \
        --text="barrier 설치완료"

fi

# =====================================
# 5. 가상메모리 확장 및 추가 입력
# =====================================

if [[ ",$CHECK," == *",가상메모리 확장,"* ]]; then

    if ! INPUT=$(zenity --forms \
        --title="추가 설정" \
        --text="swap가상메모리 값 추가 설정 (미 입력시 디폴트값)" \
        --add-entry="확장할 메모리 단위(8G)" \
        --add-entry="swapfile명(숫자)" \
        --entry-text="8G" \
        --entry-text="8" \
        --separator="|"); then

        exit 0
    fi

    IFS='|' read -r INPUT1 INPUT2 <<< "$INPUT"

    sudo fallocate -l $INPUT1 /swapfile$INPUT2
    sudo chmod 600 /swapfile$INPUT2
    sudo mkswap /swapfile$INPUT2
    sudo swapon /swapfile$INPUT2
    free -h
    /swapfile$INPUT2 none swap sw 0 0

    zenity --info \
        --title="완료" \
        --text="swap 가상메모리 확장완료"

fi

# =====================================
# 6. 최종 완료
# =====================================

zenity --info \
    --title="작업 완료" \
    --text="모든 작업이 완료되었습니다."

