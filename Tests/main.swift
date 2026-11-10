import Foundation
import simd

// FareIzleyici.swift'i sahte verilerle dener (telefon gerekmez). Gerçek sensörün yerini tutmaz, sadece hesap hatası arar.
// Çalıştırma (depo kökünden): swiftc -O -o /tmp/fare-deneme Tests/main.swift iOS/Fare/FareIzleyici.swift && /tmp/fare-deneme

var rng = SystemRandomNumberGenerator()
func gauss(_ s: Double) -> Double {
    let u1 = Double.random(in: 1e-9..<1, using: &rng), u2 = Double.random(in: 0..<1, using: &rng)
    return s * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
}
var hata = 0
func kontrol(_ ad: String, _ ok: Bool, _ ayrinti: String) {
    print("\(ok ? "✓" : "✗") \(ad): \(ayrinti)")
    if !ok { hata += 1 }
}

// Minimum sarsıntılı itiş: süre T'de mesafe D. İvme profili.
func itisIvmesi(_ t: Double, D: Double, T: Double) -> Double {
    guard t >= 0, t <= T else { return 0 }
    let s = t / T
    return D / (T * T) * (60 * s - 180 * s * s + 120 * s * s * s)
}

// MARK: Düz mod (ivme sensörü)
// Ölçüm gürültüsü (σ, m/s²), sabit sensör hatası ve kayarken masanın verdiği titreşim (σ). Titreşimin gerçekte ne kadar
// olduğu bilinmiyor (masa, mouse pad); iki hâli de deniyoruz.
func sensorYolu(_ ivme: (Double) -> Double, sure: Double, gurultu: Double, titresim: Double,
                sapma: SIMD2<Double> = [0.02, -0.015]) -> (SIMD2<Double>, Double, Double) {
    var iz = SensorIzleyici()
    let dt = 0.01
    var t = -0.5, v = 0.0, gercek = 0.0
    var enIleri = 0.0, enGeri = 0.0
    var yon = 0.0
    while t < sure + 0.6 {
        let a = ivme(t)
        v += a * dt
        gercek += v * dt
        let kayiyor = abs(v) > 0.003
        let olculen = SIMD2(a, 0) + sapma + SIMD2(gauss(gurultu), gauss(gurultu))
            + (kayiyor ? SIMD2(gauss(titresim), gauss(titresim)) : .zero)
        iz.ekle(ivme: olculen, donus: abs(gauss(0.01)) + (kayiyor ? 0.03 : 0), dt: dt)
        if yon == 0 && abs(gercek) > 0.001 { yon = gercek > 0 ? 1 : -1 }
        let ilerleme = iz.konum.x * (yon == 0 ? 1 : yon)
        enIleri = max(enIleri, ilerleme)
        enGeri = min(enGeri, ilerleme - enIleri)
        t += dt
    }
    return (iz.konum, gercek, enGeri)
}

func sensorDene(ad: String, D: Double, T: Double, gurultu: Double, titresim: Double) {
    var oranlar: [Double] = [], geriler: [Double] = [], yanlar: [Double] = []
    for _ in 0..<20 {
        let (son, gercek, geri) = sensorYolu({ itisIvmesi($0, D: D, T: T) }, sure: T, gurultu: gurultu, titresim: titresim)
        oranlar.append(son.x / gercek)
        geriler.append(geri / abs(gercek))
        yanlar.append(abs(son.y) / abs(gercek))
    }
    oranlar.sort()
    let kotuGeri = geriler.min()!
    let ok = oranlar[2] > 0.6 && oranlar[17] < 1.5 && kotuGeri > -0.15 && yanlar.max()! < 0.3
    kontrol(ad, ok, String(format: "20 denemede ölçülen/gerçek %%%.0f–%%%.0f (orta %%%.0f), en çok geri kaçış %%%.0f, en çok yana kayma %%%.0f",
                           oranlar[2] * 100, oranlar[17] * 100, oranlar[10] * 100, kotuGeri * 100, yanlar.max()! * 100))
}

for (adi, g, ti) in [("titreşimli masa", 0.02, 0.06), ("sessiz yüzey", 0.02, 0.0), ("gürültülü sensör", 0.04, 0.06)] {
    print("— Düz mod, \(adi) (gürültü \(g), titreşim \(ti) m/s²)")
    do {
        var iz = SensorIzleyici()
        for _ in 0..<300 {
            iz.ekle(ivme: SIMD2(0.02 + gauss(g), -0.015 + gauss(g)), donus: abs(gauss(0.01)), dt: 0.01)
        }
        kontrol("  dururken kaymıyor", simd_length(iz.konum) < 0.001, String(format: "3 sn'de %.2f mm", simd_length(iz.konum) * 1000))
    }
    sensorDene(ad: "  hızlı itiş 5 cm / 0,3 sn", D: 0.05, T: 0.3, gurultu: g, titresim: ti)
    sensorDene(ad: "  normal itiş 10 cm / 0,5 sn", D: 0.10, T: 0.5, gurultu: g, titresim: ti)
    sensorDene(ad: "  geri itiş -6 cm / 0,4 sn", D: -0.06, T: 0.4, gurultu: g, titresim: ti)
    // Bilinen zayıf yer: yavaş, ince hareket (gürültü uzun süre birikir). Sınama değil, bilgi.
    do {
        var oranlar: [Double] = [], yanlar: [Double] = []
        for _ in 0..<20 {
            let (son, gercek, _) = sensorYolu({ itisIvmesi($0, D: 0.02, T: 1.0) }, sure: 1.0, gurultu: g, titresim: ti)
            oranlar.append(son.x / gercek); yanlar.append(abs(son.y) * 1000)
        }
        oranlar.sort()
        print(String(format: "  · yavaş itiş 2 cm / 1 sn → %%%.0f–%%%.0f, yana en çok %.0f mm (sensörün zayıf yeri)",
                     oranlar[2] * 100, oranlar[17] * 100, yanlar.max()!))
    }
    // Sabit hızla uzun kayış: 0,2 m/s'ye çık, 0,5 sn süzül, dur (12 cm)
    let suzul: (Double) -> Double = { t in t >= 0 && t < 0.1 ? 2.0 : (t >= 0.6 && t < 0.7 ? -2.0 : 0) }
    var olculen: [Double] = []
    for _ in 0..<20 { olculen.append(sensorYolu(suzul, sure: 0.7, gurultu: g, titresim: ti).0.x * 1000) }
    olculen.sort()
    print(String(format: "  · sabit hızla süzülme 120 mm → ölçülen %.0f–%.0f mm (orta %.0f)", olculen[2], olculen[17], olculen[10]))
}

// MARK: Düz mod: telefonda görülen kaçma (8 Kasım, kayıt: 3 sn'de 3,3 m)
// İki olası neden: koyarken elin hareketi "sabit hata" diye öğrenildi; ya da kamera çıkıntısı yüzünden eğik/sallanan telefonda
// yerçekimi yatay ivmeye sızıyor. İkisinde de dururken sabit bir ivme görülür; imleç kaçmamalı.
do {
    print("— Düz mod: yanlış öğrenilmiş hata ve eğim")
    func calistir(_ ivme: (Double) -> SIMD2<Double>, _ donus: (Double) -> Double = { _ in 0.005 }, sure: Double) -> SensorIzleyici {
        var iz = SensorIzleyici()
        var t = 0.0
        while t < sure {
            iz.ekle(ivme: ivme(t) + SIMD2(gauss(0.02), gauss(0.02)), donus: donus(t), dt: 0.01)
            t += 0.01
        }
        return iz
    }
    // Koyarken ilk 0,4 sn elin hareketi (0,8 m/s² civarı), sonra telefon masada duruyor
    let koyma = calistir({ t in t < 0.4 ? SIMD2(0.8 + 0.5 * sin(t * 30), -0.3) : .zero }, { t in t < 0.4 ? 0.6 : 0.005 }, sure: 4)
    kontrol("koyarken elin hareketi hata diye öğrenilip imleci kaçırmıyor", simd_length(koyma.konum) < 0.01,
            String(format: "4 sn'de %.0f mm", simd_length(koyma.konum) * 1000))
    // Dururken eğim değişti: yerçekiminden 0,08 g sızıntı birden geliyor (1. sn'de), sonra hep var
    let egim = calistir({ t in t < 1 ? .zero : SIMD2(0.78, 0) }, { t in t > 1 && t < 1.1 ? 0.7 : 0.005 }, sure: 5)
    kontrol("dururken eğim değişince imleç kaçmıyor (en çok 4 cm, sonra durur)", simd_length(egim.konum) < 0.04 && !egim.hareketli,
            String(format: "5 sn'de %.0f mm, hareket %@", simd_length(egim.konum) * 1000, egim.hareketli ? "sürüyor" : "bitti"))
    // Sızıntı varken normal itiş: 10 cm / 0,5 sn, itiş başında eğim değişiyor (0,08 g kalıcı)
    let itis = calistir({ t in
        let s = t - 1.0
        let ana = (s >= 0 && s <= 0.5) ? (0.1 / 0.25) * (60 * (s / 0.5) - 180 * pow(s / 0.5, 2) + 120 * pow(s / 0.5, 3)) : 0
        return SIMD2(ana + (t > 1.0 ? 0.78 : 0), 0)
    }, { t in t > 1 && t < 1.1 ? 0.7 : 0.02 }, sure: 4)
    kontrol("eğim değişen itişte bile imleç sonra durur (10 cm itiş; fazlası olur ama en çok 40 cm)", itis.konum.x > 0.03 && itis.konum.x < 0.40 && !itis.hareketli,
            String(format: "%.0f mm, hareket %@", itis.konum.x * 1000, itis.hareketli ? "sürüyor" : "bitti"))
}

// MARK: Ters mod (kamera)
// ARKit kamera ekseni (belgeden): x telefonun üst kenarından alt kenarına, y portrede sağa, z ekrandan dışarı.
// Dünya: x doğu, y yukarı, z güney (ARKit gibi). Telefon ters (ekran aşağı), üst kenar kuzeye.
let dogu = SIMD3<Double>(1, 0, 0), yukari = SIMD3<Double>(0, 1, 0), kuzey = SIMD3<Double>(0, 0, -1)
let cihazY = kuzey                         // üst kenar ileri
let cihazZ = -yukari                       // ekran masaya bakıyor
let cihazX = simd_cross(cihazY, cihazZ)    // sağ el kuralı
let kx = -cihazY, ky = cihazX              // kamera ekseni
let sagEksen = -ky, ileriEksen = -kx       // FareController.kare() ile aynı
kontrol("Ters: eksen eşlemesi", simd_dot(sagEksen, dogu) > 0.99 && simd_dot(ileriEksen, kuzey) > 0.99,
        "doğuya itince sağ \(simd_dot(sagEksen, dogu)), kuzeye itince ileri \(simd_dot(ileriEksen, kuzey))")

func kameraYolu(_ yollar: [(SIMD3<Double>, Double)], titreme: Double = 0.00005) -> KameraIzleyici {
    var iz = KameraIzleyici()
    var p = SIMD3<Double>(0.3, -0.1, 0.2)
    for (hedef, sure) in yollar {
        let bas = p
        let adim = Int(sure * 60)
        for i in 1...max(adim, 1) {
            let s = Double(i) / Double(max(adim, 1))
            let k = s * s * (3 - 2 * s)
            p = bas + (hedef) * k
            let olculen = p + SIMD3(gauss(titreme), gauss(titreme), gauss(titreme))
            iz.ekle(konum: olculen, sag: sagEksen, ileri: ileriEksen, gecerli: true, sakin: simd_length(hedef) == 0)
        }
        p = bas + hedef
    }
    return iz
}
do {
    let iz = kameraYolu([(.zero, 3)])
    kontrol("Ters: dururken titreme imlece geçmiyor", simd_length(iz.cikis) < 0.0002,
            String(format: "3 sn'de %.3f mm", simd_length(iz.cikis) * 1000))
}
do {
    let iz = kameraYolu([(.zero, 0.5), (dogu * 0.03, 0.4), (.zero, 0.5), (kuzey * 0.02, 0.3), (.zero, 0.5)])
    kontrol("Ters: 3 cm sağa, 2 cm ileri", abs(iz.cikis.x - 0.03) < 0.001 && abs(iz.cikis.y - 0.02) < 0.001,
            String(format: "x %.2f mm, y %.2f mm", iz.cikis.x * 1000, iz.cikis.y * 1000))
}
do {
    // 2 cm sağa, kaldır (2 cm yukarı), havada 5 cm sola, indir, 1 cm sağa
    let iz = kameraYolu([(.zero, 0.5), (dogu * 0.02, 0.3), (.zero, 0.3), (yukari * 0.02, 0.2), (dogu * -0.05, 0.4),
                         (yukari * -0.02, 0.2), (.zero, 0.3), (dogu * 0.01, 0.3), (.zero, 0.3)])
    kontrol("Ters: kaldırınca sayılmıyor", abs(iz.cikis.x - 0.03) < 0.003,
            String(format: "beklenen yaklaşık 30 mm, ölçülen %.2f mm", iz.cikis.x * 1000))
}

do {
    // Telefonda görülen hata: masada dururken ARKit yüksekliği kayınca "havada" sanılıyordu
    func ornekle(_ adimlar: [(SIMD3<Double>, Bool)]) -> KameraIzleyici {
        var iz = KameraIzleyici()
        for (p, sakin) in adimlar { iz.ekle(konum: p + SIMD3(gauss(0.00005), gauss(0.00005), gauss(0.00005)), sag: sagEksen, ileri: ileriEksen, gecerli: true, sakin: sakin) }
        return iz
    }
    var a: [(SIMD3<Double>, Bool)] = []
    for i in 0..<180 { a.append((yukari * (0.025 * Double(i) / 180), true)) }            // 3 sn'de 2,5 cm yukarı kayma, telefon duruyor
    for i in 1...30 { a.append((yukari * 0.025 + dogu * (0.03 * Double(i) / 30), false)) } // sonra 3 cm sağa
    for _ in 0..<30 { a.append((yukari * 0.025 + dogu * 0.03, true)) }
    var iz = ornekle(a)
    kontrol("Ters: masada yükseklik kayınca havada sanılmıyor", !iz.havada && abs(iz.cikis.x - 0.03) < 0.002,
            String(format: "havada %@, sağa %.1f mm (beklenen 30)", iz.havada ? "evet" : "hayır", iz.cikis.x * 1000))
    a = []
    for _ in 0..<60 { a.append((.zero, true)) }
    for _ in 0..<60 { a.append((yukari * 0.02, true)) }                                     // birden 2 cm zıplama, telefon duruyor
    iz = ornekle(a)
    kontrol("Ters: ARKit birden zıplayınca havada sanılmıyor", !iz.havada, iz.havada ? "havada" : "masada")
    a = []
    for _ in 0..<30 { a.append((.zero, true)) }
    for i in 1...30 { a.append((dogu * (0.04 * Double(i) / 30) + yukari * (0.01 * Double(i) / 30), false)) }   // kayarken 1 cm kayma
    iz = ornekle(a)
    kontrol("Ters: kayarken 1 cm yükseklik kayması havada sayılmıyor", !iz.havada && abs(iz.cikis.x - 0.04) < 0.002,
            String(format: "sağa %.1f mm (beklenen 40)", iz.cikis.x * 1000))
}

// MARK: Vurma (ters modda tık)
do {
    var v = VurmaAlgilayici()
    var tik = 0
    for i in 0..<200 {   // 2 sn, 0,5 ve 1,2. sn'de birer vuruş
        var z = gauss(0.01)
        if i == 50 || i == 120 { z += 0.3 }
        if i == 51 || i == 121 { z -= 0.15 }
        if v.ekle(z: z, yatay: abs(gauss(0.01)), dt: 0.01) { tik += 1 }
    }
    kontrol("Vurma: iki vuruş iki tık", tik == 2, "\(tik) tık")
}
do {
    var v = VurmaAlgilayici()
    var tik = 0
    for i in 0..<200 {   // masada itip durdurmak: yatay ivme büyük, z küçük
        let t = Double(i) * 0.01
        let yatay = abs(itisIvmesi(t - 0.3, D: 0.08, T: 0.3)) / 9.81
        if v.ekle(z: gauss(0.015) + yatay * 0.1, yatay: yatay + abs(gauss(0.01)), dt: 0.01) { tik += 1 }
    }
    kontrol("Vurma: kaydırmak tık sayılmıyor", tik == 0, "\(tik) tık")
}


// MARK: Touchpad
// Parmak olayları sırayla verilir, çıkan tık/sürükleme olayları ve imleç yolu kontrol edilir.
func dokunuslar(_ adimlar: [(Double, String, Int, SIMD2<Double>)]) -> (TouchpadIzleyici, [TouchpadIzleyici.Olay]) {
    var tp = TouchpadIzleyici()
    var olaylar: [TouchpadIzleyici.Olay] = []
    var t = 0.0
    for (zaman, tur, id, konum) in adimlar.enumerated().sorted(by: { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }).map(\.element) {
        while t < zaman { t += 0.01; olaylar += tp.zaman(t) }   // telefondaki zamanlayıcı yerine
        switch tur {
        case "b": olaylar += tp.basla(id: id, konum: konum, t: zaman)
        case "k": olaylar += tp.kay(id: id, konum: konum, t: zaman)
        default: olaylar += tp.bitti(id: id, t: zaman)
        }
    }
    for _ in 0..<100 { t += 0.01; olaylar += tp.zaman(t) }
    return (tp, olaylar)
}
func kaydirma(_ id: Int, _ t0: Double, _ a: SIMD2<Double>, _ b: SIMD2<Double>, adim: Int = 20, sure: Double = 0.3) -> [(Double, String, Int, SIMD2<Double>)] {
    var r: [(Double, String, Int, SIMD2<Double>)] = [(t0, "b", id, a)]
    for i in 1...adim { let s = Double(i) / Double(adim); r.append((t0 + sure * s, "k", id, a + (b - a) * s)) }
    r.append((t0 + sure + 0.01, "e", id, b))
    return r
}
do {
    print("— Touchpad")
    let tek = dokunuslar([(0.1, "b", 1, [100, 300]), (0.18, "e", 1, [100, 300])])
    kontrol("dokun = sol tık", tek.1 == [.tik], "\(tek.1)")
    let cift = dokunuslar([(0.1, "b", 1, [100, 300]), (0.18, "e", 1, [100, 300]), (0.3, "b", 1, [102, 301]), (0.38, "e", 1, [102, 301])])
    kontrol("iki kere dokun = çift tık", cift.1 == [.ciftTik], "\(cift.1)")
    let ayri = dokunuslar([(0.1, "b", 1, [100, 300]), (0.18, "e", 1, [100, 300]), (0.9, "b", 1, [100, 300]), (0.98, "e", 1, [100, 300])])
    kontrol("arayla iki dokunuş = iki ayrı tık", ayri.1 == [.tik, .tik], "\(ayri.1)")
    let sag = dokunuslar([(0.1, "b", 1, [100, 300]), (0.12, "b", 2, [160, 300]), (0.2, "e", 1, [100, 300]), (0.21, "e", 2, [160, 300])])
    kontrol("iki parmakla dokun = sağ tık", sag.1 == [.sagTik], "\(sag.1)")
    let yol = dokunuslar(kaydirma(1, 0.1, [100, 300], [220, 240]))
    kontrol("tek parmak kaydır = imleç, tık yok", yol.1.isEmpty && simd_length(yol.0.hareket - [120, 60]) < 0.01,
            "olay \(yol.1), yol \(yol.0.hareket) (beklenen sağa 120, yukarı 60)")
    let iki = dokunuslar(kaydirma(1, 0.1, [100, 300], [100, 400]) + kaydirma(2, 0.105, [160, 300], [160, 400]))
    kontrol("iki parmak kaydır = sayfa kaydırma, imleç durur", iki.1.isEmpty && abs(iki.0.kaydirma - 100) < 0.01 && iki.0.hareket == .zero,
            "olay \(iki.1), kaydırma \(iki.0.kaydirma), imleç \(iki.0.hareket)")
    var adimlar: [(Double, String, Int, SIMD2<Double>)] = [(0.1, "b", 1, [100, 300]), (0.17, "e", 1, [100, 300])]
    adimlar += kaydirma(1, 0.27, [100, 300], [300, 300], sure: 0.5)
    let sur = dokunuslar(adimlar)
    kontrol("dokun + hemen sürükle = basılı taşı, çift tık yok", sur.1 == [.surukleBasla, .surukleBitir] && abs(sur.0.hareket.x - 200) < 0.01,
            "olay \(sur.1), yol \(sur.0.hareket.x)")
    let uzun = dokunuslar([(0.1, "b", 1, [100, 300]), (0.8, "e", 1, [100, 300])])
    kontrol("uzun basıp kaldırmak tık değil", uzun.1.isEmpty, "\(uzun.1)")
    let titrek = dokunuslar([(0.1, "b", 1, [100, 300]), (0.14, "k", 1, [104, 303]), (0.2, "e", 1, [104, 303])])
    kontrol("dokunurken az kıpırdamak yine tık", titrek.1 == [.tik], "\(titrek.1)")
    var kalkan: [(Double, String, Int, SIMD2<Double>)] = kaydirma(1, 0.1, [100, 300], [100, 400]) + kaydirma(2, 0.105, [160, 300], [160, 400])
    kalkan.removeAll { $0.1 == "e" && $0.2 == 2 }
    kalkan += [(0.45, "k", 2, [190, 420]), (0.5, "e", 2, [190, 420])]
    let kalan = dokunuslar(kalkan)
    kontrol("iki parmaktan biri kalkınca kalan parmak imleci oynatmaz", kalan.0.hareket == .zero, "\(kalan.0.hareket)")
}


// MARK: Touchpad yatay
do {
    print("— Touchpad yatay")
    // Üst kenar solda: kullanıcının sağı dikey ekranın +y'si, yukarısı +x'i
    var tp = TouchpadIzleyici()
    let y = TouchpadYonu.yatayUstSolda
    _ = tp.basla(id: 1, konum: y.cevir([100, 100]), t: 0)
    for i in 1...10 { _ = tp.kay(id: 1, konum: y.cevir([100, 100 + Double(i) * 10]), t: Double(i) * 0.02) }
    _ = tp.bitti(id: 1, t: 0.3)
    kontrol("yatay (üst solda): ekranın altına doğru kaydırmak = sağa", tp.hareket.x > 99 && abs(tp.hareket.y) < 0.01, "\(tp.hareket)")
    var tp2 = TouchpadIzleyici()
    let y2 = TouchpadYonu.yatayUstSagda
    _ = tp2.basla(id: 1, konum: y2.cevir([200, 100]), t: 0)
    for i in 1...10 { _ = tp2.kay(id: 1, konum: y2.cevir([200 - Double(i) * 10, 100]), t: Double(i) * 0.02) }
    _ = tp2.bitti(id: 1, t: 0.3)
    kontrol("yatay (üst sağda): dikey ekranın soluna doğru kaydırmak = yukarı", tp2.hareket.y > 99 && abs(tp2.hareket.x) < 0.01, "\(tp2.hareket)")
    kontrol("yerçekimi: dik = dikey, sola yatık = üst solda, sağa = üst sağda, masada düz = bilinmez",
            TouchpadYonu.yercekiminden(x: 0, y: -0.98) == .dikey && TouchpadYonu.yercekiminden(x: -0.95, y: 0.1) == .yatayUstSolda
            && TouchpadYonu.yercekiminden(x: 0.9, y: -0.2) == .yatayUstSagda && TouchpadYonu.yercekiminden(x: 0.05, y: -0.1) == nil, "")
}

print(hata == 0 ? "\nHepsi geçti." : "\n\(hata) deneme kaldı.")
exit(hata == 0 ? 0 : 1)
