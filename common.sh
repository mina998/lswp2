# 创建随机字符
function random_str {
    local length=10
    [ -n "$1" ] && length=$1
    echo $(head -c $length /dev/urandom | base64 | tr -d '/' | tr -d '=')
}
# 生成别名
function alias_from_domain {
    echo "$1" | sed 's/\-/_/g; s/\./_/g'
}
# 检测数据库是否存在
function is_db_exist {
    # 判断数据库是否存在 
    echo $(mysql -Nse "show DATABASES like '$1'")
}
# 从网络获取本机IP(防止有些机器无法获取公网IP)  
function query_public_ip {
    echo $(curl -s https://ip.idsss.workers.dev)
}
