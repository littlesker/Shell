#!/usr/bin/env bash
# Require Root Permission
# panel node deploy script
# Author: 阿拉凹凸曼 (https://sobaigu.com)

[ $(id -u) != "0" ] && { echo "错误: 请用root执行"; exit 1; }
sys_bit=$(uname -m)
if [[ -f /usr/bin/apt ]] || [[ -f /usr/bin/yum && -f /bin/systemctl ]]; then
	if [[ -f /usr/bin/yum ]]; then
		cmd="yum"
		$cmd -y install epel-release
	fi
	if [[ -f /bin/systemctl ]]; then
		systemd=true
	fi
	$cmd -y install git unzip  vim lrzsz screen ntp ntpdate crontabs net-tools telnet curl
	# 设置时区为CST
	echo yes | cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
	ntpdate cn.pool.ntp.org
	sed -i '/^.*ntpdate*/d' /etc/crontab
	sed -i '$a\* * * * 1 ntpdate cn.pool.ntp.org >> /dev/null 2>&1' /etc/crontab
	service crond restart
	hwclock -w

else
	echo -e " 哈哈……这个 ${red}辣鸡脚本${none} 不支持你的系统。 ${yellow}(-_-) ${none}" && exit 1
fi
service_Cmd() {
	if [[ $systemd ]]; then
		systemctl $1 $2
	else
		service $2 $1
	fi
}
error() {

	echo -e "\n$red 输入错误！$none\n"

}
pause() {

	read -rsp "$(echo -e "按$green Enter 回车键 $none继续....或按$red Ctrl + C $none取消.")" -d $'\n'
	echo
}
get_ip() {
	ip=$(curl -s https://ipinfo.io/ip)
	[[ -z $ip ]] && ip=$(curl -s https://api.ip.sb/ip)
	[[ -z $ip ]] && ip=$(curl -s https://api.ipify.org)
	[[ -z $ip ]] && ip=$(curl -s https://ip.seeip.org)
	[[ -z $ip ]] && ip=$(curl -s https://ifconfig.co/ip)
	[[ -z $ip ]] && ip=$(curl -s https://api.myip.com | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
	[[ -z $ip ]] && ip=$(curl -s icanhazip.com)
	[[ -z $ip ]] && ip=$(curl -s myip.ipip.net | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
	[[ -z $ip ]] && echo -e "\n$red 这小鸡鸡还是割了吧！$none\n" && exit
}

config_v2ray_ws() {
    read -p "绑定的域名:" fake_Domain
	read -p "转发路径『不要带/』:" forward_Path
	read -p "V2Ray端口:" v2ray_Port
	read -p "V2Ray额外ID:" alter_Id
	read -p "面板同步端口:" dbsync_Port
	read -p "节点ID:" node_Id
	read -p "数据库地址:" db_Host
	read -p "数据库名称:" db_Name
	read -p "数据库用户:" db_User
	read -p "数据库密码:" db_Password
	install_caddy
	install_v2ray
	firewall_set
	service_Cmd status caddy
	service_Cmd status v2ray
}

install_v2ray(){
	curl -L -s https://raw.githubusercontent.com/ColetteContreras/v2ray-ssrpanel-plugin/master/install-release.sh | bash
	echo -e "默认日志输出级别为debug，搞定后建议修改为error"
	if [[ $num == "1" ]]; then
		wget --no-check-certificate -O config.json https://raw.githubusercontent.com/828768/Shell/master/resource/v2ray-config.json
		sed -i -e "s/v2ray_Port/$v2ray_Port/g" config.json
		sed -i -e "s/alter_Id/$alter_Id/g" config.json
		sed -i -e "s/forward_Path/$forward_Path/g" config.json
		sed -i -e "s/dbsync_Port/$dbsync_Port/g" config.json
		sed -i -e "s/node_Id/$node_Id/g" config.json
		sed -i -e "s/db_Host/$db_Host/g" config.json
		sed -i -e "s/db_Name/$db_Name/g" config.json
		sed -i -e "s/db_User/$db_User/g" config.json
		sed -i -e "s/db_Password/$db_Password/g" config.json
		mv -f config.json /etc/v2ray/
	fi
	service_Cmd restart v2ray

	if [[ $num == "2" ]]; then
		service_Cmd status v2ray
		echo -e "没帮做自动配置，手动去改 /etc/v2ray/config.json"
		echo -e "可以参考这里：http://sobaigu.com/ssrpanel-v2ray-go.html#V2Ray"
	fi
}

install_caddy() {
	if [[ $cmd == "yum" ]]; then
		[[ $(pgrep "httpd") ]] && systemctl stop httpd
		[[ $(command -v httpd) ]] && yum remove httpd -y
	else
		[[ $(pgrep "apache2") ]] && service apache2 stop
		[[ $(command -v apache2) ]] && apt remove apache2* -y
	fi

	local caddy_tmp="/tmp/install_caddy/"
	local caddy_tmp_file="/tmp/install_caddy/caddy.tar.gz"
	if [[ $sys_bit == "i386" || $sys_bit == "i686" ]]; then
		local caddy_download_link="https://caddyserver.com/download/linux/386?license=personal"
	elif [[ $sys_bit == "x86_64" ]]; then
		local caddy_download_link="https://caddyserver.com/download/linux/amd64?license=personal"
	else
		echo -e "$red 自动安装 Caddy 失败！不支持你的系统。$none" && exit 1
	fi

	mkdir -p $caddy_tmp

	if ! wget --no-check-certificate -O "$caddy_tmp_file" $caddy_download_link; then
		echo -e "$red 下载 Caddy 失败！$none" && exit 1
	fi

	tar zxf $caddy_tmp_file -C $caddy_tmp
	cp -f ${caddy_tmp}caddy /usr/local/bin/

	if [[ ! -f /usr/local/bin/caddy ]]; then
		echo -e "$red 安装 Caddy 出错！" && exit 1
	fi

	setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/caddy

	if [[ $systemd ]]; then
		cp -f ${caddy_tmp}init/linux-systemd/caddy.service /lib/systemd/system/
		# sed -i "s/www-data/root/g" /lib/systemd/system/caddy.service
		sed -i "s/on-failure/always/" /lib/systemd/system/caddy.service
		systemctl enable caddy
	else
		cp -f ${caddy_tmp}init/linux-sysvinit/caddy /etc/init.d/caddy
		# sed -i "s/www-data/root/g" /etc/init.d/caddy
		chmod +x /etc/init.d/caddy
		update-rc.d -f caddy defaults
	fi

	mkdir -p /etc/ssl/caddy

	if [ -z "$(grep www-data /etc/passwd)" ]; then
		useradd -M -s /usr/sbin/nologin www-data
	fi
	chown -R www-data.www-data /etc/ssl/caddy
	rm -rf $caddy_tmp
	echo -e "Caddy安装完成！"

	# 修改配置
	mkdir -p /etc/caddy/
	if [[ $num == "1" ]]; then
		wget --no-check-certificate -O www.zip https://raw.githubusercontent.com/828768/Shell/master/resource/www.zip
		rm -rf /srv/www && unzip www.zip -d /srv/ && rm -f www.zip
		wget --no-check-certificate -O Caddyfile https://raw.githubusercontent.com/828768/Shell/master/resource/Caddyfile
		local user_Name=$(((RANDOM << 22)))
		sed -i -e "s/fake_Domain/$fake_Domain/g" Caddyfile
		sed -i -e "s/forward_Path/$forward_Path/g" Caddyfile
		sed -i -e "s/v2ray_Port/$v2ray_Port/g" Caddyfile
		sed -i -e "s/user_Name/$user_Name/g" Caddyfile
		mv -f Caddyfile /etc/caddy/
	fi
	service_Cmd restart caddy

	if [[ $num == "3" ]]; then
		service_Cmd status caddy
		echo -e "没帮你做自动配置，手动去改 /etc/caddy/Caddyfile"
		echo -e "可以参考这里：http://sobaigu.com/ssrpanel-v2ray-go.html#caddy"
	fi
}

# Firewall
firewall_set(){
    echo -e "[${green}Info${plain}] firewall set start..."
    if command -v firewall-cmd >/dev/null 2>&1; then
        systemctl status firewalld > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            firewall-cmd --permanent --zone=public --remove-port=443/tcp
            firewall-cmd --permanent --zone=public --remove-port=80/tcp
            firewall-cmd --permanent --zone=public --remove-port=${v2ray_Port}/tcp
            firewall-cmd --permanent --zone=public --remove-port=${v2ray_Port}/udp
			firewall-cmd --permanent --zone=public --add-port=443/tcp
            firewall-cmd --permanent --zone=public --add-port=80/tcp
            firewall-cmd --permanent --zone=public --add-port=${v2ray_Port}/tcp
            firewall-cmd --permanent --zone=public --add-port=${v2ray_Port}/udp
            firewall-cmd --reload
        else
            echo -e "[${yellow}Warning${plain}] firewalld looks like not running or not installed, please enable port 80, 443, ${v2ray_Port} manually if necessary."
        fi
    elif command -v iptables >/dev/null 2>&1; then
        /etc/init.d/iptables status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            iptables -L -n | grep -i ${v2ray_Port} > /dev/null 2>&1
            if [ $? -ne 0 ]; then
				iptables -D INPUT -p tcp --dport 443 -j ACCEPT
				iptables -D INPUT -p tcp --dport 80 -j ACCEPT
				iptables -D INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
				iptables -D INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
                iptables -A INPUT -p tcp --dport 443 -j ACCEPT
                iptables -A INPUT -p tcp --dport 80 -j ACCEPT
                iptables -A INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
                iptables -A INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
                /etc/init.d/iptables save
                /etc/init.d/iptables restart
				ip6tables -D INPUT -p tcp --dport 443 -j ACCEPT
				ip6tables -D INPUT -p tcp --dport 80 -j ACCEPT
				ip6tables -D INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
				ip6tables -D INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
                ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
                ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
                ip6tables -A INPUT -p tcp --dport ${v2ray_Port} -j ACCEPT
                ip6tables -A INPUT -p udp --dport ${v2ray_Port} -j ACCEPT
                /etc/init.d/ip6tables save
                /etc/init.d/ip6tables restart
            else
                echo -e "[${green}Info${plain}] port 80, 443, ${v2ray_Port} has been set up."
            fi
        else
            echo -e "[${yellow}Warning${plain}] iptables looks like shutdown or not installed, please manually set it if necessary."
        fi
    fi
    echo -e "[${green}Info${plain}] firewall set completed... port 80, 443, ${v2ray_Port} are enable"
}

install_ssr(){
	clear
	cd /usr/
  	wget https://github.com/jedisct1/libsodium/releases/download/1.0.16/libsodium-1.0.16.tar.gz
  	tar xf libsodium-1.0.16.tar.gz && cd libsodium-1.0.16
  	./configure && make -j2 && make install
  	echo /usr/local/lib > /etc/ld.so.conf.d/usr_local_lib.conf
  	rm -rf libsodium-1.0.16.tar.gz
	echo 'libsodium安装完成'
	
	cd /usr/
	echo 'SSR下载中...'
	git clone -b master https://github.com/ssrpanel/shadowsocksr.git && cd shadowsocksr && sh setup_cymysql.sh && sh initcfg.sh
	echo 'SSR安装完成'
	echo '开始配置节点连接信息...'
	stty erase '^H' && read -p "数据库服务器地址:" mysqlserver
	stty erase '^H' && read -p "数据库服务器端口:" port
	stty erase '^H' && read -p "数据库名称:" database
	stty erase '^H' && read -p "数据库用户名:" username
	stty erase '^H' && read -p "数据库密码:" pwd
	stty erase '^H' && read -p "本节点ID:" nodeid
	stty erase '^H' && read -p "本节点流量计算比例:" ratio
	sed -i -e "s/server_host/$mysqlserver/g" usermysql.json
	sed -i -e "s/server_port/$port/g" usermysql.json
	sed -i -e "s/server_db/$database/g" usermysql.json
	sed -i -e "s/server_user/$username/g" usermysql.json
	sed -i -e "s/server_password/$pwd/g" usermysql.json
	sed -i -e "s/nodeid/$nodeid/g" usermysql.json
	sed -i -e "s/noderatio/$ratio/g" usermysql.json
	echo -e "配置完成!\n如果无法连上数据库，请检查本机防火墙或者数据库防火墙!\n请自行编辑user-config.json，配置节点加密方式、混淆、协议等"
	
	#启动并设置开机自动运行
	chmod +x run.sh && ./run.sh
	sed -i '/shadowsocksr\/run.sh$/d'  /etc/rc.d/rc.local
	echo "/usr/shadowsocksr/run.sh" >> /etc/rc.d/rc.local
}

open_bbr(){
	cd
	wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh
	chmod +x bbr.sh
	./bbr.sh
}

echo -e "1.Install V2Ray+Caddy"
echo -e "2.Install V2Ray"
echo -e "3.Install Caddy"
echo -e "4.Install SSR"
echo -e "5.Open BBR"
stty erase '^H' && read -p "请输入数字进行安装[1-4]:" num
case "$num" in
	1)
	config_v2ray_ws
	;;
	2)
	install_v2ray
	;;
	3)
	install_caddy
	;;
	4)
	install_ssr
	;;
	5)
	open_bbr
	;;
	*)
	echo "请输入正确数字[1-4]:"
	;;
esac