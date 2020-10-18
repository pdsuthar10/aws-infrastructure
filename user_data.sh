#! /bin/bash
sudo mkdir /home/ubuntu/webapp
sudo chmod 777 /home/ubuntu/webapp
sudo touch /home/ubuntu/webapp/.env
sudo echo 'HOST='${aws_db_host}'' >> /home/ubuntu/webapp/.env
sudo echo 'username='${aws_db_username}'' >> /home/ubuntu/webapp/.env
sudo echo 'PASSWORD='${aws_db_password}'' >> /home/ubuntu/webapp/.env
sudo echo 'DB='${aws_db_name}'' >> /home/ubuntu/webapp/.env
sudo echo 'BUCKET_NAME='${aws_bucket_name}'' >> /home/ubuntu/webapp/.env
