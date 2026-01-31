#!/bin/bash

# Stock-TSDB Ubuntu/Debian 打包脚本
# 创建适用于Ubuntu和Debian系统的软件包

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 获取版本信息
get_version() {
    if [ -f "VERSION" ]; then
        VERSION=$(cat VERSION)
    else
        VERSION=$(git describe --tags --always 2>/dev/null || echo "1.0.0")
    fi
    echo "$VERSION"
}

# 检测发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        CODENAME=$VERSION_CODENAME
        log_info "检测到发行版: $DISTRO $CODENAME"
    else
        log_error "无法检测发行版"
        exit 1
    fi
}

# 安装打包依赖
install_packaging_deps() {
    log_info "安装打包依赖..."

    # 更新包列表
    sudo apt-get update

    # 安装必要的打包工具
    sudo apt-get install -y \
        build-essential \
        devscripts \
        debhelper \
        dh-make \
        dpkg-dev \
        lintian \
        pbuilder \
        cdbs \
        fakeroot \
        lua5.1 \
        luajit \
        luarocks \
        git

    log_info "打包依赖安装完成"
}

# 创建Debian包结构
create_debian_structure() {
    log_info "创建Debian包结构..."

    # 设置变量
    PACKAGE_NAME="stock-tsdb"
    VERSION=$(get_version)
    PACKAGE_DIR="${PACKAGE_NAME}-${VERSION}"
    TARBALL="${PACKAGE_NAME}_${VERSION}.orig.tar.gz"

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # 创建包目录
    mkdir -p "$TEMP_DIR/$PACKAGE_DIR"

    # 复制源代码
    rsync -av --exclude='.git' \
          --exclude='*.log' \
          --exclude='data/*' \
          --exclude='logs/*' \
          --exclude='*.deb' \
          --exclude='*.ddeb' \
          --exclude='debian' \
          ./ "$TEMP_DIR/$PACKAGE_DIR/"

    # 创建debian目录
    mkdir -p "$TEMP_DIR/$PACKAGE_DIR/debian"

    # 创建debian/control文件
    cat > "$TEMP_DIR/$PACKAGE_DIR/debian/control" << EOF
Source: stock-tsdb
Section: database
Priority: optional
Maintainer: Stock-TSDB Team <team@stock-tsdb.com>
Build-Depends: debhelper (>= 9), luajit (>= 2.1), luarocks, liblua5.1-0-dev, build-essential
Standards-Version: 4.1.4
Homepage: https://github.com/stock-tsdb/stock-tsdb

Package: stock-tsdb
Architecture: any
Depends: \${shlibs:Depends}, \${misc:Depends}, luajit (>= 2.1), luarocks, adduser
Description: High-performance stock time series database
 Stock-TSDB is a high-performance time series database optimized for stock market data.
 It provides efficient storage and retrieval of stock quotes, trades, and other market data.
 This package includes the server, client libraries, and management tools.

Package: stock-tsdb-dev
Architecture: any
Depends: stock-tsdb (= \${binary:Version}), \${shlibs:Depends}, \${misc:Depends}
Description: Development files for Stock-TSDB
 This package contains the header files and libraries needed for developing
 applications that use Stock-TSDB.
EOF

    # 创建debian/rules文件
    cat > "$TEMP_DIR/$PACKAGE_DIR/debian/rules" << EOF
#!/usr/bin/make -f
%:
	dh \$@ --with lua

override_dh_auto_configure:
	# 无需配置

override_dh_auto_build:
	\$(MAKE) all

override_dh_auto_install:
	\$(MAKE) install DESTDIR=debian/stock-tsdb

override_dh_clean:
	dh_clean
	rm -f build-stamp configure-stamp
EOF

    # 创建debian/changelog文件
    cat > "$TEMP_DIR/$PACKAGE_DIR/debian/changelog" << EOF
stock-tsdb ($VERSION-1) unstable; urgency=medium

  * Initial release
  * High-performance stock time series database
  * Optimized for Ubuntu and Debian systems

 -- Stock-TSDB Team <team@stock-tsdb.com>  $(date -R)
EOF

    # 创建debian/compat文件
    echo "9" > "$TEMP_DIR/$PACKAGE_DIR/debian/compat"

    # 创建debian/copyright文件
    cat > "$TEMP_DIR/$PACKAGE_DIR/debian/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: stock-tsdb
Source: https://github.com/stock-tsdb/stock-tsdb

Files: *
Copyright: 2024 Stock-TSDB Team <team@stock-tsdb.com>
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
EOF

    # 创建debian/postinst文件
    cat > "$TEMP_DIR/$PACKAGE_DIR/debian/postinst" << EOF
#!/bin/bash
set -e

case "\$1" in
    configure)
        # 创建系统用户
        if ! getent passwd stock-tsdb >/dev/null; then
            adduser --system --group --home /var/lib/stock-tsdb \
                --no-create-home --quiet --gecos "Stock-TSDB daemon" stock-tsdb
        fi

        # 创建必要的目录
        mkdir -p /var/log/stock-tsdb /var/lib/stock-tsdb
        chown -R stock-tsdb:stock-tsdb /var/log/stock-tsdb /var/lib/stock-tsdb

        # 安装Lua依赖
        if [ -x /usr/bin/luarocks ]; then
            luarocks install --local lua-cjson 2>/dev/null || true
            luarocks install --local luasocket 2>/dev/null || true
            luarocks install --local llthreads2 2>/dev/null || true
            luarocks install --local lzmq 2>/dev/null || true
        fi

        # 启用systemd服务
        if [ -d /etc/systemd/system ]; then
            systemctl enable stock-tsdb.service 2>/dev/null || true
        fi
        ;;
esac

#DEBHELPER#

exit 0
EOF

    # 创建debian/postrm文件
    cat > "$TEMP_DIR/$PACKAGE_DIR/debian/postrm" << EOF
#!/bin/bash
set -e

case "\$1" in
    purge|remove)
        # 删除系统用户
        if getent passwd stock-tsdb >/dev/null; then
            deluser --system stock-tsdb 2>/dev/null || true
        fi

        # 删除服务
        if [ -f /etc/systemd/system/stock-tsdb.service ]; then
            systemctl stop stock-tsdb.service 2>/dev/null || true
            systemctl disable stock-tsdb.service 2>/dev/null || true
            rm -f /etc/systemd/system/stock-tsdb.service
            systemctl daemon-reload 2>/dev/null || true
        fi
        ;;
esac

#DEBHELPER#

exit 0
EOF

    # 设置执行权限
    chmod +x "$TEMP_DIR/$PACKAGE_DIR/debian/postinst"
    chmod +x "$TEMP_DIR/$PACKAGE_DIR/debian/postrm"
    chmod +x "$TEMP_DIR/$PACKAGE_DIR/debian/rules"

    # 创建源码tarball
    cd "$TEMP_DIR"
    tar czf "../$TARBALL" "$PACKAGE_DIR"
    cd - > /dev/null

    # 移动到当前目录
    mv "$TEMP_DIR/$TARBALL" ./
    cp -r "$TEMP_DIR/$PACKAGE_DIR" ./

    log_info "Debian包结构创建完成"
}

# 构建Debian包
build_debian_package() {
    log_info "构建Debian包..."

    # 设置变量
    PACKAGE_NAME="stock-tsdb"
    VERSION=$(get_version)
    PACKAGE_DIR="${PACKAGE_NAME}-${VERSION}"

    # 进入包目录
    cd "$PACKAGE_DIR"

    # 构建包
    debuild -us -uc -b

    # 返回上级目录
    cd - > /dev/null

    log_info "Debian包构建完成"
}

# 创建AppImage包
create_appimage() {
    log_info "创建AppImage包..."

    # 设置变量
    VERSION=$(get_version)
    APPDIR="Stock-TSDB.AppDir"

    # 创建AppDir
    mkdir -p "$APPDIR/usr/bin"
    mkdir -p "$APPDIR/usr/lib"
    mkdir -p "$APPDIR/usr/share/applications"
    mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

    # 复制文件
    cp bin/stock-tsdb-server "$APPDIR/usr/bin/"
    cp -r lib/* "$APPDIR/usr/lib/"
    cp -r lua "$APPDIR/usr/share/stock-tsdb/"

    # 创建desktop文件
    cat > "$APPDIR/usr/share/applications/stock-tsdb.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Stock-TSDB
Comment=High-performance stock time series database
Exec=stock-tsdb-server
Icon=stock-tsdb
Categories=Development;Database;
EOF

    # 下载AppImage工具
    if [ ! -f "appimagetool-x86_64.AppImage" ]; then
        wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
        chmod +x appimagetool-x86_64.AppImage
    fi

    # 创建AppImage
    ./appimagetool-x86_64.AppImage "$APPDIR" "Stock-TSDB-${VERSION}-x86_64.AppImage"

    log_info "AppImage包创建完成"
}

# 创建RPM包（用于CentOS/RHEL）
create_rpm_package() {
    log_info "创建RPM包..."

    # 安装RPM构建工具
    sudo apt-get install -y rpm

    # 设置变量
    VERSION=$(get_version)
    SPEC_FILE="stock-tsdb.spec"

    # 创建spec文件
    cat > "$SPEC_FILE" << EOF
Name:           stock-tsdb
Version:        $VERSION
Release:        1%{?dist}
Summary:        High-performance stock time series database

License:        MIT
URL:            https://github.com/stock-tsdb/stock-tsdb
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc, make, luajit-devel, luarocks
Requires:       luajit, luarocks

%description
Stock-TSDB is a high-performance time series database optimized for stock market data.
It provides efficient storage and retrieval of stock quotes, trades, and other market data.

%prep
%setup -q

%build
make all

%install
make install DESTDIR=%{buildroot}

%files
%doc README.md
%license LICENSE
/usr/local/bin/stock-tsdb-server
/usr/local/lib/libmicro_ts.so
/usr/local/lib/libcjson.so
/usr/local/share/stock-tsdb/

%post
# 创建系统用户
getent passwd stock-tsdb >/dev/null || useradd -r -s /bin/false -d /var/lib/stock-tsdb stock-tsdb

# 创建必要的目录
mkdir -p /var/log/stock-tsdb /var/lib/stock-tsdb
chown -R stock-tsdb:stock-tsdb /var/log/stock-tsdb /var/lib/stock-tsdb

# 安装Lua依赖
luarocks install --local lua-cjson 2>/dev/null || true
luarocks install --local luasocket 2>/dev/null || true
luarocks install --local llthreads2 2>/dev/null || true
luarocks install --local lzmq 2>/dev/null || true

%postun
# 删除系统用户
if [ \$1 -eq 0 ]; then
    userdel -r stock-tsdb 2>/dev/null || true
fi

%changelog
* $(date +'%a %b %d %Y') Stock-TSDB Team <team@stock-tsdb.com> - $VERSION-1
- Initial release
EOF

    # 创建源码tarball
    tar czf "stock-tsdb-$VERSION.tar.gz" --exclude='.git' --exclude='debian' .

    # 构建RPM
    rpmbuild -ta "stock-tsdb-$VERSION.tar.gz" --define "_rpmdir $(pwd)/rpms"

    log_info "RPM包创建完成"
}

# 创建Docker镜像
create_docker_image() {
    log_info "创建Docker镜像..."

    # 设置变量
    VERSION=$(get_version)

    # 创建Dockerfile
    cat > Dockerfile << EOF
FROM ubuntu:22.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 安装依赖
RUN apt-get update && apt-get install -y \\
    luajit \\
    luarocks \\
    build-essential \\
    && rm -rf /var/lib/apt/lists/*

# 安装Lua依赖
RUN luarocks install lua-cjson \\
    && luarocks install luasocket \\
    && luarocks install llthreads2 \\
    && luarocks install lzmq

# 创建应用目录
WORKDIR /opt/stock-tsdb

# 复制应用文件
COPY bin/ /opt/stock-tsdb/bin/
COPY lib/ /opt/stock-tsdb/lib/
COPY lua/ /opt/stock-tsdb/lua/
COPY conf/ /opt/stock-tsdb/conf/

# 创建数据目录
RUN mkdir -p /var/lib/stock-tsdb /var/log/stock-tsdb

# 暴露端口
EXPOSE 6379 5555 8080

# 设置启动命令
CMD ["/opt/stock-tsdb/bin/stock-tsdb-server", "-c", "/opt/stock-tsdb/conf/stock-tsdb.conf"]
EOF

    # 构建Docker镜像
    docker build -t "stock-tsdb:$VERSION" .

    # 标记为latest
    docker tag "stock-tsdb:$VERSION" "stock-tsdb:latest"

    log_info "Docker镜像创建完成"
}

# 创建Snap包
create_snap_package() {
    log_info "创建Snap包..."

    # 安装snapcraft
    if ! command -v snapcraft &> /dev/null; then
        sudo snap install snapcraft --classic
    fi

    # 设置变量
    VERSION=$(get_version)

    # 创建snap目录
    mkdir -p snap

    # 创建snap/snapcraft.yaml
    cat > snap/snapcraft.yaml << EOF
name: stock-tsdb
version: '$VERSION'
summary: High-performance stock time series database
description: |
  Stock-TSDB is a high-performance time series database optimized for stock market data.
  It provides efficient storage and retrieval of stock quotes, trades, and other market data.

grade: stable
confinement: strict
base: core22

apps:
  stock-tsdb:
    command: bin/stock-tsdb-server
    plugs:
      - home
      - network
      - network-bind

parts:
  stock-tsdb:
    plugin: make
    source: .
    build-packages:
      - build-essential
      - luajit
      - luarocks
      - liblua5.1-0-dev
    stage-packages:
      - luajit
      - luarocks
EOF

    # 构建Snap包
    snapcraft

    log_info "Snap包创建完成"
}

# 显示帮助信息
show_help() {
    echo "Stock-TSDB Ubuntu/Debian 打包脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  --deb                   创建Debian包"
    echo "  --appimage              创建AppImage包"
    echo "  --rpm                   创建RPM包"
    echo "  --docker                创建Docker镜像"
    echo "  --snap                  创建Snap包"
    echo "  --all                   创建所有格式的包"
    echo "  --install-deps          仅安装打包依赖"
    echo
    echo "示例:"
    echo "  $0 --deb                创建Debian包"
    echo "  $0 --all                创建所有格式的包"
}

# 主函数
main() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB Ubuntu/Debian 打包脚本"
    log_info "==========================================="
    echo

    # 检测发行版
    detect_distro

    # 设置变量
    VERSION=$(get_version)
    log_info "版本: $VERSION"

    # 根据参数执行操作
    if [ "$INSTALL_DEPS" = "true" ]; then
        install_packaging_deps
        exit 0
    fi

    if [ "$CREATE_DEB" = "true" ] || [ "$CREATE_ALL" = "true" ]; then
        install_packaging_deps
        create_debian_structure
        build_debian_package
    fi

    if [ "$CREATE_APPIMAGE" = "true" ] || [ "$CREATE_ALL" = "true" ]; then
        create_appimage
    fi

    if [ "$CREATE_RPM" = "true" ] || [ "$CREATE_ALL" = "true" ]; then
        create_rpm_package
    fi

    if [ "$CREATE_DOCKER" = "true" ] || [ "$CREATE_ALL" = "true" ]; then
        create_docker_image
    fi

    if [ "$CREATE_SNAP" = "true" ] || [ "$CREATE_ALL" = "true" ]; then
        create_snap_package
    fi

    log_info "打包脚本执行完成!"
}

# 解析命令行参数
CREATE_DEB=false
CREATE_APPIMAGE=false
CREATE_RPM=false
CREATE_DOCKER=false
CREATE_SNAP=false
CREATE_ALL=false
INSTALL_DEPS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --deb)
            CREATE_DEB=true
            shift
            ;;
        --appimage)
            CREATE_APPIMAGE=true
            shift
            ;;
        --rpm)
            CREATE_RPM=true
            shift
            ;;
        --docker)
            CREATE_DOCKER=true
            shift
            ;;
        --snap)
            CREATE_SNAP=true
            shift
            ;;
        --all)
            CREATE_ALL=true
            shift
            ;;
        --install-deps)
            INSTALL_DEPS=true
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 如果没有指定选项，显示帮助
if [ "$CREATE_DEB" = "false" ] && [ "$CREATE_APPIMAGE" = "false" ] && [ "$CREATE_RPM" = "false" ] && [ "$CREATE_DOCKER" = "false" ] && [ "$CREATE_SNAP" = "false" ] && [ "$CREATE_ALL" = "false" ] && [ "$INSTALL_DEPS" = "false" ]; then
    show_help
    exit 0
fi

# 运行主函数
main