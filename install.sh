#!/bin/bash

installUtils () {
	echo "*********************************Installing WGET..."
	yum install -y wget
	
	echo "*********************************Installing Maven..."
	wget http://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O 	/etc/yum.repos.d/epel-apache-maven.repo
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then
		sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo
	fi
	yum install -y apache-maven
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then
		alternatives --install /usr/bin/java java /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/java 20000
		alternatives --install /usr/bin/javac javac /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/javac 20000
		alternatives --install /usr/bin/jar jar /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/jar 20000
		alternatives --auto java
		alternatives --auto javac
		alternatives --auto jar
		ln -s /usr/lib/jvm/java-1.8.0 /usr/lib/jvm/java
	fi
	
	echo "*********************************Installing GIT..."
	yum install -y git
	
	echo "*********************************Installing Docker..."
	echo " 				  *****************Installing Docker via Yum..."
	if [ $(cat /etc/system-release|grep -Po Amazon) == Amazon ]; then
		yum install -y docker
	else
		echo " 				  *****************Adding Docker Yum Repo..."
		tee /etc/yum.repos.d/docker.repo <<-'EOF'
		[dockerrepo]
		name=Docker Repository
		baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
		enabled=1
		gpgcheck=1
		gpgkey=https://yum.dockerproject.org/gpg
		EOF
		rpm -iUvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
		yum install -y docker-io
	fi
	
	echo " 				  *****************Configuring Docker Permissions..."
	groupadd docker
	gpasswd -a yarn docker
	echo " 				  *****************Registering Docker to Start on Boot..."
	service docker start
	chkconfig --add docker
	chkconfig docker on
}

serviceExists () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"status" : ' | grep -Po '([0-9]+)')

       	if [ "$SERVICE_STATUS" == 404 ]; then
       		echo 0
       	else
       		echo 1
       	fi
}

getServiceStatus () {
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')

       	echo $SERVICE_STATUS
}

waitForAmbari () {
       	# Wait for Ambari
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
        TASKSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep -Po 'OK')
        if [ "$TASKSTATUS" == OK ]; then
                LOOPESCAPE="true"
                TASKSTATUS="READY"
        else
               	AUTHSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep HTTP | grep -Po '( [0-9]+)'| grep -Po '([0-9]+)')
               	if [ "$AUTHSTATUS" == 403 ]; then
               	echo "THE AMBARI PASSWORD IS NOT SET TO: admin"
               	echo "RUN COMMAND: ambari-admin-password-reset, SET PASSWORD: admin"
               	exit 403
               	else
                TASKSTATUS="PENDING"
               	fi
       	fi
       	echo "Waiting for Ambari..."
        echo "Ambari Status... " $TASKSTATUS
        sleep 2
       	done
}

waitForService () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
        until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED || "$SERVICE_STATUS" == INSTALLED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

waitForServiceToStart () {
       	# Ensure that Service is not in a transitional state
       	SERVICE=$1
       	SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
       	sleep 2
       	echo "$SERVICE STATUS: $SERVICE_STATUS"
       	LOOPESCAPE="false"
       	if ! [[ "$SERVICE_STATUS" == STARTED ]]; then
        	until [ "$LOOPESCAPE" == true ]; do
                SERVICE_STATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep '"state" :' | grep -Po '([A-Z]+)')
            if [[ "$SERVICE_STATUS" == STARTED ]]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************$SERVICE Status: $SERVICE_STATUS"
            sleep 2
        done
       	fi
}

stopService () {
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       	echo "*********************************Stopping Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == STARTED ]; then
        TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context": "Stop $SERVICE"}, "ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Stop $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [ "$TASKSTATUS" == COMPLETED ]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Stop $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
        echo "*********************************$SERVICE Service Stopped..."
       	elif [ "$SERVICE_STATUS" == INSTALLED ]; then
       	echo "*********************************$SERVICE Service Stopped..."
       	fi
}

startService (){
       	SERVICE=$1
       	SERVICE_STATUS=$(getServiceStatus $SERVICE)
       		echo "*********************************Starting Service $SERVICE ..."
       	if [ "$SERVICE_STATUS" == INSTALLED ]; then
        TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context": "Start $SERVICE" }, "ServiceInfo": {"maintenance_state" : "OFF", "state": "STARTED"}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/$SERVICE | grep "id" | grep -Po '([0-9]+)')

        echo "*********************************Start $SERVICE TaskID $TASKID"
        sleep 2
        LOOPESCAPE="false"
        until [ "$LOOPESCAPE" == true ]; do
            TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
            if [ "$TASKSTATUS" == COMPLETED ]; then
                LOOPESCAPE="true"
            fi
            echo "*********************************Start $SERVICE Task Status $TASKSTATUS"
            sleep 2
        done
        echo "*********************************$SERVICE Service Started..."
       	elif [ "$SERVICE_STATUS" == STARTED ]; then
       	echo "*********************************$SERVICE Service Started..."
       	fi
}

waitForAmbari () {
       	# Wait for Ambari
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
        TASKSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep -Po 'OK')
        if [ "$TASKSTATUS" == OK ]; then
                LOOPESCAPE="true"
                TASKSTATUS="READY"
        else
               	AUTHSTATUS=$(curl -u admin:admin -I -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME | grep HTTP | grep -Po '( [0-9]+)'| grep -Po '([0-9]+)')
               	if [ "$AUTHSTATUS" == 403 ]; then
               	echo "THE AMBARI PASSWORD IS NOT SET TO: admin"
               	echo "RUN COMMAND: ambari-admin-password-reset, SET PASSWORD: admin"
               	exit 403
               	else
                TASKSTATUS="PENDING"
               	fi
       	fi
       	echo "Waiting for Ambari..."
        echo "Ambari Status... " $TASKSTATUS
        sleep 2
       	done
}

waitForNifiServlet () {
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
       		TASKSTATUS=$(curl -u admin:admin -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller | grep -Po 'OK')
       		if [ "$TASKSTATUS" == OK ]; then
               		LOOPESCAPE="true"
       		else
               		TASKSTATUS="PENDING"
       		fi
       		echo "*********************************Waiting for NIFI Servlet..."
       		echo "*********************************NIFI Servlet Status... " $TASKSTATUS
       		sleep 2
       	done
}

deployTemplateToNifi () {
	echo "*********************************Importing NIFI Template..."		
       	# Import NIFI Template HDF 2.x
       	TEMPLATEID=$(curl -v -F template=@"$ROOT_PATH/Nifi/template/DeviceManagerDemo.xml" -X POST http://$AMBARI_HOST:9090/nifi-api/process-groups/root/templates/upload | grep -Po '<id>([a-z0-9-]+)' | grep -Po '>([a-z0-9-]+)' | grep -Po '([a-z0-9-]+)')
		sleep 1
		
		# Instantiate NIFI Template 2.x
		echo "*********************************Instantiating NIFI Flow..."
       	curl -u admin:admin -i -H "Content-Type:application/json" -d "{\"templateId\":\"$TEMPLATEID\",\"originX\":100,\"originY\":100}" -X POST http://$AMBARI_HOST:9090/nifi-api/process-groups/root/template-instance
       	sleep 1
       	
       	# Rename NIFI Root Group HDF 2.x
		echo "*********************************Renaming Nifi Root Group..."
		ROOT_GROUP_REVISION=$(curl -X GET http://$AMBARI_HOST:9090/nifi-api/process-groups/root |grep -Po '\"version\":([0-9]+)'|grep -Po '([0-9]+)')
		
		sleep 1
		ROOT_GROUP_ID=$(curl -X GET http://$AMBARI_HOST:9090/nifi-api/process-groups/root|grep -Po '("component":{"id":")([0-9a-zA-z\-]+)'| grep -Po '(:"[0-9a-zA-z\-]+)'| grep -Po '([0-9a-zA-z\-]+)')

		PAYLOAD=$(echo "{\"id\":\"$ROOT_GROUP_ID\",\"revision\":{\"version\":$ROOT_GROUP_REVISION},\"component\":{\"id\":\"$ROOT_GROUP_ID\",\"name\":\"Device-Manager-Demo\"}}")
		
		sleep 1
		curl -d $PAYLOAD  -H "Content-Type: application/json" -X PUT http://$AMBARI_HOST:9090/nifi-api/process-groups/$ROOT_GROUP_ID

	sleep 1
}

# Start NIFI Flow
startNifiFlow () {
    echo "*********************************Starting NIFI Flow..."
    	# Start NIFI Flow HDF 2.x
    	TARGETS=($(curl -u admin:admin -i -X GET http://$AMBARI_HOST:9090/nifi-api/process-groups/root/processors | grep -Po '\"uri\":\"([a-z0-9-://.]+)' | grep -Po '(?!.*\")([a-z0-9-://.]+)'))
       	length=${#TARGETS[@]}
       	echo $length
       	echo ${TARGETS[0]}
       	
       	for ((i = 0; i < $length; i++))
       	do
       		ID=$(curl -u admin:admin -i -X GET ${TARGETS[i]} |grep -Po '"id":"([a-zA-z0-9\-]+)'|grep -Po ':"([a-zA-z0-9\-]+)'|grep -Po '([a-zA-z0-9\-]+)'|head -1)
       		REVISION=$(curl -u admin:admin -i -X GET ${TARGETS[i]} |grep -Po '\"version\":([0-9]+)'|grep -Po '([0-9]+)')
       		TYPE=$(curl -u admin:admin -i -X GET ${TARGETS[i]} |grep -Po '"type":"([a-zA-Z0-9\-.]+)' |grep -Po ':"([a-zA-Z0-9\-.]+)' |grep -Po '([a-zA-Z0-9\-.]+)' |head -1)
       		echo "Current Processor Path: ${TARGETS[i]}"
       		echo "Current Processor Revision: $REVISION"
       		echo "Current Processor ID: $ID"
       		echo "Current Processor TYPE: $TYPE"

       		if ! [ -z $(echo $TYPE|grep "PutKafka") ] || ! [ -z $(echo $TYPE|grep "PublishKafka") ]; then
       			echo "***************************This is a PutKafka Processor"
       			echo "***************************Updating Kafka Broker Porperty and Activating Processor..."
       			if ! [ -z $(echo $TYPE|grep "PutKafka") ]; then
                    PAYLOAD=$(echo "{\"id\":\"$ID\",\"revision\":{\"version\":$REVISION},\"component\":{\"id\":\"$ID\",\"config\":{\"properties\":{\"Known Brokers\":\"$AMBARI_HOST:6667\"}},\"state\":\"RUNNING\"}}")
                else
                    PAYLOAD=$(echo "{\"id\":\"$ID\",\"revision\":{\"version\":$REVISION},\"component\":{\"id\":\"$ID\",\"config\":{\"properties\":{\"bootstrap.servers\":\"$AMBARI_HOST:6667\"}},\"state\":\"RUNNING\"}}")
                fi
       		else
       			echo "***************************Activating Processor..."
       				PAYLOAD=$(echo "{\"id\":\"$ID\",\"revision\":{\"version\":$REVISION},\"component\":{\"id\":\"$ID\",\"state\":\"RUNNING\"}}")
			fi
       		echo "$PAYLOAD"
       		
       		curl -u admin:admin -i -H "Content-Type:application/json" -d "${PAYLOAD}" -X PUT ${TARGETS[i]}
       	done
}

installDemoControl () {
		echo "*********************************Creating Demo Control service..."
       	# Create Demo Control service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DEVICE_MANAGER_DEMO_CONTROL

       	sleep 2
       	echo "*********************************Adding Demo Control component..."
       	# Add Demo Control component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DEVICE_MANAGER_DEMO_CONTROL/components/DEVICE_MANAGER_DEMO_CONTROL

       	sleep 2
       	echo "*********************************Creating Demo Control configuration..."
		
		tee control-config <<-'EOF'
			"properties" : {
"democontrol.download_url" : "https://github.com/vakshorton/DataSimulators.git",
"democontrol.install_dir" : "/root",
"democontrol.nifi_host_ip" : " "
			}
		EOF
		
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME control-config control-config
		
       	# Create and apply configuration
       	#/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME control-config "democontrol.install_dir" "/root"
       	#sleep 2
       	#/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME control-config "democontrol.download_url" "https://github.com/vakshorton/DataSimulators.git"
       	sleep 2
       	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME control-config "democontrol.nifi_host_ip" $(getent hosts $NIFI_HOST | awk '{ print $1 }')

       	sleep 2
       	echo "*********************************Adding Creating role to Host..."
       	# Add NIFI Master role to Sandbox host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/DEVICE_MANAGER_DEMO_CONTROL

       	sleep 15
       	echo "*********************************Installing Demo Control Service"
       	# Install Demo Control Service
       	TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/DEVICE_MANAGER_DEMO_CONTROL | grep "id" | grep -Po '([0-9]+)')
       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Demo Control"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/BIOLOGICS_DEMO_CONTROL grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

enablePhoenix () {
	echo "*********************************Installing Phoenix Binaries..."
	yum install -y phoenix
	echo "*********************************Enabling Phoenix..."
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site phoenix.functions.allowUserDefinedFunctions true
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.defaults.for.version.skip true
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.regionserver.wal.codec org.apache.hadoop.hbase.regionserver.wal.IndexedWALEditCodec
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.region.server.rpc.scheduler.factory.class org.apache.hadoop.hbase.ipc.PhoenixRpcSchedulerFactory
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME hbase-site hbase.rpc.controllerfactory.class org.apache.hadoop.hbase.ipc.controller.ServerRpcControllerFactory
}

enableSparkLLAP () {
	echo "*********************************Installing Spark-LLAP Binaries..."
	wget -P /usr/hdp/current/spark-client/lib/ http://repo.hortonworks.com/content/repositories/releases/com/hortonworks/spark-llap/1.0.0.2.5.3.0-37/spark-llap-1.0.0.2.5.3.0-37-assembly.jar
	echo "*********************************Configuring Spark-LLAP..."
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-defaults spark.sql.hive.hiveserver2.url "jdbc:hive2://$HIVESERVER_INTERACTIVE_HOST:10500"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-defaults spark.jars "/usr/hdp/current/spark-client/lib/spark-llap-1.0.0.2.5.3.0-37-assembly.jar"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-defaults spark.hadoop.hive.zookeeper.quorum "$ZK_HOST:2181"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-defaults spark.hadoop.hive.llap.daemon.service.hosts "@llap0"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-thrift-sparkconf spark.sql.hive.hiveserver2.url "jdbc:hive2://$HIVESERVER_INTERACTIVE_HOST:10500"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-thrift-sparkconf spark.jars "/usr/hdp/current/spark-client/lib/spark-llap-1.0.0.2.5.3.0-37-assembly.jar"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-thrift-sparkconf spark.hadoop.hive.zookeeper.quorum "$ZK_HOST:2181"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-thrift-sparkconf spark.hadoop.hive.llap.daemon.service.hosts "@llap0"
	sleep 1
	/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME spark-env spark_thrift_cmd_opts "--jars /usr/hdp/current/spark-client/lib/spark-llap-1.0.0.2.5.3.0-37-assembly.jar"
}

configureYarnMemory () {
	YARN_MEM_MAX=$(/var/lib/ambari-server/resources/scripts/configs.sh get $AMBARI_HOST $CLUSTER_NAME yarn-site | grep '"yarn.scheduler.maximum-allocation-mb"'|grep -Po ': "([0-9]+)'|grep -Po '([0-9]+)')
	echo "*********************************yarn.scheduler.maximum-allocation-mb is set to $YARN_MEM_MAX MB"
	if [[ $YARN_MEM_MAX -lt 6000 ]]; then
		echo "*********************************Changing YARN Container Memory Size..."
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME yarn-site "yarn.scheduler.maximum-allocation-mb" "6144"
		sleep 1	
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME yarn-site "yarn.nodemanager.resource.memory-mb" "6144"
	fi	
}

createDeviceManagerTables () {	
	HQL="CREATE TABLE IF NOT EXISTS telecom_device_status_log_$CLUSTER_NAME (
			serialNumber string, 
			status string, 
			state string, 
			internalTemp int, 
			signalStrength int, 
			eventTimeStamp bigint) 
		CLUSTERED BY (serialNumber) INTO 30 BUCKETS STORED AS ORC;"
	
	# CREATE DEVICE STATUS LOG TABLE
	beeline -u jdbc:hive2://$HIVESERVER_HOST:10000/default -d org.apache.hive.jdbc.HiveDriver -e "$HQL" -n hive
	
	HQL="CREATE TABLE IF NOT EXISTS telecom_device_details_$CLUSTER_NAME (
			serialNumber string, 
			deviceModel string, 
			latitude string, 
			longitude string, 
			ipAddress string, 
			port string) 
		CLUSTERED BY (serialNumber) INTO 30 BUCKETS STORED AS ORC;"
	
	# CREATE DEVICE DETAILS TABLE
	beeline -u jdbc:hive2://$HIVESERVER_HOST:10000/default -d org.apache.hive.jdbc.HiveDriver -e "$HQL" -n hive	
}

getNameNodeHost () {
       	NAMENODE_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/HDFS/components/NAMENODE|grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')
       	
       	echo $NAMENODE_HOST
}

getHiveServerHost () {
        HIVESERVER_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/HIVE/components/HIVE_SERVER|grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')

        echo $HIVESERVER_HOST
}

getHiveInteractiveServerHost () {
        HIVESERVER_INTERACTIVE_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/HIVE/components/HIVE_SERVER_INTERACTIVE|grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')

        echo $HIVESERVER_INTERACTIVE_HOST
}

getHiveMetaStoreHost () {
        HIVE_METASTORE_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/HIVE/components/HIVE_METASTORE|grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')

        echo $HIVE_METASTORE_HOST
}

getKafkaBroker () {
       	KAFKA_BROKER=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/KAFKA/components/KAFKA_BROKER |grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')
       	
       	echo $KAFKA_BROKER
}

getAtlasHost () {
       	ATLAS_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/ATLAS/components/ATLAS_SERVER |grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')
       	
       	echo $ATLAS_HOST
}

getNifiHost () {
       	NIFI_HOST=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_MASTER|grep "host_name"|grep -Po ': "([a-zA-Z0-9\-_!?.]+)'|grep -Po '([a-zA-Z0-9\-_!?.]+)')

       	echo $NIFI_HOST
}

captureEnvironment () {
	NIFI_HOST=$(getNifiHost)
	export NIFI_HOST=$NIFI_HOST
	NAMENODE_HOST=$(getNameNodeHost)
	export NAMENODE_HOST=$NAMENODE_HOST
	HIVESERVER_HOST=$(getHiveServerHost)
	export HIVESERVER_HOST=$HIVESERVER_HOST
	HIVESERVER_INTERACTIVE_HOST=$(getHiveInteractiveServerHost)
	export HIVESERVER_INTERACTIVE_HOST=$HIVESERVER_INTERACTIVE_HOST
	HIVE_METASTORE_HOST=$(getHiveMetaStoreHost)
	export HIVE_METASTORE_HOST=$HIVE_METASTORE_HOST
	HIVE_METASTORE_URI=thrift://$HIVE_METASTORE_HOST:9083
	export HIVE_METASTORE_URI=$HIVE_METASTORE_URI
	ZK_HOST=$AMBARI_HOST
	export ZK_HOST=$ZK_HOST
	KAFKA_BROKER=$(getKafkaBroker)
	export KAFKA_BROKER=$KAFKA_BROKER
	ATLAS_HOST=$(getAtlasHost)
	export ATLAS_HOST=$ATLAS_HOST
	COMETD_HOST=$AMBARI_HOST
	export COMETD_HOST=$COMETD_HOST
	env
	
	echo "export NIFI_HOST=$NIFI_HOST" >> /etc/bashrc
	echo "export NAMENODE_HOST=$NAMENODE_HOST" >> /etc/bashrc
	echo "export ZK_HOST=$ZK_HOST" >> /etc/bashrc
	echo "export KAFKA_BROKER=$KAFKA_BROKER" >> /etc/bashrc
	echo "export ATLAS_HOST=$ATLAS_HOST" >> /etc/bashrc
	echo "export HIVE_METASTORE_HOST=$HIVE_METASTORE_HOST" >> /etc/bashrc
	echo "export HIVE_METASTORE_URI=$HIVE_METASTORE_URI" >> /etc/bashrc
	echo "export COMETD_HOST=$COMETD_HOST" >> /etc/bashrc

	echo "export NIFI_HOST=$NIFI_HOST" >> ~/.bash_profile
	echo "export NAMENODE_HOST=$NAMENODE_HOST" >> ~/.bash_profile
	echo "export ZK_HOST=$ZK_HOST" >> ~/.bash_profile
	echo "export KAFKA_BROKER=$KAFKA_BROKER" >> ~/.bash_profile
	echo "export ATLAS_HOST=$ATLAS_HOST" >> ~/.bash_profile
	echo "export HIVE_METASTORE_HOST=$HIVE_METASTORE_HOST" >> ~/.bash_profile
	echo "export HIVE_METASTORE_URI=$HIVE_METASTORE_URI" >> ~/.bash_profile
	echo "export COMETD_HOST=$COMETD_HOST" >> ~/.bash_profile

	. ~/.bash_profile
}

installNifiAtlasReporter () {
	echo "*********************************Building Nifi Atlas Reporter"
	git clone https://github.com/vakshorton/NifiAtlasBridge.git
	cd $ROOT_PATH/NifiAtlasBridge/NifiAtlasFlowReportingTask
	mvn clean install
	cd $ROOT_PATH/NifiAtlasBridge/NifiAtlasLineageReportingTask
	mvn clean install
	cd $ROOT_PATH
	
	echo "*********************************Install Nifi Atlas Reporters..."
	mv -vf $ROOT_PATH/NifiAtlasBridge/NifiAtlasFlowReportingTask/target/NifiAtlasFlowReportingTask-0.0.1-SNAPSHOT.nar /usr/hdf/current/nifi/lib/
	mv -vf $ROOT_PATH/NifiAtlasBridge/NifiAtlasLineageReportingTask/target/NifiAtlasLineageReporter-0.0.1-SNAPSHOT.nar /usr/hdf/current/nifi/lib/
}

installNifiService () {
       	echo "*********************************Creating NIFI service..."
       	# Create NIFI service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI

       	sleep 2
       	echo "*********************************Adding NIFI MASTER component..."
       	# Add NIFI Master component to service
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_MASTER
		curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI/components/NIFI_CA
		
       	sleep 2
       	echo "*********************************Creating NIFI configuration..."

       	# Create and apply configuration
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-config $CONFIG_PATH/hdf-config/nifi-config/nifi-ambari-config.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-ambari-ssl-config $CONFIG_PATH/hdf-config/nifi-config/nifi-ambari-ssl-config.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-authorizers-env $CONFIG_PATH/hdf-config/nifi-config/nifi-authorizers-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-env $CONFIG_PATH/hdf-config/nifi-config/nifi-bootstrap-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-bootstrap-notification-services-env $CONFIG_PATH/hdf-config/nifi-config/nifi-bootstrap-notification-services-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-env $CONFIG_PATH/hdf-config/nifi-config/nifi-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-flow-env $CONFIG_PATH/hdf-config/nifi-config/nifi-flow-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-login-identity-providers-env $CONFIG_PATH/hdf-config/nifi-config/nifi-login-identity-providers-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-node-logback-env $CONFIG_PATH/hdf-config/nifi-config/nifi-node-logback-env.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-properties $CONFIG_PATH/hdf-config/nifi-config/nifi-properties.json

		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-state-management-env $CONFIG_PATH/hdf-config/nifi-config/nifi-state-management-env.json
		
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-jaas-conf $CONFIG_PATH/hdf-config/nifi-config/nifi-jaas-conf.json
				
		/var/lib/ambari-server/resources/scripts/configs.sh set $AMBARI_HOST $CLUSTER_NAME nifi-logsearch-conf $CONFIG_PATH/hdf-config/nifi-config/nifi-logsearch-conf.json
		
       	echo "*********************************Adding NIFI MASTER role to Host..."
       	# Add NIFI Master role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_MASTER

       	echo "*********************************Adding NIFI CA role to Host..."
		# Add NIFI CA role to Ambari Host
       	curl -u admin:admin -H "X-Requested-By:ambari" -i -X POST http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/hosts/$AMBARI_HOST/host_components/NIFI_CA

       	sleep 30
       	echo "*********************************Installing NIFI Service"
       	# Install NIFI Service
       	TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
		
		sleep 2       	
       	if [ -z $TASKID ]; then
       		until ! [ -z $TASKID ]; do
       			TASKID=$(curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context" :"Install Nifi"}, "Body": {"ServiceInfo": {"maintenance_state" : "OFF", "state": "INSTALLED"}}}' http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/services/NIFI | grep "id" | grep -Po '([0-9]+)')
       		 	echo "*********************************AMBARI TaskID " $TASKID
       		done
       	fi
       	
       	echo "*********************************AMBARI TaskID " $TASKID
       	sleep 2
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
               	TASKSTATUS=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER_NAME/requests/$TASKID | grep "request_status" | grep -Po '([A-Z]+)')
               	if [ "$TASKSTATUS" == COMPLETED ]; then
                       	LOOPESCAPE="true"
               	fi
               	echo "*********************************Task Status" $TASKSTATUS
               	sleep 2
       	done
}

waitForNifiServlet () {
       	LOOPESCAPE="false"
       	until [ "$LOOPESCAPE" == true ]; do
       		TASKSTATUS=$(curl -u admin:admin -i -X GET http://$AMBARI_HOST:9090/nifi-api/controller | grep -Po 'OK')
       		if [ "$TASKSTATUS" == OK ]; then
               		LOOPESCAPE="true"
       		else
               		TASKSTATUS="PENDING"
       		fi
       		echo "*********************************Waiting for NIFI Servlet..."
       		echo "*********************************NIFI Servlet Status... " $TASKSTATUS
       		sleep 2
       	done
}

instalHDFManagementPack () {
	wget http://public-repo-1.hortonworks.com/HDF/centos7/3.x/updates/3.0.0.0/tars/hdf_ambari_mp/hdf-ambari-mpack-3.0.0.0-453.tar.gz
ambari-server install-mpack --mpack=hdf-ambari-mpack-3.0.0.0-453.tar.gz --verbose

	sleep 2
	ambari-server restart
	waitForAmbari
	sleep 2
}

if [ ! -d "/usr/jdk64" ]; then
	echo "*********************************Install and Enable Oracle JDK 8"
	wget http://public-repo-1.hortonworks.com/ARTIFACTS/jdk-8u77-linux-x64.tar.gz
	tar -vxzf jdk-8u77-linux-x64.tar.gz -C /usr
	mv /usr/jdk1.8.0_77 /usr/jdk64
	alternatives --install /usr/bin/java java /usr/jdk64/bin/java 3
	alternatives --install /usr/bin/javac javac /usr/jdk64/bin/javac 3
	alternatives --install /usr/bin/jar jar /usr/jdk64/bin/jar 3
	export JAVA_HOME=/usr/jdk64
	echo "export JAVA_HOME=/usr/jdk64" >> /etc/bashrc
fi

export AMBARI_HOST=$(hostname -f)
echo "*********************************AMABRI HOST IS: $AMBARI_HOST"

export CLUSTER_NAME=$(curl -u admin:admin -X GET http://$AMBARI_HOST:8080/api/v1/clusters |grep cluster_name|grep -Po ': "(.+)'|grep -Po '[a-zA-Z0-9\-_!?.]+')

if [[ -z $CLUSTER_NAME ]]; then
        echo "Could not connect to Ambari Server. Please run the install script on the same host where Ambari Server is installed."
        exit 1
else
       	echo "*********************************CLUSTER NAME IS: $CLUSTER_NAME"
fi

export ROOT_PATH=$(pwd)
echo "*********************************ROOT PATH IS: $ROOT_PATH"

echo "*********************************Preparing HDF Artifacts..."
cd ~
git clone https://github.com/vakshorton/CloudBreakArtifacts
export CONFIG_PATH=~/CloudBreakArtifacts
cd $ROOT_PATH
echo "*********************************CONFIG PATH IS: $CONFIG_PATH"

export HADOOP_USER_NAME=hdfs
echo "*********************************HADOOP_USER_NAME set to HDFS"

echo "*********************************Waiting for cluster install to complete..."
waitForServiceToStart YARN

waitForServiceToStart HDFS

waitForServiceToStart HIVE

waitForServiceToStart ZOOKEEPER

sleep 10

export VERSION=`hdp-select status hadoop-client | sed 's/hadoop-client - \([0-9]\.[0-9]\).*/\1/'`
export INTVERSION=$(echo $VERSION*10 | bc | grep -Po '([0-9][0-9])')
echo "*********************************HDP VERSION IS: $VERSION"

echo "*********************************Load Demo Control Service into Ambari"
cd $ROOT_PATH
cp -Rvf $ROOT_PATH/DEVICE_MANAGER_DEMO_CONTROL /var/lib/ambari-server/resources/stacks/HDP/$VERSION/services/

if [[ -d "/usr/hdp/current/atlas-server"  && ! -d "/usr/hdp/current/atlas-client" ]]; then 
echo "*********************************Only Atlas Server installed, setting symbolic link"
	ln -s /usr/hdp/current/atlas-server /usr/hdp/current/atlas-client
	ln -s /usr/hdp/current/atlas-server/conf/application.properties /usr/hdp/current/atlas-client/conf/atlas-application.properties
fi

sleep 2

echo "*********************************Install HDF Management Pack..."
instalHDFManagementPack 
sleep 2

echo "*********************************Installing Utlities..."
installUtils
sleep 2

echo "*********************************Installing NIFI..."
installNifiService
sleep 2

NIFI_SERVICE_PRESENT=$(serviceExists NIFI)
if [[ "$NIFI_SERVICE_PRESENT" == 0 ]]; then
       	echo "*********************************NIFI Service Not Present, Installing..."
       	waitForAmbari
       	installNifiService
fi

installNifiAtlasReporter
startService NIFI	 	

NIFI_STATUS=$(getServiceStatus NIFI)
echo "*********************************Checking NIFI status..."
if ! [[ $NIFI_STATUS == STARTED || $NIFI_STATUS == INSTALLED ]]; then
       	echo "*********************************NIFI is in a transitional state, waiting..."
       	waitForService NIFI
       	echo "*********************************NIFI has entered a ready state..."
fi

if [[ $NIFI_STATUS == INSTALLED ]]; then
       	startService NIFI
else
       	echo "*********************************NIFI Service Started..."
fi

sleep 2
echo "*********************************Capturing Environment Data..."
captureEnvironment
sleep 2

echo "*********************************Create /root HDFS folder for Slider..."
hadoop fs -mkdir /user/root/
hadoop fs -chown root:hdfs /user/root/

#Create Docker working folder
echo "*********************************Creating Docker Home Folder..."
mkdir /home/docker/
mkdir /home/docker/dockerbuild/
mkdir /home/docker/dockerbuild/mapui

echo "*********************************Staging Slider Configurations..."
cd $ROOT_PATH/SliderConfig
cp -vf appConfig.json /home/docker/dockerbuild/mapui
cp -vf metainfo.json /home/docker/dockerbuild/mapui
cp -vf resources.json /home/docker/dockerbuild/mapui

echo "*********************************Copy redeployApplication.sh to /root"
cd $ROOT_PATH
cp -Rvf $ROOT_PATH/redeployApplication.sh /root

echo "*********************************Load Data Plane Client Service into Ambari"
git clone https://github.com/vakshorton/Utils
cp -Rvf $ROOT_PATH/Utils/DATA_PLANE_CLIENT /var/lib/ambari-server/resources/stacks/HDP/$VERSION/services/

# Build from source
echo "*********************************Building Device Monitor Storm Topology..."
cd $ROOT_PATH/DeviceMonitor
mvn clean package
cp -vf target/DeviceMonitor-0.0.1-SNAPSHOT.jar /home/storm

echo "*********************************Building Device Monitor Nostradamus Application..."
#Build Spark Project and Copy to working folder
cd $ROOT_PATH/DeviceMonitorNostradamusScala
mvn clean package
cp target/DeviceMonitorNostradamusScala-0.0.1-SNAPSHOT-jar-with-dependencies.jar /home/spark
cd $ROOT_PATH

#Import Spark Model
echo "*********************************Importing Spark Model..."
cd $ROOT_PATH/Model
unzip nostradamusSVMModel.zip
cp -rvf nostradamusSVMModel /tmp
cp -vf DeviceLogTrainingData.csv /tmp
hadoop fs -mkdir /demo/
hadoop fs -mkdir /demo/data
hadoop fs -mkdir /demo/data/model/
hadoop fs -mkdir /demo/data/checkpoint
hadoop fs -mkdir /demo/data/training/
hadoop fs -chmod -R 777 /demo/data/
hadoop fs -put /tmp/nostradamusSVMModel /demo/data/model/ 
hadoop fs -put /tmp/DeviceLogTrainingData.csv /demo/data/training/
#rm -Rvf /tmp/nostradamusSVMModel
#rm -vf /tmp/DeviceLogTrainingData.csv

#Create TransactionHistory Hive Table for Storm topology
#echo "*********************************Creating device_event_history Hive Table..."
#createDeviceEventTable

echo "*********************************Install GeoLite City DB for Nifi..."
wget http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz -P /home/centos
cd /home/centos
gunzip -vf GeoLite2-City.mmdb.gz
chmod 755 -R /home/centos

waitForNifiServlet
echo "*********************************Deploying NIFI Template..."
deployTemplateToNifi

echo "*********************************Starting NIFI Flow ..."
startNifiFlow
cd $ROOT_PATH

echo "*********************************Installing Demo Control Service ..."
installDemoControl

sleep 2
#Start Kafka
KAFKA_STATUS=$(getServiceStatus KAFKA)
echo "*********************************Checking KAFKA status..."
if ! [[ $KAFKA_STATUS == STARTED || $KAFKA_STATUS == INSTALLED ]]; then
       	echo "*********************************KAFKA is in a transitional state, waiting..."
       	waitForService KAFKA
       	echo "*********************************KAFKA has entered a ready state..."
fi

if [[ $KAFKA_STATUS == INSTALLED ]]; then
       	startService KAFKA
else
       	echo "*********************************KAFKA Service Started..."
fi

#Configure Kafka
echo "*********************************Configuring Kafka Topics..."
/usr/hdp/current/kafka-broker/bin/kafka-topics.sh --create --zookeeper $AMBARI_HOST:2181 --replication-factor 1 --partitions 1 --topic TechnicianEvent
/usr/hdp/current/kafka-broker/bin/kafka-topics.sh --create --zookeeper $AMBARI_HOST:2181 --replication-factor 1 --partitions 1 --topic DeviceEvents

sleep 2
AMBARI_INFRA_PRESENT=$(serviceExists AMBARI_INFRA)
if [[ "$AMBARI_INFRA_PRESENT" == 1 ]]; then
	# Start AMBARI_INFRA
	AMBARI_INFRA_STATUS=$(getServiceStatus AMBARI_INFRA)
	echo "*********************************Checking AMBARI_INFRA status..."
	if ! [[ $AMBARI_INFRA_STATUS == STARTED || $AMBARI_INFRA_STATUS == INSTALLED ]]; then
       	echo "*********************************AMBARI_INFRA is in a transitional state, waiting..."
		waitForService AMBARI_INFRA
       	echo "*********************************AMBARI_INFRA has entered a ready state..."
	fi

	if [[ $AMBARI_INFRA_STATUS == INSTALLED ]]; then
       	startService AMBARI_INFRA
	else
       	echo "*********************************AMBARI_INFRA Service Started..."
	fi
else
	echo "*********************************AMBARI_INFRA is not present, skipping..."
fi

#Configure Solr for Dashboard
#echo "*********************************Configuring Solr..."
#curl http://$AMBARI_INFRA_HOST:8983/solr/admin/cores?action=CREATE&name=settopbox&configSet=data_driven_schema_configs

HBASE_STATUS=$(getServiceStatus HBASE)
echo "*********************************Checking HBASE status..."
if ! [[ $HBASE_STATUS == STARTED || $HBASE_STATUS == INSTALLED ]]; then
       	echo "*********************************HBASE is in a transitional state, waiting..."
       	waitForService HBASE
       	echo "*********************************HBASE has entered a ready state..."
fi

if [[ $HBASE_STATUS == INSTALLED ]]; then
       	startService HBASE
else
       	echo "*********************************HBASE Service Started..."
fi

STORM_STATUS=$(getServiceStatus STORM)
echo "*********************************Checking STORM status..."
if ! [[ $STORM_STATUS == STARTED || $STORM_STATUS == INSTALLED ]]; then
       	echo "*********************************STORM is in a transitional state, waiting..."
       	waitForService STORM
       	echo "*********************************STORM has entered a ready state..."
fi

echo "*********************************Stoping STORM Service..."
STORM_STATUS=$(getServiceStatus STORM)
if [[ $STORM_STATUS == STARTED ]]; then
       	stopService STORM
else
       	echo "*********************************STORM Service Stopped..."
fi

echo "*********************************Starting STORM Service..."
STORM_STATUS=$(getServiceStatus STORM)
if [[ $STORM_STATUS == INSTALLED ]]; then
       	startService STORM
else
       	echo "*********************************STORM Service Started..."
fi

# Download Docker Images
echo "*********************************Downloading Docker Images for UI..."
service docker start
docker pull vvaks/mapui
docker pull vvaks/cometd

echo "*********************************Create Device Manager Hive Tables..."
createDeviceManagerTables

echo "*********************************Checking Yarn and Phoenix Configurations..."
configureYarnMemory
#enablePhoenix
#stopService HBASE
#startService HBASE

echo "*********************************Checking Spark Configurations..."
enableSparkLLAP
stopService SPARK
startService SPARK

echo "*********************************Setting Ambari-Server to Start on Boot..."
chkconfig --add ambari-server
chkconfig ambari-server on
echo "*********************************Installation Complete... "
cd $ROOT_PATH

exit 0
#yum-config-manager --enable epel
# Reboot to refresh configuration
#reboot now