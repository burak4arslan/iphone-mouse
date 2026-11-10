import Foundation

// iPhone Fare: telefon ev ağından Mac'e UDP paketi yollar, Mac'teki "iPhone Fare" uygulaması imleci oynatır.
// iOS, iPhone'un Bluetooth fare gibi görünmesine izin vermiyor (HID servisi yayınlanamıyor); o yüzden Mac'te alıcı var.
// Bu dosya hem iPhone uygulamasında hem Mac uygulamasında (Mac/build.sh) derlenir.
enum FareAg {
    static let servis = "_iphonefare._udp"
}

// Telefondan Mac'e. Konum, kaydırma ve vurma sayısı birikimli gider: arada kaybolan paket hareketi silmez,
// bir sonraki paket farkı kapatır. Düğmeler her pakette o anki hâliyle gider (kaybolan "bıraktım" takılı kalmaz).
struct FarePaketi: Codable {
    var oturum: UInt32      // telefon her başlatışta yenisini seçer; Mac birikimli değerleri sıfırdan alır
    var sira: UInt64        // artar; eskisi geç gelirse atılır
    var t: Double           // telefonun saati (sn), hız hesabı için
    var mod: String         // "kamera" (ters, kamera tavana bakar) | "sensor" (düz, ivme sensörü) | "touchpad"
    var durum: String       // kısa durum: izleme iyi mi, telefon kalktı mı
    var x: Double           // metre, birikimli; +x sağa
    var y: Double           // metre, birikimli; +y ileri (Mac'te yukarı)
    var sol: Bool
    var sag: Bool
    var kaydir: Double      // birikimli kaydırma (parmak noktası)
    var tik: UInt32         // birikimli sol tıklar: sırtına vurma ya da ses açma tuşu
    var sagTik: UInt32?     // birikimli sağ tıklar: ses kısma tuşu (eski sürümde yok)
    var vurmaTepe: Double   // son yarım saniyedeki en sert vuruş (g), eşiği ayarlamak için
    var nokta: Int          // kameranın tavanda gördüğü iz noktası
}

// Mac'ten telefona: bağlı olduğunu ve ayarları bildirir.
struct FareCevabi: Codable {
    var ad: String
    var acik: Bool          // Mac'te fare açık mı
    var izin: Bool          // Mac'te Erişilebilirlik izni var mı (yoksa tıklama olmaz)
    var vurmaEsigi: Double  // g
}
