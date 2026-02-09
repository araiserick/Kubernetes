# Deploy приложения с использованием Helm для управления зависимостями и конфигурацией. В данном случае, мы устанавливаем Traefik, который будет использоваться в качестве Ingress Controller для маршрутизации трафика к нашим приложениям.
helm install traefik traefik/traefik \
   --namespace traefik \
   --create-namespace \
   --set service.type=NodePort \
   --set ports.web.nodePort=32080 \
   --set ports.websecure.nodePort=32443

# Установка cert-manager для управления сертификатами TLS, которые будут использоваться Traefik для обеспечения безопасности соединений.
helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set installCRDs=true

# Деплой приложения, которое будет обрабатывать запросы. В данном случае, мы используем простой Nginx сервер, который будет доступен через Traefik.
kubectl apply -f - <<EOF
---
# Deployment приложения
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
  template:
    metadata:
      labels:
        app: my-app
    spec:
      nodeSelector:
        node-type: worker
      containers:
      - name: my-container
        image: nginx:stable-alpine3.23
        ports:
        - containerPort: 80
          name: http
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
      terminationGracePeriodSeconds: 30
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  minReadySeconds: 10
  revisionHistoryLimit: 5
  progressDeadlineSeconds: 600

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
EOF

# Деплой Ingress ресурса для маршрутизации трафика к нашему приложению через Traefik. В данном случае, мы настраиваем маршрут для домена "myapp.local", который будет направлять запросы на сервис "my-service".
kubectl apply -f - <<EOF
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-ingressroute
  namespace: default
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`my-app.example.com`) && PathPrefix(`/`)
    kind: Rule
    services:
    - name: my-service
      port: 80
EOF

# Проверка статуса развертывания и доступности приложения. Мы используем kubectl для получения информации о развертывании, сервисе и Ingress ресурсе, чтобы убедиться, что все компоненты работают корректно.
kubectl get deployments -n default
kubectl get services -n default
kubectl get ingressroutes -n default

# После успешного развертывания, вы можете проверить доступность приложения, отправив запрос на домен "my-app.example.com". Убедитесь, что ваш DNS настроен правильно или используйте файл hosts для локального тестирования.
curl http://my-app.example.com

# Удаляем развертывание и связанные ресурсы после тестирования, чтобы освободить ресурсы в кластере.
kubectl delete ingressroutes my-ingressroute -n default
kubectl delete services my-service -n default
kubectl delete deployments my-deployment -n default