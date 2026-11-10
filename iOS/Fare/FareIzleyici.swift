import Foundation
import simd

// iPhone Fare'nin hesap kısmı. UIKit/ARKit yok: Mac'te sahte verilerle denenebilsin (Tests/main.swift).
// Yönler kullanıcıya göre: +x sağa, +y ileri (telefonun üst kenarı senden uzağa bakar, fare gibi).

// Ters mod: telefon ekranı masaya bakar, arka kamera tavana. ARKit tavana göre telefonun yerini milimetrik verir.
// Burada iki kare arasındaki yer değişimi telefonun kendi eksenlerine izdüşürülür (fare döndürülünce olduğu gibi),
// küçük titremeler ölü bölgede yutulur, telefon masadan kaldırılınca hareket sayılmaz (gerçek fare gibi).
// Kaldırma: ARKit'in yükseklik tahmini özellikle ilk saniyelerde santim kadar kayabiliyor (8 Kasım, telefonda: masada
// dururken "havada" sanıyordu). Bu yüzden telefon kıpırdamadan duruyorsa masada sayılır ve masa yüksekliği o an yeniden
// alınır; havada sadece hareket hâlindeyken ve masadan 1,5 cm yukarıdaysa olur.
struct KameraIzleyici {
    var oluBolge = 0.00015      // m: bundan küçük titreme imleci oynatmaz
    var kalkmaYuksekligi = 0.015 // m: hareket hâlindeyken masadan bu kadar yükselince "havada"

    private(set) var ham = SIMD2<Double>.zero
    private(set) var cikis = SIMD2<Double>.zero
    private(set) var havada = false
    private var son: SIMD3<Double>?
    private var zemin: Double?

    // konum: ARKit dünya koordinatı (y yukarı). sag/ileri: kullanıcının sağı ve ilerisi, dünya koordinatında.
    // gecerli: izleme güvenilir mi. sakin: hareket sensörü telefonu bir süredir kıpırdamaz görüyor mu (masada demek).
    mutating func ekle(konum p: SIMD3<Double>, sag: SIMD3<Double>, ileri: SIMD3<Double>, gecerli: Bool, sakin: Bool) {
        defer { son = p }
        guard let son else { return }
        guard gecerli else { return }

        // Zemin: telefon masadayken kameranın yüksekliği. Kıpırdamadan duruyorsa şu anki yükseklik zemindir
        // (ARKit'in kayması burada sıfırlanır); daha alçak görülürse de hemen o olur. Havadan inişte yarı eşikte biter.
        if sakin || zemin == nil { zemin = p.y }
        else if p.y < zemin! { zemin = p.y }
        let yukseklik = p.y - zemin!
        let yeniHavada = havada ? yukseklik > kalkmaYuksekligi * 0.5 : yukseklik > kalkmaYuksekligi
        if yeniHavada != havada {
            havada = yeniHavada
            if !havada { ham = cikis }   // yere inince olduğu yerden devam (inişteki sarsıntı imleci itmesin)
        }
        guard !havada else { return }

        let d = p - son
        ham += SIMD2(simd_dot(d, sag), simd_dot(d, ileri))
        izle()
    }

    // Vuruş (tık) anında telefon biraz sarsılır: o anki hareket atılır, imlece geçmez
    mutating func sabitle() { ham = cikis }

    private mutating func izle() {
        let fark = ham - cikis
        let boy = simd_length(fark)
        if boy > oluBolge { cikis += fark * (1 - oluBolge / boy) }
    }
}

// Düz mod: telefon ekranı yukarı, kamera masaya bakar (görüntü yok). Sadece ivme sensörü: ivmeden hız, hızdan yol.
// Her ölçüm hatası birikir, bu yüzden telefon durunca hız sıfırlanır. Zor kısımlar:
// - Başlangıç: eşik geçilene kadarki kısım kaybolmasın diye son 250 ms saklanır, hareket başlayınca o da sayılır.
// - Durma: sabit hızla kayarken ivme sıfıra yakındır, "durdu" sanılabilir. Kayan telefon masada titrer;
//   titreşim dururkenki seviyenin üstündeyse durdu sayılmaz.
// - Fren: itişin sonunda frenlemeyi biraz fazla ölçmek hızı ters yöne çevirir, imleç geri kaçar. Ters yöndeki hız,
//   tepe hızın %35'ini geçmedikçe sıfırda tutulur; geçerse gerçekten geri dönüyorsun demektir.
// - Hayalet: süzülürken "durdu" sanılırsa ardından gelen frenleme yeni, ters bir itiş gibi görünür. Bir duruştan
//   hemen sonra (0,3 sn) ters yöne başlayan itiş bekletilir: bittiğinde hızı hâlâ yüksekse frenmiş, atılır;
//   gerçek bir itişse (hızlanıp yavaşladıysa) yolu o an imlece eklenir.
// - Sabit hata: sensör dururken bile biraz ivme gösterir. Sadece kesin durgun örneklerden (250 ms eski) öğrenilir;
//   yoksa itişin başı da "hata" diye öğrenilir ve imleç kendi kendine kaçar. Kaçmaya karşı sigorta: telefon
//   0,5 sn titremeden ve dönmeden durursa ya da bir itiş 1,2 sn'yi geçerse itiş biter.
// - Sabit ivme (8 Kasım, telefonda 3 sn'de 3,3 m kaçtı): eğik/sallanan telefonda yerçekimi sızar, koyarken elin hareketi de
//   hata diye öğrenilebiliyordu. Artık hata sadece kıpırtısız (dönmeyen, titremeyen) örneklerden öğrenilir; durma ivmenin
//   sıfır olmasına değil sabit kalmasına bakar; her duruşta o anki sabit ivme yeni hata olur. Hız saniyede 1 m'yi geçmez.
struct SensorIzleyici {
    var baslamaEsigi = 0.06  // m/s², 50 ms ortalaması: bunu geçince hareket başladı
    var durmaOrani = 0.6     // durma eşiği = başlama eşiği × bu
    var donusEsigi = 0.25    // rad/s: telefon dönüyorsa duruyor sayılmaz

    private(set) var konum = SIMD2<Double>.zero
    private(set) var hiz = SIMD2<Double>.zero
    private(set) var hareketli = false
    private var sakinSure = 0.0
    private var sapma = SIMD2<Double>.zero    // dururken sensörün gösterdiği sabit hata
    private var tepe = SIMD2<Double>.zero     // bu itişte eksen eksen en yüksek hız
    private var ters = SIMD2<Double>.zero     // tepe yönünün tersine biriken hız
    private var sonlar: [SIMD2<Double>] = []  // son 5 örnek (ortalama)
    private var oncesi: [(net: SIMD2<Double>, ham: SIMD2<Double>, dt: Double, kipirtisiz: Bool)] = []   // hareket başlamadan önceki 250 ms
    private var titresim = 0.0
    private var sakinTitresim = 0.01          // dururken titreşim (öğrenilir)
    private var sakinOrnek = 0                // sapma öğrenilirken sayılan durgun örnek
    private var saat = 0.0
    private var sonDurus = -10.0
    private var sonYon = SIMD2<Double>.zero   // son itişin yönü
    private var itisBaslangici = SIMD2<Double>.zero
    private var hayalet = false
    private var bekleyen = SIMD2<Double>.zero // hayalet itişin bekletilen yolu
    private var itisSuresi = 0.0
    private var durgunSure = 0.0
    private var itisDonus = 0.0               // bu itişteki en hızlı dönme: eğim değişti mi

    // ivme: m/s², kullanıcı ekseninde (yerçekimi çıkmış). donus: rad/s büyüklük. dt: sn.
    mutating func ekle(ivme a: SIMD2<Double>, donus: Double, dt: Double) {
        saat += dt
        let net = a - sapma
        sonlar.append(net)
        if sonlar.count > 10 { sonlar.removeFirst() }
        let kisa = sonlar.suffix(5).reduce(SIMD2<Double>.zero, +) / Double(min(sonlar.count, 5))   // 50 ms
        let uzun = sonlar.reduce(SIMD2<Double>.zero, +) / Double(sonlar.count)                     // 100 ms
        titresim += (simd_length(net - kisa) - titresim) * 0.15

        // İvme sıfıra yakın ya da (itişte telefon eğildiyse) sabit: eğim sızıntısı sıfır olmayan sabit bir değer bırakır.
        // Eğilme olmadan sabit ivme yavaş bir itiş de olabilir, o yüzden orada sıfır beklenir.
        let sabit = simd_length(kisa - uzun) < baslamaEsigi * durmaOrani
        if hareketli { itisDonus = max(itisDonus, donus) }
        let duruyorGibi = simd_length(uzun) < baslamaEsigi * durmaOrani || (sabit && itisDonus > 0.3)
        if hareketli {
            let sakin = duruyorGibi && donus < donusEsigi && titresim < max(sakinTitresim * 2.5, 0.02)
            // Tek tük gürültü sayacı sıfırlamasın: sakin değilken iki kat hızla geri sayar
            sakinSure = sakin ? sakinSure + dt : max(0, sakinSure - 2 * dt)
            let durgun = (simd_length(uzun) < baslamaEsigi || (sabit && itisDonus > 0.3)) && donus < donusEsigi
                && titresim < max(sakinTitresim * 1.5, 0.015)
            durgunSure = durgun ? durgunSure + dt : 0
            itisSuresi += dt
            if sakinSure >= 0.12 || durgunSure >= 0.5 {
                sapma += uzun   // telefon duruyor: kalan sabit ivme yeni hata
                itisBitti()
                return
            }
            if itisSuresi > 1.2 {
                // Uzun süren "itiş" çoğu zaman sabit hatadır: telefon kıpırtısız ve ivme sabitse hata olarak al
                if sabit && donus < 0.1 && titresim < max(sakinTitresim * 2.5, 0.02) { sapma += uzun }
                itisBitti()
                return
            }
        } else if simd_length(kisa) > baslamaEsigi && sakinOrnek >= 20 {
            hareketli = true
            itisDonus = donus
            sakinSure = 0
            durgunSure = 0
            itisSuresi = 0
            var v = SIMD2<Double>.zero
            var yol = SIMD2<Double>.zero
            for ornek in oncesi {
                v += ornek.net * ornek.dt
                yol += v * ornek.dt
            }
            oncesi.removeAll()
            hiz = v
            itisBaslangici = konum
            let yon = simd_length(v) > 0 ? v : kisa
            hayalet = saat - sonDurus < 0.3 && simd_dot(yon, sonYon) < 0
            bekleyen = .zero
            ilerle(yol)
        } else {
            // Kıpırtısız örnek: dönmüyor (elde değil, sallanmıyor) ve titremiyor. Hata sadece bunlardan öğrenilir.
            let kipirtisiz = donus < 0.1 && (sakinOrnek < 20 || titresim < max(sakinTitresim * 2.5, 0.02))
            oncesi.append((net, a, dt, kipirtisiz))
            if oncesi.count > 25 {
                let eski = oncesi.removeFirst()   // 250 ms önce durgundu ve hâlâ hareket başlamadı: kesin durgun
                if eski.kipirtisiz {
                    sakinOrnek += 1
                    sapma += (eski.ham - sapma) * max(0.05, 1 / Double(sakinOrnek))
                }
            }
            if kipirtisiz { sakinTitresim += (titresim - sakinTitresim) * (sakinOrnek < 20 ? 0.2 : 0.02) }
            return
        }

        hiz += net * dt
        for i in 0..<2 {
            if tepe[i] != 0 && hiz[i] * tepe[i] < 0 {
                ters[i] += hiz[i]
                if abs(ters[i]) > abs(tepe[i]) * 0.35 {
                    hiz[i] = ters[i]       // gerçekten geri dönüyor
                    tepe[i] = ters[i]
                    ters[i] = 0
                } else {
                    hiz[i] = 0
                }
            } else {
                ters[i] = 0
                if abs(hiz[i]) > 0.01 && abs(hiz[i]) > abs(tepe[i]) { tepe[i] = hiz[i] }
            }
        }
        hiz = SIMD2(min(max(hiz.x, -1), 1), min(max(hiz.y, -1), 1))   // el ile saniyede 1 m'den hızlı itilmez
        ilerle(hiz * dt)
    }

    private mutating func ilerle(_ yol: SIMD2<Double>) {
        if hayalet { bekleyen += yol } else { konum += yol }
    }

    private mutating func itisBitti() {
        if hayalet {
            // Frenleme: hız sona kadar yüksek kaldı (hızlanıp yavaşlamadı). Gerçek itişse yolunu şimdi ver.
            let frenMi = simd_length(hiz) > simd_length(tepe) * 0.5
            if !frenMi { konum += bekleyen }
        } else {
            let yol = konum - itisBaslangici
            if simd_length(yol) > 0.002 { sonYon = yol }
        }
        sonDurus = saat
        durdur()
    }

    // Durunca ya da ekrana dokununca (telefon sarsılır) hız atılır
    mutating func durdur() {
        hareketli = false
        hayalet = false
        bekleyen = .zero
        hiz = .zero
        tepe = .zero
        ters = .zero
        sakinSure = 0
        oncesi.removeAll()
    }
}

// Ters modda tık: telefonun sırtına parmakla vurunca ekran yönünde (z) kısa, sert bir sıçrama olur.
// Masada kaydırmak çoğunlukla yatay ivme; z'deki sıçrama yatayın 1,5 katından büyükse vuruş sayılır.
struct VurmaAlgilayici {
    var esik = 0.15   // g
    private var ortalama = 0.0
    private var bekleme = 0.0
    private(set) var tepe = 0.0   // okunana kadarki en sert z sıçraması (g)

    // z: ekran yönündeki ivme (g, yerçekimi çıkmış). yatay: yatay ivme büyüklüğü (g).
    mutating func ekle(z: Double, yatay: Double, dt: Double) -> Bool {
        let sicrama = abs(z - ortalama)
        ortalama += (z - ortalama) * 0.1
        bekleme = max(0, bekleme - dt)
        tepe = max(tepe, sicrama)
        guard bekleme == 0, sicrama > esik, sicrama > yatay * 1.5 else { return false }
        bekleme = 0.18
        return true
    }

    mutating func tepeyiOku() -> Double {
        defer { tepe = 0 }
        return tepe
    }
}

// Touchpad modu: telefon ekranı Mac trackpad'i gibi. Konumlar ekran noktası (pt), y aşağı doğru artar.
// Tek parmak kaydır = imleç. Dokun = sol tık (çift dokunuş = çift tık). İki parmakla dokun = sağ tık.
// İki parmakla kaydır = sayfa kaydır. Dokun, hemen tekrar dokunup sürükle = basılı tutup taşı.
// Tek dokunuşun tıkı kısa bir süre bekletilir: ardından ikinci dokunuş gelirse çift tık ya da sürükleme olur.
// Beklemeden gönderilse sürüklemenin başı Mac'te çift tık sayılırdı (Finder'da dosya açılırdı).
struct TouchpadIzleyici {
    enum Olay: Equatable { case tik, ciftTik, sagTik, surukleBasla, surukleBitir }

    var dokunmaSuresi = 0.25     // sn: bundan kısa ve az kıpırdayan dokunuş tıktır
    var dokunmaYaricapi = 10.0   // pt
    var ciftAraligi = 0.22       // sn: ikinci dokunuş için bekleme

    private(set) var hareket = SIMD2<Double>.zero   // birikimli imleç yolu (pt): +x sağa, +y yukarı
    private(set) var kaydirma = 0.0                 // birikimli kaydırma (pt): parmaklar aşağı +
    private(set) var surukluyor = false
    private var parmaklar: [Int: SIMD2<Double>] = [:]
    private var baslangic = 0.0
    private var enCokParmak = 0
    private var toplamYol = 0.0
    private var bekleyenTik: Double?   // tek dokunuş bitti, ikincisi bekleniyor
    private var ikinci = false         // bu dokunuş, bekleyen bir tıkın ardından geldi

    var parmakSayisi: Int { parmaklar.count }
    var tikBekliyor: Bool { bekleyenTik != nil }

    mutating func basla(id: Int, konum: SIMD2<Double>, t: Double) -> [Olay] {
        var olaylar: [Olay] = []
        if parmaklar.isEmpty {
            baslangic = t
            enCokParmak = 0
            toplamYol = 0
            if let b = bekleyenTik, t - b >= ciftAraligi {   // süre dolmuş ama zamanlayıcı henüz gelmemiş
                bekleyenTik = nil
                olaylar.append(.tik)
            }
            ikinci = bekleyenTik != nil
        }
        parmaklar[id] = konum
        enCokParmak = max(enCokParmak, parmaklar.count)
        if parmaklar.count >= 2, ikinci {   // ikinci dokunuş iki parmakla geldi: önceki tek tık kendi başına sayılır
            ikinci = false
            bekleyenTik = nil
            olaylar.append(.tik)
        }
        return olaylar
    }

    mutating func kay(id: Int, konum: SIMD2<Double>, t: Double) -> [Olay] {
        guard let eski = parmaklar[id] else { return [] }
        parmaklar[id] = konum
        let d = konum - eski
        var olaylar: [Olay] = []
        if parmaklar.count >= 2 {
            kaydirma += d.y / Double(parmaklar.count)
            toplamYol += simd_length(d) / Double(parmaklar.count)
        } else if enCokParmak == 1 {   // iki parmaktan biri kalktıysa kalan parmak imleci zıplatmasın
            toplamYol += simd_length(d)
            if ikinci && !surukluyor && toplamYol > dokunmaYaricapi {
                surukluyor = true
                bekleyenTik = nil
                olaylar.append(.surukleBasla)
            }
            hareket += SIMD2(d.x, -d.y)
        }
        return olaylar
    }

    mutating func bitti(id: Int, t: Double) -> [Olay] {
        guard parmaklar.removeValue(forKey: id) != nil, parmaklar.isEmpty else { return [] }
        if surukluyor {
            surukluyor = false
            return [.surukleBitir]
        }
        let dokunus = t - baslangic < dokunmaSuresi && toplamYol < dokunmaYaricapi
        if dokunus && enCokParmak >= 2 {
            bekleyenTik = nil
            return [.sagTik]
        }
        if dokunus && ikinci && bekleyenTik != nil {
            bekleyenTik = nil
            return [.ciftTik]
        }
        if dokunus {
            bekleyenTik = t
            return []
        }
        if bekleyenTik != nil {   // ikinci dokunuş tık da sürükleme de olmadı: ilk tık kendi başına sayılır
            bekleyenTik = nil
            return [.tik]
        }
        return []
    }

    // Bekleyen tek tık: süre doldu ve ikinci dokunuş gelmedi
    mutating func zaman(_ t: Double) -> [Olay] {
        guard let b = bekleyenTik, parmaklar.isEmpty, t - b >= ciftAraligi else { return [] }
        bekleyenTik = nil
        return [.tik]
    }
}

// Touchpad'in tutuluş yönü. Uygulama hep dikey (arayüz dönmüyor), ekran noktaları dikeye göre gelir;
// telefon yatay tutulunca kullanıcının sağı/yukarısı ekranın başka bir kenarına denk gelir, noktalar çevrilir.
enum TouchpadYonu: Int, CaseIterable {
    case dikey
    case yatayUstSolda   // telefonun üst kenarı solda (saat yönünün tersine çevrilmiş)
    case yatayUstSagda   // üst kenar sağda

    var ad: String {
        switch self {
        case .dikey: return "dikey"
        case .yatayUstSolda, .yatayUstSagda: return "yatay"
        }
    }

    // Dikey ekran noktası (y aşağı) → kullanıcının gördüğü düzlem (x sağa, y aşağı). Uzunluklar korunur.
    func cevir(_ p: SIMD2<Double>) -> SIMD2<Double> {
        switch self {
        case .dikey: return p
        case .yatayUstSolda: return SIMD2(p.y, -p.x)
        case .yatayUstSagda: return SIMD2(-p.y, p.x)
        }
    }

    // Yerçekimi (telefon ekseninde, g). Telefon belirgin eğik tutuluyorsa yön; masada düz yatıyorsa nil (bilinmez).
    static func yercekiminden(x gx: Double, y gy: Double) -> TouchpadYonu? {
        if gx < -0.6 { return .yatayUstSolda }
        if gx > 0.6 { return .yatayUstSagda }
        if gy < -0.6 { return .dikey }
        return nil
    }

    var sonraki: TouchpadYonu { TouchpadYonu(rawValue: (rawValue + 1) % 3)! }
}
