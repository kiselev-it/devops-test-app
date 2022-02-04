# Приложение для загрузки и получения картинки

## Функциональность

Загрузка картинки

```sh
curl -F 'image=@/path/to/image.png' my-app.com/upload
```

Получение картинки

```sh
curl http://my-app.com/image -o image.jpg
```

При загрузки следующей картинки предыдущая удаляется

## Требования

- Zero-downtime deployment
- 100% uptime
- Возможность делать несколько релизов для разных веток в один неймспейс (для тестирования)

## Деплой

Сборка

```sh
make build BRANCH=master
```

Деплой helm чарта (используется helm 3)

```sh
make deploy HELM=helm
```


---
# Ошибки  
## 1. Сборка
Неправильная команда сборки. Правильно: `make build-app BRANCH=master`, т.к. правильная команда сборки прописана в makefile.
 
## 2. ingress

Ошибка в `serviceName:my-app`. Необходимо исправить на {{ .Release.Name }}, т.к. в service.yaml указано данное имя.

В текущей версии k&s 1.23 не будет поддерживаться Все бета-версии API Ingress, поэтому нужно заменить `apiVersion: networking.k8s.io/v1beta1` на `apiVersion: networking.k8s.io/v1`.
Также в данной версии pathType больше не имеет значения по умолчанию. Необходимо указать одно из значений: "Exact", "Prefix", или "ImplementationSpecific.

## 3. deploymet
Ошибка в указании claimName. Правильно: `{{ .Release.Name }}`.

Не заданы доступы к приватному docker regestry. Необходимо указать секрет (Перед этим секрет еще необходимо создать ):
```
imagePullSecrets:
- name: private-registry
```
В идеале, лучше использовать внешние хранилище секретов. Например Vault. 

# Улучшения:
## Dockerfile
Можно использовать multi-stage сборку образа, что позволит в разы уменьшить размер конечного образа.

```
FROM golang:1.14 as builder
WORKDIR /app
COPY . .
RUN go build -o app
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/app /app/app
CMD ["/app/app"]
```
Базовый образ apline весит гораздо меньше, чем базовый образ golang:1.14. Поэтому из golang:1.14 передается лишь только исполняемый файл. За счет чего достигается следующий результат:

![alt text](/pmg/1.PNG?raw=true)


 ```
FROM golang:1.14 as builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o app .
FROM scratch
WORKDIR /app
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/app /app/app
CMD ["/app/app"]
 ```
Можно еще уменьшить размер образа, использовав пустой образ - scratch, что даст результат в 7.95 mb.
Необходимо изменить команду сборки, добавив дополнительные флаги. А также пробросить сертификат, т.к. scratch пуст. Но могут возникнуть проблемы с сертификатом.

Также можно добавить флаги `RUN CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build -ldflags "-s -w -extldflags '-static'" -o ./app`. Сократит образ еще на пару mb.

![alt text](/pmg/2.PNG?raw=true)


Также в данном варианте, при go build каждый раз будут загружаться  зависимости. И если б их было много, то сильно замедлило процесс сборки образа. 
Чтобы исправить это, можно использовать кэширование модулей.
Это можно сделать, сначала скопировав файлы go.mod и go.sum и запустив go mod download, затем скопировав все остальные файлы и запустив go build.

 ```
FROM golang:1.14 as builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o app .
FROM scratch
WORKDIR /app
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/app /app/app
CMD ["/app/app"]
 ```

## PVC

Чтобы Админу/разработчику не создавать PV руками, можно использовать провижинер (например nfs), чтобы PV создавались автоматически. Также PV будут создан с нужными режимом и с точным запрашиваемым размером. Но для начало необходимо установить provisioner. Соответственно необходимо будет указать storageClassName:


Также необходимо заменить режим доступа к тому с ReadWriteOnce на ReadWriteMany.
Т.к. с исходным режимом доступа к тому, том может быть примонтирован в режиме чтения и записи только к одной ноде.( Может использоваться несколькими подами, если они находятся на одной ноде)

```
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: {{ .Release.Name }}
spec:
  storageClassName: "nfs"
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi

```

## Zero-downtime deployment и 100% uptime
Для соблюдения требования Zero-downtime deployment и 100% uptime необходимо увеличить количество реплик и настроить Rolling Updates.

Т.е. при такой стратегии обновления будет всегда доступно три реплики приложения, а новая версия будет добавляться постепенно, по одному экземпляру.
```
replicas: {{ .Values.replicaCount }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```
Также необходимо добавить livenessProbe/readinessProbe (жти пробы реализованы в коде). livenessProbe проверят живой контейнер или нет, отправляя запрос HTTP GET каждые 10 секунды (initialDelaySeconds - ждать 5 секунды перед проведением первой пробы) и если возвращеатся код успеха, то значит контейнер жив. Если проба не прошла, то контейнер будет перезапущен.
А readinessProbe же будет проверять, может ли приложение обслуживать трафик. Если не может, то контейнер не будет перезапущен, как в случае с livenessProbe), а перестанет отправлять клиентские запросы.
```
livenessProbe:
  httpGet:
    path: /healthz/liveness
    port: {{ .Values.AppPort }}
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /healthz/readiness
    port: {{ .Values.AppPort }}
  initialDelaySeconds: 5
  periodSeconds: 10
```
Также необходимо указать запросы и лимиты, чтобы не случилось такой ситуации, когда поду понадобится больше ресурсов, а на ноде свободных нет.

resources:
   limits:
     cpu: 200m
     memory: 256Mi
   requests:
     cpu: 100m
     memory: 128Mi

# Vaules
Лучше задать больше значений через переменные и также добавить больше lables. Соответственно таким образом исправлено часть ошибок.
