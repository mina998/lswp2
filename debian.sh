#!/bin/bash
# MySQL数据库版本
DB_VERSION=8.0
# OLS安装版本
OLS_VERSION=1.8.1
# 临时保存源码目录
SRC_PATH=/root/install
source ./const.sh
source ./colors.sh
# 是否存在系统信息文件
if [ ! -f /etc/os-release ]; then
    echoRC "当前操作系统不支持."
    exit 1
fi
# 导入变量
. /etc/os-release
if [ "$ID" != 'ubuntu' ] && [ "$ID" != 'debian' ]; then
    echoRC "当前操作系统不支持."
    exit 1
fi
# 导入函数
source ./common.sh
# 更新系统
apt update -y
# 安装所需工具
apt-get install socat cron curl wget gnupg unzip iputils-ping apt-transport-https ca-certificates software-properties-common gawk p7zip-full systemd-timesyncd -y
# 创建目录
[ ! -e "$SRC_PATH" ] && mkdir -p $SRC_PATH
# 检测面板是否安装
if [ -d $OLS_ROOT ]; then
    echoRC "检测到OpenLiteSpeed已安装"
    exit 1
fi
# 检查 MySQL 服务状态
if systemctl is-active --quiet mysql; then
    echoRC "安装失败, 本机已存在MySQL服务."
    exit 1
fi
# 切换目录
cd $SRC_PATH
# 安装面板
function install_ols {
    # 添加存储库
    wget -O - https://repo.litespeed.sh | bash
    wget https://openlitespeed.org/packages/openlitespeed-${OLS_VERSION}-x86_64-linux.tgz
    if [ $? -ne 0 ]; then
        echoRC '下载OpenLiteSpeed安装包失败'
        exit 1
    fi
    tar xf openlitespeed-${OLS_VERSION}-x86_64-linux.tgz
    cd openlitespeed
    sed -i 's/USE_LSPHP7=yes/USE_LSPHP7=no/' ols.conf
    cat ols.conf
    ./install.sh
    # 安装PHP 和 扩展
    apt install lsphp81 lsphp81-common lsphp81-intl lsphp81-curl lsphp81-opcache lsphp81-imagick lsphp81-mysql lsphp81-memcached -y
    # 删除其他PHP
    [ -f /usr/bin/php ]  && rm -f /usr/bin/php
    # 创建PHP软链接
    ln -s $OLS_ROOT/lsphp81/bin/php /usr/bin/php
    cd $SRC_PATH && rm -rf *
    # 下载配置文件
    curl $DOWNLOAD_URL/httpd_config > $OLS_CONF_DIR/httpd_config.conf
    # 下载证书文件
    curl $DOWNLOAD_URL/example.crt -o $OLS_CONF_DIR/example.crt
    curl $DOWNLOAD_URL/example.key -o $OLS_CONF_DIR/example.key
    # 下载wordpress 虚拟主机模板
    curl $DOWNLOAD_URL/wordpress -o $OLS_CONF_DIR/templates/wordpress.conf
    # 修改权限
    if [ $? -eq 0 ];then
        chown lsadm:nogroup $OLS_CONF_DIR/templates/wordpress.conf
    fi
    echo '' > $VH_DOMAIN_FILE
    chown lsadm:nogroup $VH_DOMAIN_FILE
    service lsws restart
}
install_ols

function install_wp_cli {
    # 切换目录
    cd $SRC_PATH
    # 安装WP CLI
    [ -e /usr/local/bin/wp ] && rm /usr/local/bin/wp
    [ -e /usr/bin/wp ] && rm /usr/bin/wp
    wget -Nq https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    # 下载失败
    if [ $? -ne 0 ]; then
        echoRC "${RC}下载WP CLI失败${ED}."
        exit 1
    fi 
    chmod +x wp-cli.phar
    echo $PATH | grep '/usr/local/bin' >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        mv wp-cli.phar /usr/local/bin/wp
    else
        mv wp-cli.phar /usr/bin/wp
    fi
}
install_wp_cli

function install_mysql {
    # 添加MySQL 密钥
    wget https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
    gpg --dearmor RPM-GPG-KEY-mysql-2023
    mv RPM-GPG-KEY-mysql-2023.gpg /etc/apt/trusted.gpg.d/
    rm RPM-GPG-KEY-mysql-2023
    # 检查MySQL密钥是否添加成功
    apt-key list 2>&1 | grep MySQL >/dev/null 
    if [ $? -ne 0 ]; then 
        echoRC '从repo.mysql.com添加密钥失败.请检查密钥问题!'
        exit 1
    fi
    # 添加MySQL仓库
    local mysql_repo='/etc/apt/sources.list.d/mysql.list'
    echo "deb http://repo.mysql.com/apt/${ID} $VERSION_CODENAME mysql-${DB_VERSION}" > "${mysql_repo}"  
    # 更新仓库源
    apt update -y
    if [ $? -ne 0 ]; then
        echoRC "更新包失败."
        exit 1
    fi
    # 设置MySQL root 密码
    mysql_root_password=$(random_str)
    debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password ${mysql_root_password}"
    debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password ${mysql_root_password}"
    # 非交互式安装MySQL
    DEBIAN_FRONTEND=noninteractive apt -y install mysql-server
    if [ $? != 0 ] ; then
        echoRC "安装MySQL时发生错误."
        echoYC "您可能需要手动运行'apt -y -f --allow-unauthenticated install mysql-server' 命令进行检查。中止安装!"
        exit 1
    fi
    # 启动MySQL
    service mysql start
    if [ $? -ne 0 ]; then
        echoRC "MySQL启动失败"
        exit 1
    fi
    echo -e "\n[client]\nuser=root\npassword=${mysql_root_password}\n" >> /etc/mysql/my.cnf
    chmod 600 /etc/mysql/my.cnf
}
install_mysql

# 安装PHPMyAdmin
function install_php_my_admin {
    # 切换工作目录
    local example=$OLS_ROOT/Example
    cd $example
    if [ -d "phpMyAdmin" ]; then
        echoRC '检测到phpMyAdmin已安装!'
        exit 1
    fi
    # 下载phpMyAdmin程序
    wget -O phpMyAdmin.zip https://files.phpmyadmin.net/phpMyAdmin/5.1.1/phpMyAdmin-5.1.1-english.zip
    if [ $? -ne 0 ]; then
        echoRC '下载phpMyAdmin失败!'
        exit 1
    fi
    # 解压文件
    unzip phpMyAdmin.zip > /dev/null 2>&1
    # 删除文件
    rm phpMyAdmin.zip
    # 重命名文件夹
    mv phpMyAdmin-5.1.1-english phpMyAdmin
    # 切换目录
    cd phpMyAdmin
    # 创建临时目录并设置权限
    mkdir tmp && chmod 777 tmp
    # 创建Cookie密钥
    keybs=$(random_str 64)
    # 修改配置文件1
    sed -i "/\$cfg\['blowfish_secret'\]/s/''/'$keybs'/" config.sample.inc.php
    # 切换目录
    cd libraries
    # 修改配置文件2
    sed -i "/\$cfg\['blowfish_secret'\]/s/''/'$keybs'/" config.default.php
    # 导入sql文件
    mysql < $example/phpMyAdmin/sql/create_tables.sql
    # 添加访问路径
    curl $DOWNLOAD_URL/context | sed s/context_path/phpMyAdmin/g >> $OLS_CONF_DIR/vhosts/Example/vhconf.conf
    # 重新加载
    systemctl restart lsws
}
install_php_my_admin

# 创建防火墙规则
function firewall_rules_create {
    #是否存在iptables
    if [ -z "$(which iptables)" ]; then
        echoRC 'iptables不存在'
        exit 1
    fi
    # 添加防火墙规则
    curl $DOWNLOAD_URL/firewall > /etc/iptables.rules
    # 添加重启自动加载防火寺规则
    curl $DOWNLOAD_URL/rc.local > /etc/rc.local
    # ssh端口
    local ssh=$(ss -tapl | grep sshd | awk 'NR==1 {print $4}' | cut -f2 -d :)
    [ -n "$ssh" ] && sed -i "s/22,80/$ssh,80/" /etc/iptables.rules
    # 添加执行权限
    chmod +x /etc/rc.local
    # 启动服务
    systemctl start rc-local
}
firewall_rules_create

function acme_sh_install {
    # 下载安装证书签发程序
    [ -d "/root/.acme.sh" ] && rm -rf /root/.acme.sh
    local email=$(tr -dc 'a-z' < /dev/urandom | head -c 8)@gmail.com
    curl https://get.acme.sh | sh -s email=$email
    # 重新设置CA账户
    /root/.acme.sh/acme.sh --register-account -m $email >/dev/null 2>&1
    # 更改证书签发机构
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echoRC 'SSL证书签发程序下载失败.'
        exit 1
    fi
}
acme_sh_install
# 设置时区
timedatectl set-timezone Asia/Shanghai
# 启用时间同步
timedatectl set-ntp true 
# 下载打包程序
curl $DOWNLOAD_URL/lswp > /usr/local/bin/lswp
chmod +x /usr/local/bin/lswp
echoPC '菜单指令: lswp'
# 查询公网IP
public_ip=$(query_public_ip)
# LSWS
echoCC '安装完成.请保存以下信息!'
echoGC '面板管理账号/密码'
echo -ne "$SB"
cat $OLS_ROOT/adminpasswd | grep -oE admin.*
echo -ne "$ED"
echoGC '面板地址'
echoSB "https://${public_ip}:7080"
echoGC "MySQL管理员账号密码"
echoSB "root / $mysql_root_password"
# phpMyAdmin
echoGC "phpMyAdmin安装完成."
echoSB "phpMyAdmin地址: http://$(query_public_ip):8088/phpMyAdmin"
# 删除源码目录
rm -rf $SRC_PATH

