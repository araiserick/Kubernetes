## Запустить deployment 

```
kubectl apply -f deployment.yml
```

При обновлении приложения  если что-то пошло не так, то мы можем вернуться к исхожному состоянию

```
kubectl rollout undo deployment my-deployment
```
так же можем посмотреть историю deployment 

```
kubectl rollout history deployment my-deployment
```