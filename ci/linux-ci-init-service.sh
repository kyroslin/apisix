#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

docker exec -i apache-apisix_kafka-server1_1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server1:2181 --replication-factor 1 --partitions 1 --topic test2
docker exec -i apache-apisix_kafka-server1_1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server1:2181 --replication-factor 1 --partitions 3 --topic test3
docker exec -i apache-apisix_kafka-server2_1 /opt/bitnami/kafka/bin/kafka-topics.sh --create --zookeeper zookeeper-server2:2181 --replication-factor 1 --partitions 1 --topic test4

# prepare openwhisk env
docker pull openwhisk/action-nodejs-v14:nightly
docker run --rm -d --name openwhisk -p 3233:3233 -p 3232:3232 -v /var/run/docker.sock:/var/run/docker.sock openwhisk/standalone:nightly
docker exec -i openwhisk waitready
docker exec -i openwhisk bash -c "wsk action update test <(echo 'function main(args){return {\"hello\":args.name || \"test\"}}') --kind nodejs:14"

docker exec -i rmqnamesrv rm /home/rocketmq/rocketmq-4.6.0/conf/tools.yml
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test -c DefaultCluster
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test2 -c DefaultCluster
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test3 -c DefaultCluster
docker exec -i rmqnamesrv /home/rocketmq/rocketmq-4.6.0/bin/mqadmin updateTopic -n rocketmq_namesrv:9876 -t test4 -c DefaultCluster

# prepare vault kv engine
docker exec -i vault sh -c "VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault secrets enable -path=kv -version=1 kv"
