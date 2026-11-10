import SwiftUI

// Ayarlar: arayüz dili ve uygulama hakkında. Dil anında değişir (bütün ekranlar @AppStorage("dil") okur).
struct AyarlarEkrani: View {
    @AppStorage(Metin.anahtar) private var dil = ""
    private var en: Bool { Metin.ingilizce(dil) }

    private var surum: String {
        let bilgi = Bundle.main.infoDictionary
        let kisa = bilgi?["CFBundleShortVersionString"] as? String ?? "?"
        let derleme = bilgi?["CFBundleVersion"] as? String ?? "?"
        return "\(kisa) (\(derleme))"
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { Dil(rawValue: dil) ?? .sistem }, set: { dil = $0.rawValue })) {
                    ForEach(Dil.allCases) { Text($0.ad).tag($0) }
                } label: {
                    Label(en ? "Language" : "Dil", systemImage: "globe")
                }
            } footer: {
                Text(en ? "The Mac app has its own language setting in its window."
                        : "Mac uygulamasının dili kendi penceresinden seçilir.")
            }

            Section(en ? "About" : "Hakkında") {
                LabeledContent(en ? "Version" : "Sürüm", value: surum)
                if let url = URL(string: "https://github.com/Burak4Arslan/iphone-mouse") {
                    Link(destination: url) {
                        Label(en ? "Source code on GitHub" : "Kaynak kodu GitHub'da", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
        }
        .navigationTitle(en ? "Settings" : "Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
