mkdir -p "$HOME/bin"
cd "$HOME/bin"

# 라이브러리 설치 (1회)
wget -O linuxdeploy \
https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy

wget -O linuxdeploy-plugin-gtk.sh \
https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
chmod +x linuxdeploy-plugin-gtk.sh

wget -O linuxdeploy-plugin-appimage-x86_64.AppImage \
https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage
chmod +x linuxdeploy-plugin-appimage-x86_64.AppImage

# 패키징
LINUXDEPLOY="$HOME/bin/linuxdeploy" bash MyProgram/build-appimage.sh