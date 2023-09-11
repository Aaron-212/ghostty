import SwiftUI

struct ConfigurationErrorsView: View {
    class Model: ObservableObject {
        @Published var errors: [String] = []
    }
    
    @ObservedObject var model: Model
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 52))
                    .padding()
                    .frame(alignment: .center)
                
                Text("""
                    ^[\(model.errors.count) error(s) were](inflect: true) found while loading the configuration. \
                    Please review the errors below and reload your configuration.
                    """)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(model.errors, id: \.self) { error in
                            Text(error)
                                .lineLimit(nil)
                                .font(.system(size: 12).monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        
                        Spacer()
                    }
                    .padding(.all)
                    .frame(minHeight: geo.size.height)
                    .background(Color.white)
                }
            }
        }
        .frame(minWidth: 480, maxWidth: 960, minHeight: 270)
    }
}
