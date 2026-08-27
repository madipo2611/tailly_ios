# Tailly iOS — статус и план продолжения

Обновлено: 2026-08-27. Репозиторий-каркас: `E:\devops\tailly_ios`.

## Цель

Нативное iOS-приложение социальной сети Tailly на Swift/SwiftUI: лента постов, клипы, истории, профиль, создание контента, уведомления и realtime-сообщения. Backend не меняется: публичный вход — GraphQL gateway в `tailly_back_v2`, который сам обращается к микросервисам.

## Что сделано

- Создан воспроизводимый XcodeGen-проект (`project.yml`), iOS 17+, bundle id `ru.tailly.ios`.
- Создано SwiftUI-приложение с тёмной Nebula-темой, повторяющей визуальное направление Android-клиента.
- Реализованы: безопасное хранение access/refresh JWT в Keychain, восстановление сессии, вход/регистрация, упреждающее обновление JWT (`refreshTokens`) и generic HTTP GraphQL client с Bearer header.
- Лента выполняет реальные GraphQL-запросы `postsPaginated` и `storyFeed`, содержит fullscreen viewer историй с автопрогрессом, фиксацией просмотра через `markStoriesSeen`, реакциями и текстовыми ответами; клипы — `clips`; профиль получает `me`, редактируется через `updateProfile` и поддерживает смену пароля.
- Реализован раздел «Интересное»: смешанная рекомендательная лента `exploreFeed`, фильтры фото/клипов, бесконечная пагинация и запись события просмотра в recommender через gateway.
- Transport: single-flight refresh-token для конкурентных запросов, повтор одного запроса после HTTP `401`/GraphQL `UNAUTHENTICATED`, а также `URLSession` GraphQL multipart upload (`performUpload`) для `Upload`.
- В ленте: реальные like/unlike с optimistic update, pagination, просмотр комментариев, их отправка и ответы на комментарии; действия like/comment отправляются в recommender.
- Добавлен задел WebSocket-клиента, GitHub Actions с macOS runner и URLProtocol unit-тесты GraphQL transport (успешный ответ, offline-состояние, multipart Upload и `UNAUTHENTICATED` refresh/retry).

## Важный API-контракт

Источник истины: `tailly_back_v2/internal/http/graph/schema.graphql`.

| Назначение | Endpoint / операция | Статус iOS |
| --- | --- | --- |
| HTTP GraphQL | `https://tailly.ru/query` | подключён |
| Авторизация | `login`, `register`, `refreshTokens`, `me`, `updateProfile`, `changePassword` | подключены; single-flight refresh и retry подключены |
| Посты | `postsPaginated`, `createPost`, comments, likes | pagination, optimistic likes, комментарии и ответы подключены; фото-пост создаётся через multipart Upload |
| Истории | `storyFeed`, `userStories`, create/seen/reactions/replies | лента, fullscreen viewer, mark seen, реакции и текстовые ответы подключены |
| Клипы | `clips`, comments, likes, `createClip` | чтение, likes, комментарии и базовая загрузка видео подключены |
| Интересное | `exploreFeed`, `recordExploreInteraction` | подключён базовый список/filters/view event |
| Диалоги | `getUserChats`, `getChatMessages`, send/status | контракт описан, UI не подключён |
| WS GraphQL | `wss://tailly.ru/ws`, `messageStream(userId:)` | задел есть, нужна protocol-проверка |

Android использует Apollo и URL `wss://tailly.ru/ws?token=<JWT>`. Web-клиент использует `subscriptions-transport-ws`; Go gateway (`gqlgen`) не фиксирует явно subprotocol. До включения realtime в iOS надо снять handshake в staging и выбрать совместимый протокол: `graphql-ws` либо `graphql-transport-ws`. Не отправлять сообщения по самодельному протоколу.

## Архитектура

```
SwiftUI feature views
        ↓
GraphQLClient / GraphQLSubscriptionClient
        ↓ HTTPS / WSS
tailly_back_v2 GraphQL gateway
        ↓ gRPC
stories · clips · messages · subscribers · recommender
```

Принципы: UI отделён по `Features`, DTO пока совпадают с GraphQL-полями, токены только в Keychain, сетевые URL в `AppConfiguration`. Внешние UI-компоненты сознательно не добавлены: базовый дизайн системный и не создаёт цепочку зависимостей для CI.

## План работ

1. **Стабилизировать transport:** single-flight refresh, `UNAUTHENTICATED` retry, multipart Upload, понятные offline/server error-сообщения и XCTest URLProtocol-моки готовы; добавить тест конкурентного refresh.
2. **Завершить auth/profile:** редактирование профиля, logout, регистрация и `me` подключены; далее подписки, Keychain migration и тесты.
3. **Лента и «Интересное»:** post pagination, optimistic likes, комментарии и ответы готовы; далее просмотр поста/клипа, image caching, accessibility и события like/comment/skip в recommender.
4. **Истории:** viewer с автопрогрессом, mark seen, реакции и текстовые ответы готовы; далее камера/медиапикер, upload, архив/highlights.
5. **Клипы:** базовая загрузка видео, comments и likes готовы; далее AVPlayer, автозапуск/prefetch и обработка ошибок HLS/preview.
6. **Сообщения:** подтвердить WS протокол на staging, chats/messages/send/status, lifecycle reconnect/backoff, deduplication и background notifications.
7. **Качество/release:** XCTest network mocks, UI tests, GraphQL schema/code generation (Apollo iOS или custom), CI signing secrets, TestFlight workflow, privacy manifest, push (APNs).

## Как продолжить в новом диалоге

1. Открыть этот файл и `README.md`.
2. Не сканировать `tailly_android/**/build`, `tailly_android/.gradle`, `tailly_front_v2/node_modules`, `dist` и другие generated/cache каталоги.
3. Сверять каждую операцию с `tailly_back_v2/internal/http/graph/schema.graphql` и Android `.graphql` файлами; менять backend только по отдельному запросу.
4. Ближайшая рекомендуемая задача: реализовать refresh и проверить WebSocket subprotocol против staging — это разблокирует безопасный realtime-слой.

## CI и подпись

Workflow `.github/workflows/ios.yml` генерирует `.xcodeproj` из `project.yml` и запускает `xcodebuild test` на macOS. Для архива/TestFlight потребуется Apple Developer account, Team ID, certificate/profile или App Store Connect API key. Их нужно добавить в GitHub Secrets; никаких ключей в репозиторий.
