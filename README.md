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
