# берем наш кубер на него деплоим манифесты с 3 репликами приложения
kubectl apply -f deployment.yml
# проверяем что все запустилось
kubectl get pods -n deployment
# NAME                         READY   STATUS    RESTARTS   AGE
# deployment-app-5d4b6f7c9b-abcde   1/1     Running   0          2m
# deployment-app-5d4b6f7c9b-fghij   1/1     Running   0          2m

# пробуем достучаться до приложения внутри кластера
kubectl exec -n deployment deployment-app-5d4b6f7c9b-abcde -- curl -s http://deployment-app:8000/
# пробуем достучаться до приложения с хоста кубера
kubectl port-forward -n deployment deployment-app-5d4b6f7c9b-abcde 8080:8000 & curl -s http://127.0.0.1:8080/
# меняю манифест чтобы была другая версия приложения
kubectl apply -f deployment-v2.yml
# проверяем что все запустилось
kubectl get pods -n deployment
# NAME                         READY   STATUS    RESTARTS   AGE
# deployment-app-5d4b6f7c9b-abcde   1/1     Running   0          10m
# deployment-app-5d4b6f7c9b-fghij   1/1     Running   0          10m
# deployment-app-5d4b6f7c9b-klmno   1/1     Running   0          2m
# где указываем стратегию обновления приложения в deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
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
      spec:
        nodeSelector:
          node-type: worker
      containers:
      - name: my-container
        image: nginx:stable-alpine3.23
        ports:
        - containerPort: 80
# настройки readness probe для проверки готовности приложения
# если приложение не готово, то трафик на него не пойдет
      readnessProbe:
        httpGet:
          path: /
          port: 80
# периодичность проверки готовности
        initialDelaySeconds: 5
# интервал между проверками
        periodSeconds: 10
  strategy:
# стратегия обновления приложения
    type: RollingUpdate
# параметры стратегии
    rollingUpdate:
# максимальное количество недоступных подов во время обновления
      maxUnavailable: 1
# максимальное количество дополнительных подов во время обновления
      maxSurge: 1
# дополнительные параметры для контроля прогресса обновления
# минимальное время в секундах, которое под должен быть готов перед тем как считать его успешно обновленным
  minReadySeconds: 10
# максимальное количество предыдущих ревизий, которые будут сохранены для отката
  revisionHistoryLimit: 5
# максимальное время в секундах, которое контроллер будет ждать для успешного обновления подов
  progressDeadlineSeconds: 600
# проверяем что новая версия приложения работает
kubectl exec -n deployment deployment-app-5d4b6f7c9b-abcde -- curl -s http://deployment-app:8000/
# помимо этого можно смотреть статус обновления
kubectl rollout status deployment/deployment-app -n deployment
# откат к предыдущей версии если что-то пошло не так
kubectl rollout undo deployment/deployment-app -n deployment
# смортрим историю ревизий
kubectl rollout history deployment/deployment-app -n deployment
# смотрим детали конкретной ревизии
kubectl rollout history deployment/deployment-app -n deployment --revision=2
# удаляем деплоймент
kubectl delete -f deployment.yml
# StatefulSet
# деплоим statefulset из файла statefulset.yml
kubectl apply -f statefulset.yml
# давайте посмотрим на statefulset
cat statefulset.yml

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: my-statefulset
  labels:
    app: my-app
spec:
  serviceName: "my-service"
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
# terminationGracePeriodSeconds задает время ожидания перед завершением пода
      terminateGracePeriodSeconds: 10
      containers:
      - name: my-container
        image: nginx:stable-alpine3.23
        ports:
        - containerPort: 80
        volumeMounts:
        - name: my-pvc
          mountPath: /usr/share/nginx/html
# volumeClaimTemplates для создания персистентных томов для каждого пода
# каждый под получит свой том, который будет сохранять данные при перезапуске пода и берется из storage class standard
# standard должен быть заранее создан в кластере
  volumeClaimTemplates:
  - metadata:
      name: my-pvc
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
      storageClassName: standard
# создадим standard storage class если его нет
kubectl apply -f storage-class.yml
cat storage-class.yml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
    name: standard
provisioner: kubernetes.io/aws-ebs
parameters:
    type: gp2
# проверяем что statefulset запустился
kubectl get pods -n deployment
# удаляем statefulset
kubectl delete -f statefulset.yml

# labels
# укажем лейблы на нодах
kubectl label nodes kubadm1 node-type=worker
kubectl label nodes master1 node-type=master
# проверим что лейблы установились
kubectl get nodes --show-labels
# отфильтруем ноды по лейблу
kubectl get nodes -l node-type=worker
# так же добавляем лейбл в манифесте деплоймента
# nodeSelector:
#   node-type: worker
# удаляем лейбл с ноды
kubectl label nodes kubadm1 node-type-
# аннотации
# добавим аннотацию к ноде
kubectl annotate node kubadm1 environment=production
# проверим что аннотация установилась
kubectl get node kubadm1 -o json | jq '.metadata.annotations'
# удалим аннотацию с ноды
kubectl annotate node kubadm1 environment-