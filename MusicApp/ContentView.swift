import NavidromeCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text(ClientIdentity().name)
            .padding()
    }
}

#Preview {
    ContentView()
}
