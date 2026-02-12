# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# install packages
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl containerd
sudo apt-mark hold kubelet kubeadm kubectl


# activate specific modules
# overlay — The overlay module provides overlay filesystem support, which Kubernetes uses for its pod network abstraction
# br_netfilter — This module enables bridge netfilter support in the Linux kernel, which is required for Kubernetes networking and policy.
sudo -i
modprobe br_netfilter
modprobe overlay


# enable packet forwarding, enable packets crossing a bridge are sent to iptables for processing
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf


# return to user
# In v1.22 and later, if the user does not set the cgroupDriver field under KubeletConfiguration, kubeadm defaults it to systemd.
# by default containerd set SystemdCgroup = false, so you need to activate SystemdCgroup = true, put it in /etc/containerd/config.toml
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/configure-cgroup-driver/
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers
sudo mkdir /etc/containerd/
sudo vim /etc/containerd/config.toml

version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
   [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true

sudo systemctl restart containerd            


# get master ip for --apiserver-advertise-address
ip a


# to access kubernetes from external network you need to additionaly set flag with external ip --apiserver-cert-extra-sans=158.160.111.211
sudo kubeadm init \
  --apiserver-advertise-address=10.128.0.28 \
  --pod-network-cidr 10.244.0.0/16


# set default kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


# install cni flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# вместо flannel можно использовать calico
# сначала установить helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add projectcalico https://docs.projectcalico.org/charts
# установить calico, надо учитывать, что tigera-operator должен быть в отдельном неймспейсе
helm install calico projectcalico/tigera-operator \
  --namespace tigera-operator \
  --create-namespace \
  --set-string "installation.calicoNetwork.ipPools[0].cidr=10.244.0.0/16" \
  --set-string "installation.calicoNetwork.ipPools[0].natOutgoing=Enabled"
# проверить что все запущено
kubectl get pods -A  

# add worker nodes
# kubeadm token generate 
# kubeadm token create 76mrvp.9y6jm4gi8kaht0cs --print-join-command --ttl=0
sudo kubeadm join 10.128.0.28:6443 --token zvxm7y.z61zq4rzaq3rtipk \
        --discovery-token-ca-cert-hash sha256:9b650e50a7a5b6261746684d033a7d6483ea5b84db8932cb70563b35f91080f7
# и послу установки calico получаем
kubectl get nodes
# NAME      STATUS   ROLES           AGE    VERSION
# kubadm1   Ready    <none>          112s   v1.30.14
# master1   Ready    control-plane   37m    v1.30.14

# Если вдруг будет ошибка
sudo systemctl stop kubelet
sudo kubeadm reset -f
sudo kubeadm init --apiserver-advertise-address=10.128.0.18 --pod-network-cidr=10.244.0.0/16
sudo systemctl start kubelet
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# добавим namespace test и запустим тестовый под из файла install/pod.yml
kubectl create namespace test
kubectl apply -f install/pod.yml
# просмотрим подробности по поду
kubectl describe pod test-web -n test
# проверить что под запустился
kubectl run test-curl -n test --image=curlimages/curl --rm -it -- curl http://test-web:8000/
kubectl detail pod test-web
# проверить что под запустился 
kubectl get pods -n test
# проверить что под запустился и получить логи
kubectl logs -n test test-web

# Если надо перегенерировать токен для подключения по external ip
# Создайте резервную копию текущих сертификатов
sudo cp -r /etc/kubernetes/pki /etc/kubernetes/pki-backup-$(date +%F)
# Удалите текущие сертификаты API-сервера
sudo rm /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
# Перегенерируйте сертификат API-сервера с публичным IP
sudo kubeadm init phase certs apiserver \
  --apiserver-cert-extra-sans=$PUBLIC_IP,$INTERNAL_IP,$HOSTNAME,127.0.0.1
# Перезапустите компоненты управления Kubernetes, чтобы они использовали новый сертификат
sudo systemctl restart kubelet
# Создайте новый токен для подключения узлов-воркеров
kubeadm token create --print-join-command --ttl=0

# На master1: обновите конфиг для удалённого доступа
kubectl config set-cluster kubernetes \
  --server=https://<externel_ip>:6443 \
  --kubeconfig=/etc/kubernetes/admin.conf

# Скопируйте конфиг на локальную машину
scp erick@<externel_ip>:/etc/kubernetes/admin.conf ~/.kube/config-remote

# На локальной машине отредактируйте ~/.kube/config-remote:
#   server: https://<externel_ip>:6443