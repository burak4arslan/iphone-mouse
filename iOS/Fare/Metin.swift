import Foundation

// Arayüz dili: Türkçe ya da İngilizce. Ayarlardan seçilir; "Sistem" telefonun/Mac'in diline uyar
// (Türkçe değilse İngilizce). Bu dosya hem iPhone hem Mac uygulamasında derlenir (Mac/build.sh).
// Paketteki mod ve durum her zaman Türkçe anahtar olarak gider (Mac'teki CSV kaydı değişmesin);
// ekranda gösterirken burada çevrilir.
enum Dil: String, CaseIterable, Identifiable {
    case sistem, tr, en
    var id: String { rawValue }

    /// Seçenek adı, her dilde aynı görünür ki yanlış dili seçen geri dönebilsin.
    var ad: String {
        switch self {
        case .sistem: return Metin.ingilizce(Dil.sistem.rawValue) ? "System" : "Sistem"
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }
}

enum Metin {
    /// UserDefaults / @AppStorage anahtarı
    static let anahtar = "dil"

    /// `secim`: @AppStorage'daki ham değer ("sistem", "tr", "en" ya da boş).
    static func ingilizce(_ secim: String) -> Bool {
        switch Dil(rawValue: secim) ?? .sistem {
        case .tr: return false
        case .en: return true
        case .sistem: return !(Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("tr")
        }
    }

    /// Kayıtlı seçime göre (görünüm dışı yerler için: pencere adı gibi).
    static var ingilizce: Bool { ingilizce(UserDefaults.standard.string(forKey: anahtar) ?? "") }

    static let uygulamaAdi = (tr: "iPhone Fare", en: "iPhone Mouse")

    /// Paketteki mod anahtarı → ekrandaki ad
    static func mod(_ anahtar: String, en: Bool) -> String {
        switch anahtar {
        case "kamera": return en ? "Face-down (camera)" : "Ters (kamera)"
        case "sensor": return en ? "Face-up (sensor)" : "Düz (sensör)"
        case "sensor-ters": return en ? "Face-down (sensor)" : "Ters (sensör)"
        case "touchpad": return "Touchpad"
        default: return anahtar
        }
    }

    /// Telefonun Türkçe durum metni → seçili dil. Bilinmeyen metin olduğu gibi kalır.
    static func durum(_ metin: String, en: Bool) -> String {
        guard en else { return metin }
        let sozluk = [
            "başlıyor": "starting",
            "bu telefonda ARKit yok": "no ARKit on this phone",
            "izleme iyi": "tracking good",
            "izleme yok": "no tracking",
            "yerini arıyor": "relocalizing",
            "tavanda iz az": "few ceiling features",
            "çok hızlı": "too fast",
            "izleme sınırlı": "tracking limited",
            "telefonu ters çevir": "turn the phone face-down",
            "telefonu düz koy": "lay the phone flat",
            "havada": "lifted",
            "hareket": "moving",
            "duruyor": "still",
            "sürüklüyor": "dragging",
            "hazır": "ready",
        ]
        if let ceviri = sozluk[metin] { return ceviri }
        if metin.hasPrefix("hata: ") { return "error: " + metin.dropFirst(6) }
        if metin.hasPrefix("bekliyor: ") { return "waiting: " + metin.dropFirst(10) }
        return metin
    }
}
