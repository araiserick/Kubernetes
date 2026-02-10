# Перед использованием StorageClass и PVC убедитесь, что у вас установлен и настроен провайдер локального хранилища, например, Local Path Provisioner от Rancher. Это позволит Kubernetes автоматически создавать PV на основе PVC.
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Создаем pvc для нашего deployment
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
  namespace: default
  labels:
    app: my-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path-retain

# Создаем StorageClass для нашего pvc
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-retain
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true

# Deployment приложения
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  namespace: default
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  minReadySeconds: 10
  revisionHistoryLimit: 5
  progressDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app: my-app
    spec:
      terminationGracePeriodSeconds: 30
      volumes:
      - name: my-volume
        persistentVolumeClaim:
          claimName: my-pvc
      - name: config-volume
        configMap:
          name: my-configmap
          items:
          - key: file
            path: file
      - name: nginx-config
        configMap:
          name: my-configmap
          items:
          - key: nginx.conf
            path: nginx.conf
      initContainers:
      - name: init-container
        image: busybox
        command: ['sh', '-c', 'echo "Initialized at $(date)" > /data/init.log']
        volumeMounts:
        - name: my-volume
          mountPath: /data
      containers:
      - name: my-container
        image: nginx:stable-alpine3.23
        ports:
        - containerPort: 80
          name: http
        volumeMounts:
        - name: my-volume
          mountPath: /usr/share/nginx/html/data
        - name: config-volume
          mountPath: /homework/conf
          readOnly: true
        - name: nginx-config
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: nginx.conf
          readOnly: true
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20

---
# Service для доступа к подам
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: default
  labels:
    app: my-app
spec:
  selector:
    app: my-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    name: http
  type: ClusterIP

# ConfigMap для нашего deployment
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-configmap
  namespace: default
  labels:
    app: my-app
data:
  file: |
    This is a value from ConfigMap
    Accessible via /conf/file
  
  nginx.conf: |
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        
        location /conf/ {
            alias /homework/conf/;
            default_type text/plain;
            autoindex off;
            try_files $uri =404;
        }
        
        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }
    }
# Ingress для доступа к сервису извне
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  namespace: default
  labels:
    app: my-app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: my-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
