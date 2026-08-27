import SwiftUI

struct MessagesView: View { var body: some View { NavigationStack { TaillyScreen { ContentUnavailableView("Сообщения", systemImage: "paperplane", description: Text("Каркас WebSocket-клиента готов. После проверки совместимого WS-протокола будут подключены список диалогов и live-обновления.")) }.navigationTitle("Сообщения") } } }
