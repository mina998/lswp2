# 验证域名
function verify_domain {
    # 接收输入域名
    while true; do
        echo -ne "$BC请输入域名(eg:www.demo.com):$ED "
        read -r INPUT_VALUE
        INPUT_VALUE=$(echo $INPUT_VALUE | tr 'A-Z' 'a-z')
        INPUT_VALUE=$(echo $INPUT_VALUE | awk '/^[a-z0-9][-a-z0-9]{0,62}(\.[a-z0-9][-a-z0-9]{0,62})+$/{print $0}')
        if [ -z "$INPUT_VALUE" ]; then
            echoYC "域名有误,请重新输入!!!"
            continue
        fi
        local is_bind_site=0
        # 查找域名是否绑定到其他站点
        local domain_list=$(grep -o 'vhDomain.*' "$VH_DOMAIN_FILE" | grep -oE "[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
        for item in $domain_list; do
            if [ "$INPUT_VALUE" = "$item" ]; then
                is_bind_site=1
            fi
        done
        if [ $is_bind_site -eq 1 ]; then
            echoCC '域名已绑定到其它虚拟机.'
            continue
        fi
        # 站点是否存在
        local alias=$(alias_from_domain $INPUT_VALUE)
        if [ -d "/home/$alias" ]; then
            echoCC "[$INPUT_VALUE]站点已存在."
            continue
        fi
        break
    done
}
# 查询虚拟主机别名
function query_vm_alias {
    HOST_NAME=''
    local vhost_list=(`grep 'member' "$VH_DOMAIN_FILE" | awk -F 'member | {' '{print $2}'`)
    i=0
    while [[ $i -lt ${#vhost_list[@]} ]]; do
        echo -e "${CC}${i})${ED} ${vhost_list[$i]}"
        let i++ 
    done
    if [ $i -eq 0 ]; then
        echoCC "没有可选站点."
    else
        echo -e "${YC}e${CC})${ED} ${LG}Back${ED}"
    fi
    while [[ $i -gt 0 ]] ; do
        echo -ne "${BC}请选择虚拟机,输入序号:${ED}"
        read num
        if [ "$num" = 'e' ]; then
            break
        fi
        expr $num - 1 &> /dev/null
        if [ $? -lt 2 ]; then
            [ -n "${vhost_list[$num]}" ] && HOST_NAME=${vhost_list[$num]} && break
        fi
        echoYC "输入有误."
    done
}
# 删除数据库所有表
function drop_db_tables {
    local db_name=$1
    # 数据库是否存在
    if [ ! -n "$(is_db_exist $db_name)" ]; then
        echoCC "数据库不存在."
        return $?
    fi
    local conn="mysql -D$db_name -s -e"
    local drop=$($conn "SELECT concat('DROP TABLE IF EXISTS ', table_name, ';') FROM information_schema.tables WHERE table_schema = '${db_name}'")
    $($conn "SET foreign_key_checks = 0; ${drop}")
}

# 重置面板账号密码
function reset_ols_user_password {
    echoCC "面板用户密码重置成功后.原有的所有用户将删除."
    local user; local pass1; local pass2
    while true; do
        echo -ne "${BC}输入账号(默认:admin): ${ED}"
        read -a user
        [ -z "$user" ] && user=admin
        [ $(expr "$user" : '.*') -ge 5 ] && break
        echoCC "账号长度不能小于5位."
    done
    while true; do
        echo -ne "${BC}输入密码: ${ED}"
        read -a pass1
        if [ `expr "$pass1" : '.*'` -lt 6 ]; then
            echoCC "密码长度不能小于6位."
            continue
        fi
        echo -ne "${BC}密码确认: ${ED}" 
        read -a pass2
        if [ "$pass1" != "$pass2" ]; then
            echoCC "密码不匹配,再试一次."
            continue
        fi
        break
    done
    cd $OLS_ROOT/admin/fcgi-bin
    local encrypt_pass=$(./admin_php -q ../misc/htpasswd.php $pass1)
    echo "$user:$encrypt_pass" > ../conf/htpasswd
    cd $RUN_PARH
    echoGC "面板用户密码重置完成."
}
# 获取域名解析结果
function dns_query {
    local vhost=$1
    local local_ip=$(query_public_ip)
    if (ping -c 2 $vhost &>/dev/null); then
        local domain_ip=$(ping $vhost -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
        if [ "$local_ip" != "$domain_ip" ]; then
            echo $domain_ip
        fi
    else
        echo '0.0.0.0'
    fi
}