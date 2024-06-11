#!/bin/bash
source ./colors.sh
source ./const.sh
# 虚拟主机配置目录
VHOST_CONF_DIR=$OLS_CONF_DIR/vhosts
RUN_PATH=/home
# 站点文档目录
DOC_DIR_NAME=public_html
# 导出数据库的SQL文件名
DB_SQL_NAME=db.sql
# 检测是否安装OLS
if [ ! -f "$OLS_ROOT/bin/lswsctrl" ]; then
    echoRR "OpenLiteSpeed未安装"
    exit 1
fi
source ./common.sh
source ./utils.sh
source ./sitecmd.sh
# 常用站眯指令
function site_cmd {
    cd $RUN_PATH
    # 查看所有站点
    query_vm_alias
    [ -z "$HOST_NAME" ] && return $?
    # 定义站点根目录
    SITE_ROOT=$RUN_PATH/$HOST_NAME
    SITE_BACKUP=$SITE_ROOT/backup
    SITE_DOC_DIR=$SITE_ROOT/public_html
    while true; do
        echoCC "当前站点: $HOST_NAME"
        # 显示菜单
        echo -e "${YC}1${ED}.${LG}备份${ED}"
        echo -e "${YC}2${ED}.${LG}还原${ED}"
        echo -e "${YC}3${ED}.${LG}删除备份${ED}"
        echo -e "${YC}4${ED}.${LG}删除站点${ED}"
        echo -e "${YC}5${ED}.${LG}追加域名${ED}"
        echo -e "${YC}6${ED}.${LG}安装证书${ED}"
        echo -e "${YC}7${ED}.${LG}替换数据库域名${ED}"
        echo -e "${YC}e${ED}.${LG}返回${ED}"
        echo -ne "${BC}请选择: ${ED}"
        read -a num2
        case $num2 in 
            1) backup_site ;;
            2) restore_site ;;
            3) delete_backup ;;
            4) delete_site ;;
            5) domain_add ;;
            6) cert_ssl_install ;;
            7) replace_db_domain ;;
            e) break ;;
            *) echoCC '输入有误.'
        esac
        continue
    done
    HOST_NAME=''
    cd $RUN_PARH
}
# 设置菜单
function menu {
    while true; do
        echoCC '请选译菜单'
        echo -e "${YC}1${ED}.${LG}添加一个站点${ED}"
        echo -e "${YC}2${ED}.${LG}常用站点指令${ED}"
        echo -e "${YC}3${ED}.${LG}重置面板用户密码${ED}"
        echo -e "${YC}e${ED}.${LG}退出${ED}"
        echo -ne "${YC}请选择: ${ED}"
        read -a num
        case $num in
            1) create_site ;;
            2) site_cmd ;;
            3) reset_ols_user_password ;;
            e) exit 0 ;;
            *) clear
        esac
        continue
    done
    clear
}
menu
