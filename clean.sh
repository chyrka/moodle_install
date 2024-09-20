#!/bin/bash

echo "Clean previous Moodle installation"
echo "###################################################"
echo "!!!Please pay attention that DB will be deleted!!!"
echo "###################################################"
sleep 15

sudo systemctl stop mysql
sudo systemctl stop nginx
sudo systemctl stop php-fpm

sudo dnf remove mariadb* nginx php* -y
sudo rm -rf /etc/nginx /etc/php-fpm.d 

sudo rm -rf /var/moodledata /var/www/html/moodle 

sudo rm -rf /var/lib/mysql
sudo rm -f /etc/my.cnf
sudo rm -rf /etc/mysql

sudo dnf autoremove

