# 添加一个WordPress网站
function install_wp {
    # 接收用户输入
    echo -ne "$BC请输入站点管理员账号(默认:admin):$ED "
    read -a wp_user; [ -z "$wp_user" ] && wp_user=admin 
    echo -ne "$BC请输入站点管理员密码(默认:admin):$ED "
    read -a wp_pass; [ -z "$wp_pass" ] && wp_pass=admin
    echo -ne "$BC请输入站点管理员邮箱(默认:admin@$INPUT_VALUE):$ED "
    read -a wp_mail; [ -z "$wp_mail" ] && wp_mail="admin@$INPUT_VALUE"
    # 下载WP程序 wp core download --locale=zh_CN --allow-root
    wp core download --allow-root
    # 添加伪静态规则
    curl $DOWNLOAD_URL/htaccess > .htaccess
    # 把参数转换成变量
    local db_name; local db_user; local db_pass; eval "$1" "$2" "$3"
    local db_prefix=$(random_str 2)_
    # 创建数据库配置文件
    wp config create --dbname=$db_name --dbuser=$db_user --dbpass=$db_pass --dbprefix=$db_prefix --allow-root --quiet
    # 安装WordPress程序
    wp core install --url="http://$INPUT_VALUE" --title="My Blog" --admin_user=$wp_user --admin_password=$wp_pass --admin_email=$wp_mail --skip-email --allow-root
    # WP配置文件中添加新常量
    local wp_const="\ndefine('WP_POST_REVISIONS', false);"
    # 插入到文件
    sed -i "/\$table_prefix/a\\$wp_const" wp-config.php
}
# 创建站点
function create_site {
    cd $RUN_PARH
    # 验证域名
    verify_domain
    # 定义别名
    local alias=$(alias_from_domain $INPUT_VALUE)
    # 定义站点目录
    local site_root=/home/$alias
    # 设置数据库变量
    local db_pass=$(random_str 10)
    # 数据库是否存在
    if [ -n "$(is_db_exist $alias)" ]; then
        echoCC "数据库已存在."
        return $?
    fi
    # 创建数据库
    mysql -Nse "CREATE DATABASE \`${alias}\`"
    # 创建用户
    mysql -Nse "CREATE USER '${alias}'@'localhost' IDENTIFIED BY '${db_pass}'"
    # 设置数据库用户权限
    mysql -Nse "GRANT ALL PRIVILEGES ON \`${alias}\`.* TO '${alias}'@'localhost'"
    # 刷新权限
    mysql -Nse "FLUSH PRIVILEGES"
    # 添加用户
    if ! (id $alias &> /dev/null);then
        useradd -s /sbin/nologin -r $alias
    fi
    # 创建网站目录
    mkdir -p ${site_root}/{backup,logs,cert,$DOC_DIR_NAME}
    cd ${site_root}/${DOC_DIR_NAME}
    # 安装WordPress
    echo -ne "$BC是否安装WordPrss(y/N):$ED "
    read -a iswp
    if [ "$iswp" = "y" -o "$iswp" = "Y" ]; then
        install_wp "db_name=$alias" "db_user=$alias" "db_pass=$db_pass"
    else
        echo 'This a Temp Site.' > index.php
    fi
    # 修改权限
    chown -R $alias:$alias ${site_root}
    chown -R $alias:nogroup ${site_root}/${DOC_DIR_NAME}
    chmod 711 ${site_root}
    chmod 750 ${site_root}/${DOC_DIR_NAME}
    if [ -e .htaccess ]; then
        chown -R $alias:$alias .htaccess
    fi
    # 修改目录权限
    find ${site_root}/${DOC_DIR_NAME}/ -type d -exec chmod 750 {} \;
    # 修改文件权限
    find ${site_root}/${DOC_DIR_NAME}/ -type f -exec chmod 640 {} \;
    # 添加虚拟机配置
    echo -e "member $alias { \n\t vhDomain  \t $INPUT_VALUE \n}" >> $OLS_CONF_DIR/vhosts.conf
    # 重启服务
    systemctl restart lsws
    # clear
    echoGC "站点安装完成, ${CC}以下信息只显示一次."
    echoSB "地址: http://$INPUT_VALUE"
    if [ -n "$wp_user" ]; then
        echoSB "账号: $wp_user"
        echoSB "密码: $wp_pass"
    fi
    echoGC "数据库信息"
    echoSB "名称: ${alias}"
    echoSB "账号: ${alias}"
    echoSB "密码: ${db_pass}"
}
# 备份站点
function backup_site {
    # 切换工作目录
    cd $SITE_DOC_DIR
    if [ ! -n "$(is_db_exist $HOST_NAME)" ]; then
        echoCC "数据库不存在."
        return $?
    fi
    # 导出MySQL数据库
    mysqldump $HOST_NAME > $DB_SQL_NAME
    # 测数据库是否导出成功
    if [ $? -ne 0 ]; then
        echoCC '备份数据库失败'
        return $?
    fi
    # 切换目录
    cd $SITE_BACKUP
    # 备份网站保存名称
    local web_save_name=$(date +%Y-%m-%d.%H%M%S).web.7z
    # 打包本地网站数据,这里用--exclude排除文件及无用的目录
    7z a -mx=9 $web_save_name $SITE_DOC_DIR
    # 测数网站是否备份成功
    if [ $? -ne 0 ]; then
        echoCC '打包文件失败.不完整'
        return $?
    fi
    # 删除
    rm $SITE_DOC_DIR/$DB_SQL_NAME
    echoSB "备份文件列表, 总容量: $(du -sh)"
    # 查看备份
    ls -ghGA | awk 'BEGIN{OFS="\t"} NR > 1 {print $3, $7}'
    echoGC "备份完成."
}
# 恢复站点
function restore_site {
    # 切换工作目录
    cd $SITE_BACKUP
    if [ $(ls | wc -l) -eq 0 ]; then
        echoCC '没有备份文件'
        return $?
    fi
    # 查看备份
    echo -e "${SB}文件总大小:$ED $(du -sh)"
    # 查看备份 ls -lrthgG
    ls -ghGA | awk 'BEGIN{OFS="\t"} NR > 1 {print $3, $7}'
    # 接收用户输入
    echo -ne "$BC请输入要还原的文件名: $ED"
    read -a site_backup_file
    # 检查文件是否存在
    if [ -z $site_backup_file ] || [ ! -f $site_backup_file ]; then
        echoCC "$site_backup_file指定文件不存在"
        return $?
    fi
    # 检测文件格式
    if [[ ! $site_backup_file =~ .*\.7z$ ]]; then
        echoCC "[$site_backup_file]非指定的压缩格式"
        return $?
    fi
    # 判断临时目录
    if [ -d public_html ] ; then
        rm -rf public_html
    fi
    # 解压备份文件
    7z x $site_backup_file
    if [ ! -d public_html ] ; then
        echoCC "找不到指定目录"
        return 1
    fi
    cd public_html
    # 判断数据库文件是否存在
    if [ ! -f $DB_SQL_NAME ]; then
        echoCC '找不到SQL文件'
        return $?
    fi
    # 删除数据库中的所有表
    drop_db_tables "$HOST_NAME"
    # 导入备份数据
    mysql "$HOST_NAME" < $DB_SQL_NAME
    # 删除SQL
    rm $DB_SQL_NAME
    # 替换数据库信息
    sed -i -r "s/DB_NAME',\s*'(.+)'/DB_NAME', '$HOST_NAME'/" wp-config.php
    sed -i -r "s/DB_USER',\s*'(.+)'/DB_USER', '$HOST_NAME'/" wp-config.php
    # 定义WordPress配置文件位置
    local wp_config=$SITE_DOC_DIR/wp-config.php
    if [ -f "$wp_config" ]; then
        # 获取原数据库信息
        local original_db_password=$(grep -oE "DB_PASSWORD.*[\"\']{1}" "$wp_config" | sed -r '{s/.*,\s*//}' | sed s/[\'\"]*//g)
        sed -i -r "s/DB_PASSWORD',\s*'(.+)'/DB_PASSWORD', '$original_db_password'/" wp-config.php
    fi
    # 删除网站文件
    rm -rf $SITE_DOC_DIR/{.[!.],}*
    # 还原备份文件
    mv ./{.[!.],}* $SITE_DOC_DIR/ > /dev/null 2>&1
    # 删除临时目录
    cd .. && rm -rf public_html
    # 切换工作目录
    cd $SITE_ROOT
    # 修改所有者
    chown -R $HOST_NAME:nogroup $DOC_DIR_NAME/*
    # 修改目录权限
    find $DOC_DIR_NAME/ -type d -exec chmod 750 {} \;
    # 修改文件权限
    find $DOC_DIR_NAME/ -type f -exec chmod 640 {} \;
    # 重载配置
    service lsws restart
    echoGC '操作完成.'
}
# 完全删除站点
function delete_site {
    echoCC "请把文件备份到本地,将删除站点[$HOST_NAME]全部资料"
    echo -ne "${BC}确认完全删除站点,输入大写Y: ${ED}"; read -a ny1
    echo -ne "${BC}确认完全删除站点,输入小写y: ${ED}"; read -a ny2
    if [ "$ny2" != "y" -o "$ny1" != "Y" ]; then
        echoCC "已退出删除操作."
        return $?
    fi
    # 删除虚拟机配置
    sed -i "/^member $HOST_NAME {/,/^}/d" $VH_DOMAIN_FILE
    echoGC "站点配置文件删除完成."
    # 删除虚拟主机空间目录
    rm -rf $SITE_ROOT
    echoGC "站点所有文件删除完成."
    # 删除用户和组
    pkill -u $HOST_NAME
    # 删除用户
    if id $HOST_NAME >/dev/null 2>&1; then
        userdel $HOST_NAME
    fi
    # 删除数据库相关
    if [ -n $(is_db_exist "$HOST_NAME") ]; then
        # 查询数据库相关用户
        local db_user=$(mysql -Nse "select distinct user from mysql.db where db = '$HOST_NAME';")
        if [ -n "$db_user" ]; then
            mysql -e "drop user '$db_user'@'localhost';"
        fi
        # 删除数据库
        mysql -e "drop database $HOST_NAME;"
        echoGC "网站数据库已删除完成."
    else
        echoYC "[$HOST_NAME]数据库删除失败:不存在"
    fi
    menu 
    return $?
}
# 删除备份
function delete_backup {
    cd $SITE_BACKUP
    if [ $(ls | wc -l) -eq 0 ]; then
        echoCC '没有备份文件'
        return $?
    fi
    local files=(`ls`)
    i=0
    while [[ $i -lt ${#files[@]} ]]; do
        echo -e "${CC}${i})${ED} ${files[$i]}"
        let i++ 
    done
    echo -e "${YC}e${CC})${ED} ${LG}Back${ED}"
    echo -ne "${BC}请输入序号以空格隔开:${ED}"
    local item=''
    read nums
    if [ "$nums" = "e" ]; then
        return $?
    fi
    for n in $nums; do
        item=${files[$n]}
        if [ -n "$item" ] && [ -f "$item" ]; then
            rm $item
        fi
    done
    echoCC '删除完成.'
}
# 添加域名
function domain_add {
    # 获取域名部分
    local domain_str=`sed -n "/$HOST_NAME/{n;p}" $VH_DOMAIN_FILE`
    # 获取虚拟机绑定域名列表
    local domain_list=`echo $domain_str | awk '{print $2}'`
    echo -ne "${SB}已绑定域名列表: ${ED}"
    echoYC "$domain_list"
    # 接收域名
    verify_domain
    if [ -n "$INPUT_VALUE" ]; then
        sed -i "/$HOST_NAME/{n;s/.*/\t vhDomain \t $domain_list,$INPUT_VALUE/;}" $VH_DOMAIN_FILE
    else
        echoRR '添加域名失败'
        return $?
    fi
    # 重新获取列表 
    domain_list=`sed -n "/$HOST_NAME/{n;p}" $VH_DOMAIN_FILE | awk '{print $2}'`
    echoLG "绑定成功: $domain_list"
    # 重新加载配置
    service lsws force-reload
}
# 替换数据库域名
function replace_db_domain {
    echo -ne "${SB}请输入(eg:${LG}old.com,new.com${ED}${SB}):${ED} "
    read rs_domain
    local old=`echo $rs_domain | awk -F',' '{print $1}'`
    local new=`echo $rs_domain | awk -F',' '{print $2}'`
    echo -ne "${YC}替换数据库中的域名. ${LG}${old} -> ${new}. [${PC}Y/n${ED}${LG}]:${ED} "
    read confirm
    if [ -z "$confirm" ] || [ "$confirm" = "Y" ] || [ "$confirm" = "y" ]; then
        wp search-replace $old $new --allow-root --path=$SITE_DOC_DIR
    fi
    return $?
}
# 申请SSL证书
function cert_ssl_install {
    # 获取绑定域名列表
    local vm_domain_list=`sed -n "/$HOST_NAME/{n;p}" $VH_DOMAIN_FILE | awk '{print $2}'`
    echoCC "将为以下域名申请SSL证书:"
    echoSB "$vm_domain_list"
    # 解析成功列表
    local dns_domain_list=`echo $vm_domain_list | tr -d ' ' | tr ',' ' '`
    # 判断是否解析
    for item in $vm_bind_domains; do
        local dns_ip=$(dns_query "$item")
        if [ -n "$dns_ip" ]; then
             echoRR "[$item -> $dns_ip]:解析失败,该域名无法申请证书."
        else
            dns_domain_list[${#dns_domain_list[*]}]=$item
        fi
    done
    # 判断是否有域名解析成功
    if [ ${#dns_domain_list[*]} -eq 0 ]; then
        echoCC '没有域名解析成功.'
        return $?
    fi
    # 组装参数
    local domain_list="-d $(echo ${dns_domain_list[@]} | sed 's/ / -d /g')"
    # 开使申请证书
    /root/.acme.sh/acme.sh --issue $domain_list --webroot $SITE_DOC_DIR
    # #copy/安装 证书
    local ssl=$SITE_ROOT/cert/ssl.pem
    local key=$SITE_ROOT/cert/key.pem
    local fullchain=$SITE_ROOT/cert/fullchain.pem
    /root/.acme.sh/acme.sh --install-cert $domain_list --cert-file $ssl --key-file $key --fullchain-file $fullchain --reloadcmd "service lsws force-reload"
    echo -e "${GC}证书文件:${ED} ${SB}$ssl ${ED}"
    echo -e "${GC}私钥文件:${ED} ${SB}$key ${ED}"
    echo -e "${GC}证书全链:${ED} ${SB}$fullchain ${ED}"
    service lsws restart
}