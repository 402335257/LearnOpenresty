# lua-resty-kafak的timer问题

## 部署本地kafka

```
安装kafka

wget http://mirrors.tuna.tsinghua.edu.cn/apache/kafka/2.4.0/kafka_2.11-2.4.0.tgz

sudo tar -xzvf kafka_2.11-2.4.0.tgz -C /usr/local/

cd /usr/local

sudo ln -s kafka_2.11-2.4.0 kafka

安装zookeeper

wget https://mirrors.tuna.tsinghua.edu.cn/apache/zookeeper/zookeeper-3.5.6/apache-zookeeper-3.5.6-bin.tar.gz

sudo tar -xzvf apache-zookeeper-3.5.6-bin.tar.gz -C /usr/local/

cd /usr/local

sudo ln -s apache-zookeeper-3.5.6-bin zookeeper

sudo cp /usr/local/zookeeper/conf/zoo_sample.cfg /usr/local/zookeeper/conf/zoo.cfg

```

```
启动

sudo /usr/local/zookeeper/bin/zkServer.sh start

sudo /usr/local/kafka/bin/kafka-server-start.sh  -daemon /usr/local/kafka/config/server.properties 

创建topic

sudo /usr/local/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181  --replication-factor 1 --partitions 2 --topic test

测试发送和接收

/usr/local/kafka/bin/kafka-console-producer.sh  --broker-list 127.0.0.1:9092 --topic test

/usr/local/kafka/bin/kafka-console-consumer.sh --bootstrap-server 127.0.0.1:9092 --topic test --from-beginning 
```

## 跑单元测试
先安装test-nginx
```
https://github.com/openresty/test-nginx

apt-get install libtest-base-perl libipc-run3-perl libtest-longstring-perl
```

单元测试跑的有问题, no resolver defined to resolve,需要修改kafka配置文件server.properties
```
host.name=127.0.0.1
```

创建topic，每个topic的partition count为2
```
 sudo /usr/local/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181  --replication-factor 1 --partitions 2 --topic test

 sudo /usr/local/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181  --replication-factor 1 --partitions 2 --topic test2

 sudo /usr/local/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181  --replication-factor 1 --partitions 2 --topic test3

 sudo /usr/local/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181  --replication-factor 1 --partitions 2 --topic test4

 sudo /usr/local/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181  --replication-factor 1 --partitions 2 --topic test5

```


sendbuffer的TEST 5: aggregator 输出topic顺序不一样, 本机测试顺序为1,5,4
```
topic:test; partition_id:1
topic:test5; partition_id:1
topic:test4; partition_id:1
```


## 改成ngx.timer.every
```
1.use "_flush_pending_flag" to avoid creating timer.at when too many timers pending.
2.use timer.every to execute flushing and reset "_flush_pending_flag".
3.add test that trigger "too many pending timers"
```

## git 合并commit

```
git rebase -i HEAD~2
pick -> squash
git push -f
```
