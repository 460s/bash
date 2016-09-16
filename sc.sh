#!/bin/sh
# qq: d.syrovatskiy@ispsystem.com

ver="1.7.4"
sc="${0##*/}"
 
#подсветка
green(){
	printf "\033[32;1m$@\033[0m\n"

}

red(){
	printf "\033[31;1m$@\033[0m\n"

}

#детектим ОС
OSParams() { 
	if [ -f /etc/redhat-release ]; then
		ostype=centos
		osname=$(rpm -qf /etc/redhat-release)
	elif [ -f /etc/debian_version ]; then
		ostype=debian
		osname=$(lsb_release -s -i -c -r | xargs echo |sed 's; ;-;g')-$(dpkg --print-architecture)
		read osversion < /etc/debian_version  
		if [ "$(echo ${osversion} | cut -c 1)" = 8 ]; then
			osversion=jessie
		elif [ "$(echo ${osversion} | cut -c 1)" = 7 ]; then
			osversion=wheezy			
		fi
	else
		red "На данной ОС скрипт не работает"
		exit 0
	fi
}

#перезагрузка панели
MgrReload() { 
	#while killall core; do echo "yes"; done
	killall -9 core
	green "Панель перезапущена"
}

#Получаем IP и имя манагера
CheckParam(){
	mgrctl="/usr/local/mgr5/sbin/mgrctl"
	if [ $($mgrctl > /dev/null 2>&1 ; echo $?) = "1" ]; then
		mgr=$($mgrctl mgr | awk '/mgr/' | cut -d = -f2)	
	fi
	ipaddr=$(ip addr show | awk '$1 ~ /inet/ && $2 !~ /127.0.0|::1|fe80:/ {print $2}' |cut -d/ -f1 | head -1)
}

#проверка обновлений скрипта
CheckUpdate(){ 
	fullpath=$(curl -I https://github.com/460s/ISPmgr_config/releases/latest 2>/dev/null | awk '/tag/' | tr -d '\r') ##curl может и не быть
	gitver="${fullpath##*/}"
	if ! [ -z $gitver ]
	then
		if [ $ver != $gitver ]; then
			echo "Скрипт версии $ver будет обновлен до $gitver"
			wget https://github.com/460s/ISPmgr_config/archive/$gitver.tar.gz > /dev/null 2>&1
			extract=$(tar xvzf $gitver.tar.gz)
			dirupd=$(echo $extract | cut -d / -f 1)
			cat $dirupd/changelog | head -4
			mv -f $dirupd/$sc $0
			rm -f $gitver.tar.gz
			rm -rf $dirupd
			if	grep "$gitver" $0 > /dev/null; then
				green "Скрипт обновлен. Перезапустите скрипт."
			else
				red "Скрипт не обновлен. Вам к d.syrovatskiy"
			fi
			exit 0	
		fi
	else
		red "Скрипт не обновиться, на машине отсутствует curl"
	fi
}

#вывод сообщений с подсказками
Usage()
{
        cat << EOU >&2

Ключи:
        $sc --help       Вывод списка ключей

        $sc [ключ] 
    -v  Версия скрипта
	-1  Запуск install.5.sh
	-2  Обновиться из репозитория
	-3  Установить debug.conf
	-4  Установить dev окружение
	-5  Запуск install.4.sh
	-6  Установить наш billmgr
	-7  Вкл/Выкл автообновлений
EOU
}

#добавление скрипта в алиасы
AddAlias(){
	if ! grep "alias ыс" ~/.bashrc > /dev/null; then
		chmod +x $0
		echo "alias sc='sh $(pwd)/$sc'" >> ~/.bashrc
		echo "alias ыс='sh $(pwd)/$sc'" >> ~/.bashrc
		echo "============="
		echo "Добавлен псевдоним вашего скрипта"
		printf "Обновите список alias командой \033[32;1m. ~/.bashrc\033[0m\n"
		printf "Скрипт можно вызвать в любом месте командой \033[32;1msc\033[0m\n"
		echo "============="
	fi
}

CheckUpdate
AddAlias
CheckParam
OSParams
	
#парсим аргументы
if [ -n "$1" ]
then
	case "${1}" in
		-h | --help) Usage; exit 0 ;;
		-v) echo $ver ;;
		1 | -1) select=inst; instv=5 ;;
		2 | -2) select=update ;;
		3 | -3) select=debug ;;
		4 | -4) select=dtools ;;
		5 | -5) select=inst; instv=4 ;;
		6 | -6) select=otherinst; instv=5 ;;
		7 | -7) select=autoupd ;;
		*)  Usage; exit 0 ;; 
	esac
else
	echo
	green $osname
	green "Выберите необходимое действие:"
	while [ -z $select ]
	do
		echo "1) Запуск install.5.sh"
		echo "2) Обновиться из репозитория"
		echo "3) Установить debug.conf"
		echo "4) Установить dev окружение"
		echo "5) Запуск install.4.sh"
		echo "6) Установить наш billmgr"
		echo "7) Вкл/Выкл автообновлений"
		echo "8) Скрипт начальной загрузки"
		echo

		read -p "Что будем делать: " n
		echo

		case "$n" in
			1) select=inst; instv=5 ;;
			2) select=update ;;
			3) select=debug ;;
			4) select=dtools ;;
			5) select=inst; instv=4 ;;
			6) select=otherinst ;;
			7) select=autoupd ;;
			8) select=startsc ;;
			*) ;;
		esac
	done
fi

case "$select" in
	inst) 
		#Запускаем скрипт установки 4/5 версии продукта
		#Отключаем автообновления и ставим два текстовых редактора
		if [ -f install.$instv.sh ]; then
			red "Файл install.$instv.sh уже cуществует, запускаем"
			sh install.$instv.sh
			CheckParam
			$mgrctl -m $mgr srvparam autoupdate=noupdate sok=ok > /dev/null
		else
			if wget http://cdn.ispsystem.com/install.$instv.sh > /dev/null 2>&1
			then
				green "Файл install.$instv.sh загружен, запускаем"
				sh install.$instv.sh
				CheckParam
				$mgrctl -m $mgr srvparam autoupdate=noupdate sok=ok > /dev/null
				case "$ostype" in
        			centos)
						if ! rpm -q vim > /dev/null; then
							yum -y install vim
						fi
						if ! rpm -q nano > /dev/null; then
							yum -y install nano
						fi
					;;
					debian)
						apt-get -y install vim
						apt-get -y install nano
					;;
					*);;
				esac
			else
				red "Файл install.$instv.sh не загружен"
			fi
		fi	 
	;;
	update)
		#Получаем имя репозитория
		#Обновляемся из текущего репа или из введенного user'ом
		if [ $ostype = "debian" ]; then
			reponame=$(cat /etc/apt/sources.list.d/ispsystem.list | awk '/ispsystem/{print $3}' | cut -d - -f 1)
		elif [ $ostype = "centos" ]; then
			reponame=$(cat /etc/yum.repos.d/ispsystem.repo | awk '/name/ && !/#/' | cut -d - -f 2)
		fi
		
		printf "Произойдет обновление из \033[32;1m$reponame\033[0m\n"
		echo "Нажмите Enter для обновления из $reponame или введите имя нового репозитория"
		read answer
		if [ -n "$answer" ]; then
			reponame=$answer
	    fi

		case "$ostype" in
        centos)
			rm -f /etc/yum.repos.d/ispsystem.repo #долго подключается к download
			wget -O /etc/yum.repos.d/ispsystem.repo "http://intrepo.download.ispsystem.com/repo/centos/ispsystem-template.repo" && sed -i -r "s/TYPE/$reponame/g" /etc/yum.repos.d/ispsystem.repo
			yum clean metadata
			yum clean all
			yum -y update			
		;;
		debian)
			rm -f /etc/apt/sources.list.d/ispsystem.list
			echo "deb http://intrepo.download.ispsystem.com/repo/debian $reponame-$osversion main" > /etc/apt/sources.list.d/ispsystem.list
			apt-get update 
			apt-get -y dist-upgrade
		;;
		*);;
		esac
	;;
	debug)
		if [ -f /usr/local/mgr5/etc/debug.conf ]; then
			green "Конфиг какого manager необходим?:"
			echo $debugconf
			while [ -z "$debugconf" ]
			do
				echo "1) ISPmanager"
				echo "2) BILLmanager"
				echo "3) VMmanagerKVM"
				echo "4) VMmanagerOVZ"
				echo

				read -p "Что будем делать: " n
				echo

				case "$n" in
					1) 
						debugconf="* 9\n*.conn 4\n*.cache 4\n*.longtask 4\n*.cache 4\n*.sprite 4\n*.merge 4\n*.config 4\n*.stdconfig 4\n*.xml 4\n*.action 4\n*.period 4\n*.libmgr 4\n*.core_decoration 4\n*.output 4"
					;;
					2) 
						debugconf="* 6\n*.db 6\n*.core 4\n*.conn 4\n*.merge 4\n*.xmli 4\n*.cache 4\n*.longtask 4" 				
					;;
					3) 
						debugconf="* 6\n*.db 4\n*.core 4\n*.conn 4\n*.merge 4\n*.xmli 4\n*.cache 4\n*.longtask 4\n*.vmmgr 9\n*.virt 9\n*.migratevm 9\n*.cloud 9" 				
					;;
					4) 
						debugconf="* 6\n*.db 4\n*.core 4\n*.conn 4\n*.merge 4\n*.xmli 4\n*.cache 4\n*.longtask 4\n*.ve_openvz 9\n*.vemgr 9" 				
					;;
					*) ;;
				esac
			done
			echo -e "$debugconf" > /usr/local/mgr5/etc/debug.conf
			green "Файл debug.conf изменен" 
			MgrReload
		else
			red "Файл debug.conf не существует"
		fi
	;;
	dtools)
		case "$ostype" in
        centos)
			yum -y install coremanager-devel gcc-c++ make unzip cgdb gtest-isp gtest-isp-devel
        ;;
		debian)
			apt-get -y install coremanager-dev g++ make unzip cgdb gtest-isp gtest-isp-dev
		;;
		*);;
		esac
	;;
	otherinst)
		echo "Введите имя репозитория для установки Billmgr"
		read reponame
		
		if [ -f install.$instv.sh ]; then
			red "Файл install.$instv.sh уже cуществует, запускаем"
			sh install.$instv.sh --noinstall --release $reponame
		else
			if wget http://cdn.ispsystem.com/install.$instv.sh > /dev/null 2>&1
			then
				green "Файл install.$instv.sh загружен, запускаем"
				sh install.$instv.sh --noinstall --release $reponame
				case "$ostype" in	
					centos)
						yum -y install billmanager			
					;;
					debian)
						apt-get -y install billmanager
					;;
					*);;
				esac
			else
				red "Файл install.$instv.sh не загружен"
			fi
		fi
	;;
	autoupd)
		if [ $($mgrctl -m $mgr srvparam | awk '/autoupdate/' | cut -d = -f2) = "noupdate" ] 
		then
			stneed="updatecore"
			printf "Обновления выключены. \033[32;1mВключаем?\033[0m (y/n)" 
		else
			stneed="noupdate"
			printf "Обновления включены. \033[31;1mВыключаем?\033[0m (y/n)" 
		fi

		read n 
		
		case "$n" in
			y|Y|д|Д) 
				green "Готово!"
				$mgrctl -m $mgr srvparam autoupdate=$stneed sok=ok > /dev/null
			;;
			n|N|н|Н) 
				red "Выход"
				exit 0
			;;
			*) ;;
		esac
	;;
	*) ;;
esac


#VDSmgr http://dl.ispsystem.com/Linux-cc6/x86_64/VDSmanager-Linux/
