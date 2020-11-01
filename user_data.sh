#! /bin/bash
sudo touch /home/ubuntu/.env
sudo echo 'HOST='${aws_db_host}'' >> /home/ubuntu/.env
sudo echo 'USERNAME='${aws_db_username}'' >> /home/ubuntu/.env
sudo echo 'PASSWORD='${aws_db_password}'' >> /home/ubuntu/.env
sudo echo 'DB='${aws_db_name}'' >> /home/ubuntu/.env
sudo echo 'BUCKET_NAME='${aws_bucket_name}'' >> /home/ubuntu/.env
