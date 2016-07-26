#!/bin/bash
#placeholder for deployment script.
set -ex

#    ./01-deploybundle.sh $opnfvtype $openstack $opnfvlab $opnfvsdn $opnfvfeature $opnfvdistro

    #copy and download charms
    cp $4/fetch-charms.sh ./fetch-charms.sh
    #modify the ubuntu series wants to deploy
    sed -i -- "s|distro=trusty|distro=$6|g" ./fetch-charms.sh
    ./fetch-charms.sh $6

osdomname=''

#check whether charms are still executing the code even juju-deployer says installed.
check_status() {
    retval=0
    timeoutiter=0
    while [ $retval -eq 0 ]; do
       sleep 30
       juju status > status.txt
       if [ "$(grep -c "executing" status.txt )" -ge 2 ]; then
           echo " still executing the reltionship within charms ..."
           if [ $timeoutiter -ge 60 ]; then
               retval=1
           fi
           timeoutiter=$((timeoutiter+1))
       else
           retval=1
       fi
    done
    echo "...... deployment finishing ......."
}

#read the value from deployment.yaml
if [ -e ~/.juju/deployment.yaml ]; then
   cp ~/.juju/deployment.yaml ./deployment.yaml
   if [ -e ~/.juju/deployconfig.yaml ]; then
      cp ~/.juju/deployconfig.yaml ./deployconfig.yaml
      extport=`grep "ext-port" deployconfig.yaml | cut -d ' ' -f 4 | sed -e 's/ //' | tr ',' ' '`
      datanet=`grep "dataNetwork" deployconfig.yaml | cut -d ' ' -f 4 | sed -e 's/ //'`
      admnet=`grep "admNetwork" deployconfig.yaml | cut -d ' ' -f 4 | sed -e 's/ //'`
      cephdisk=`grep "ceph-disk" deployconfig.yaml | cut -d ':' -f 2 | sed -e 's/ //'`
      osdomname=`grep "os-domain-name" deployconfig.yaml | cut -d ':' -f 2 | sed -e 's/ //'`
   fi
fi

case "$3" in
     'juniperpod1' )
         sed -i -- 's/10.4.1.1/172.16.50.1/g' ./bundles.yaml
         sed -i -- 's/#ext-port: "eth1"/ext-port: "eth1"/g' ./bundles.yaml
         ;;
     'ravellodemopod' )
         sed -i -- 's/#ext-port: "eth1"/ext-port: "eth2"/g' ./bundles.yaml
        ;;
esac

# lets put the if seperateor as "," as this will save me from world.
fea=""
IFS=","
for feature in $5; do
    if [ "$fea" == "" ]; then
        fea=$feature
    else
        fea=$fea"_"$feature
    fi
done

#update source if trusty is target distribution
var=os-$4-$fea-$1"-"$6"_"$2

if [ "$osdomname" != "''" ]; then
    var=$var"_"publicapi
fi

#lets generate the bundle for all target using genBundle.py
python genBundle.py  -l deployconfig.yaml  -s $var > bundles.yaml

echo "... Deployment Started ...."
juju-deployer -vW -d -t 7200 -r 5 -c bundles.yaml $6-"$2"-nodes

# seeing issue related to number of open files.
# juju run --service nodes 'echo 2048 | sudo tee /proc/sys/fs/inotify/max_user_instances'

count=`juju status nodes --format=short | grep nodes | wc -l`

c=0
while [ $c -lt $count ]; do
    juju ssh nodes/$c 'echo 2048 | sudo tee /proc/sys/fs/inotify/max_user_instances'
    let c+=1
done

juju-deployer -vW -d -t 7200 -r 5 -c bundles.yaml $6-"$2" || true
