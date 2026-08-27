# Tailly iOS

SwiftUI-каркас нативного клиента Tailly. Проект намеренно не содержит сторонних SDK: он собирается из XcodeGen и Swift Package Manager не требуется.

## Локальный запуск (macOS)

1. Установить [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. В этой папке выполнить `xcodegen generate`.
3. Открыть `Tailly.xcodeproj` в Xcode и запустить схему `Tailly`.

Приложение по умолчанию подключается к production API `tailly.ru`. Для локального сервера смените URL в `Tailly/App/AppConfiguration.swift`; не коммитьте токены и ключи.

Полное состояние работ, контракт API, известные ограничения и последовательность продолжения: [docs/STATUS.md](docs/STATUS.md). Вкладка «Интересное» использует backend-рекомендации `exploreFeed`, поэтому не зависит от того, реализован ли этот сценарий на Android.
