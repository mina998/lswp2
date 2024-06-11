#!/bin/bash
if [ -z "${1}" ]; then
    echo '请输入参数'
    exit 1
fi
if [ ! -f "${1}.sh" ]; then
    echo "${1}.sh 文件不存在."
    exit 1
fi
# 输入文件和输出文件
input="${1}.sh"
output="${1}"
echo '' > $output
# 逐行读取输入文件
while IFS= read -r line
do
    if [[ "$line" == "source"* ]]; then
        file=$(echo $line | awk '{print $2}')
        if test -f "$file"; then
            cat $file >> $output
            echo -e "\n" >> "$output"
        else
            echo "$file 不存在"
            exit 1
        fi
    else
        echo "$line" >> "$output"
        echo -e "\n" >> "$output"
    fi
done < "$input"
sed -i '/^\s*#/d; /^\s*$/d' $output
# 在第一行插入内容
sed -i '1i #!/bin/bash' $output
