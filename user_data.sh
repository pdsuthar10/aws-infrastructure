#! /bin/bash
sudo touch /home/ubuntu/.env
sudo echo 'HOST='${aws_db_host}'' >> /home/ubuntu/.env
sudo echo 'USERNAME='${aws_db_username}'' >> /home/ubuntu/.env
sudo echo 'PASSWORD='${aws_db_password}'' >> /home/ubuntu/.env
sudo echo 'DB='${aws_db_name}'' >> /home/ubuntu/.env
sudo echo 'BUCKET_NAME='${aws_bucket_name}'' >> /home/ubuntu/.env
sudo echo 'ENVIRONMENT='${aws_environment}'' >> /home/ubuntu/.env
sudo echo 'DOMAIN='${aws_domainName}'' >> /home/ubuntu/.env
sudo echo 'TOPIC_ARN='${aws_topic_arn}'' >> /home/ubuntu/.env
