#!/bin/bash

export MACHINE="n1-standard-16"


finalize() {
	rm .ssh/authorized_keys &>/dev/null
	echo " * * * * * * REMEMBER TO SHUTDOWN THE COMPUTE INSTANCE * * * * * *"
	echo "# : gcloud compute instances delete --quiet scikit"
	exit
}

trap finalize SIGINT
trap finalize SIGTERM

echo "Creating..."
gcloud compute instances create scikit --image container-vm-v20140710 --image-project google-containers --machine-type $MACHINE || finalize
echo "Compute engine created"
gcloud compute ssh scikit --command "wait" || finalize
echo "Compute engine up"

IP=$(gcloud compute instances list | grep scikit | awk '{ print $5 }')
ssh-keygen -f "/home/neuron/.ssh/known_hosts" -R $IP

ssh -o StrictHostKeyChecking=no $IP << EOF
mkdir -p src/ml tmp/ml

#for zram:
wget https://gist.githubusercontent.com/andaag/ed2e8079f9dd588cb320/raw/b2c193773f44c7b3818d624890badf7b3cde0709/gistfile1.sh
sudo mv gistfile1.sh /etc/init.d/zram
sudo chmod +x /etc/init.d/zram
sudo /etc/init.d/zram start

#for reverse sshfs mount:
echo deb http://http.debian.net/debian wheezy contrib non-free | sudo tee -a /etc/apt/sources.list
sudo apt-get update
sudo apt-get -y install sshfs
sudo adduser neuron fuse
sudo modprobe fuse
sudo chmod o+rx /bin/fusermount
sudo chmod a+rwx /dev/fuse
echo "user_allow_other" | sudo tee -a /etc/fuse.conf
sudo docker pull andaag/sklearn_notebook3
echo "Docker image downloaded..."
EOF

#Reverse sshfs, requires ssh to localhost auth authorized key. I overwrite authorized keys locally because I don't use it for anything else
cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys 
dpipe /usr/lib/openssh/sftp-server = ssh $IP sshfs :/home/neuron/src/ml src/ml -o slave -o reconnect -C -o allow_root &
sleep 10
rm ~/.ssh/authorized_keys

echo "Starting up docker on localhost:8889"
ssh -L 8889:localhost:8889 -o StrictHostKeyChecking=no $IP << EOF
sudo docker run --privileged --rm=true -v /home/neuron/src/ml:/ml  -v /home/neuron/tmp/ml:/mnt --name="ml" -p 8889:8889 -t -i andaag/sklearn_notebook3 bash -c "umount /dev/shm ; mount -t tmpfs tmpfs -o rw,nosuid,nodev /dev/shm ; echo Listening on ; hostname -i ; groupadd ml && useradd ml -m -g ml -u 1000 && chown ml:ml /ml && sudo PYTHONUNBUFFERED=1 -sHu ml ipython notebook --no-browser --script --ip=0.0.0.0 --port 8889" -p 127.0.0.1:8889:8889
EOF

finalize
