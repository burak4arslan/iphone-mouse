import AppKit
import ApplicationServices
import Network
import SwiftUI
import simd

// iPhone Fare (Mac): iPhone uygulamasından gelen UDP paketleriyle imleci oynatır, tıklar, kaydırır.
// Telefon Bonjour'da _iphonefare._udp arar; bu uygulama o adla yayın yapar. Paket: ../iOS/Fare/FareProtokol.swift.
// Tıklama ve sürükleme için Erişilebilirlik izni gerekir; izin yoksa sadece imleç oynar.
// Gerçek trackpad de çalışmaya devam eder: her harekette imlecin o anki yerinden devam edilir.
// Derleme: ./build.sh. FARE_KURU=1 ile açılırsa imleci hiç oynatmaz, hesapladığını yazar (deneme için).
@main
struct IPhoneFareApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var alici = FareAlici()

    var body: some Scene {
        WindowGroup(Metin.ingilizce ? Metin.uygulamaAdi.en : Metin.uygulamaAdi.tr) {
            AnaGorunum(alici: alici)
                .frame(width: 480)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

@MainActor
final class FareAlici: ObservableObject {
    // Ayarlar
    @Published var acik: Bool { didSet { kaydet(); if !acik { dugmeleriBirak() } } }
    @Published var hassasiyet: Double { didSet { kaydet() } }   // nokta / mm (ivmesiz)
    @Published var ivme: Bool { didSet { kaydet() } }
    @Published var tersX: Bool { didSet { kaydet() } }
    @Published var tersY: Bool { didSet { kaydet() } }
    @Published var tersKaydir: Bool { didSet { kaydet() } }
    @Published var vurmaEsigi: Double { didSet { kaydet() } }  // g
    @Published var ekran: String { didSet { kaydet() } }         // imleç bu ekrandan çıkmaz ("" = hepsi)
    @Published var halkaAcik: Bool { didSet { kaydet(); halkayiGuncelle() } }   // çekim için imleç halkası

    // Ekranda görünenler (saniyede 10 kez yenilenir)
    @Published private(set) var bagli = false
    @Published private(set) var mod = ""
    @Published private(set) var durum = ""
    @Published private(set) var nokta = 0
    @Published private(set) var hizMm = 0.0
    @Published private(set) var vurmaTepe = 0.0
    @Published private(set) var tikSayisi = 0
    @Published private(set) var izin = AXIsProcessTrusted()
    @Published private(set) var yol: [CGPoint] = []   // telefonun son 4 sn'lik yolu (mm)
    @Published private(set) var dinleyiciDurumu = "başlıyor"

    let ad = Host.current().localizedName ?? "Mac"
    private let kuru = ProcessInfo.processInfo.environment["FARE_KURU"] == "1"
    private var dinleyici: NWListener?
    private var baglantilar: [NWConnection] = []
    private let kaynak = CGEventSource(stateID: .hidSystemState)

    // Son paketten kalanlar
    private var paket: FarePaketi?
    private var oturum: UInt32 = 0
    private var sira: UInt64 = 0
    private var sonKonum = SIMD2<Double>.zero
    private var sonHareketT = 0.0
    private var sonKaydir = 0.0
    private var sonTik: UInt32 = 0
    private var sonSagTik: UInt32 = 0
    private let halka = ImlecHalkasi()
    private var pencereYerlesti = false
    private var solBasili = false
    private var sagBasili = false
    private var artik = SIMD2<Double>.zero        // nokta altı birikim
    private var kaydirArtik = 0.0
    private var anlikHiz = 0.0
    private var sonBasma: (zaman: TimeInterval, yer: CGPoint, sayi: Int64) = (0, .zero, 0)
    private var sonPaketZamani = Date.distantPast
    private var sonCevap = Date.distantPast
    private var yolNoktalari: [(Date, CGPoint)] = []
    private var yolUcu = CGPoint.zero
    private var zamanlayici: Timer?
    private var izinSayac = 0

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["acik": true, "hassasiyet": 10.0, "ivme": true, "tersX": false, "tersY": false,
                              "tersKaydir": false, "vurmaEsigi": 0.15, "ekran": "", "halkaAcik": true])
        acik = d.bool(forKey: "acik")
        hassasiyet = d.double(forKey: "hassasiyet")
        ivme = d.bool(forKey: "ivme")
        tersX = d.bool(forKey: "tersX")
        tersY = d.bool(forKey: "tersY")
        tersKaydir = d.bool(forKey: "tersKaydir")
        vurmaEsigi = d.double(forKey: "vurmaEsigi")
        ekran = d.string(forKey: "ekran") ?? ""
        halkaAcik = d.bool(forKey: "halkaAcik")
        kaynak?.localEventsSuppressionInterval = 0   // gönderdiğimiz olaylar gerçek trackpad'i susturmasın
        if kuru { setvbuf(stdout, nil, _IOLBF, 0) }   // deneme günlüğü dosyaya satır satır düşsün
        baslat()
    }

    private func kaydet() {
        let d = UserDefaults.standard
        d.set(acik, forKey: "acik")
        d.set(hassasiyet, forKey: "hassasiyet")
        d.set(ivme, forKey: "ivme")
        d.set(tersX, forKey: "tersX")
        d.set(tersY, forKey: "tersY")
        d.set(tersKaydir, forKey: "tersKaydir")
        d.set(vurmaEsigi, forKey: "vurmaEsigi")
        d.set(ekran, forKey: "ekran")
        d.set(halkaAcik, forKey: "halkaAcik")
    }

    var ekranAdlari: [String] { NSScreen.screens.map(\.localizedName) }

    private func ekranAlani(_ ad: String) -> CGRect? {
        guard !ad.isEmpty, let s = NSScreen.screens.first(where: { $0.localizedName == ad }),
              let no = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        return CGDisplayBounds(no)
    }

    // Pencere açılışta seçili ekranın sağ üst köşesine gelir (çekimde telefonun yolu görünsün)
    func pencereyiYerlestir() {
        guard !pencereYerlesti, !ekran.isEmpty,
              let s = NSScreen.screens.first(where: { $0.localizedName == ekran }),
              let pencere = NSApp.windows.first(where: { $0.isVisible && [Metin.uygulamaAdi.tr, Metin.uygulamaAdi.en].contains($0.title) }) else { return }
        pencereYerlesti = true
        let alan = s.visibleFrame
        pencere.setFrameOrigin(NSPoint(x: alan.maxX - pencere.frame.width - 30, y: alan.maxY - pencere.frame.height - 30))
    }

    private func halkayiGuncelle() {
        halka.goster(halkaAcik && bagli && paket.map { $0.oturum != 0 } == true && !kuru)
    }

    func izinIste() {
        let secenek = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        izin = AXIsProcessTrustedWithOptions(secenek)
        if !izin, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Ağ

    private func baslat() {
        do {
            let yeni = try NWListener(using: .udp)
            yeni.service = NWListener.Service(name: ad, type: FareAg.servis)
            yeni.stateUpdateHandler = { [weak self] durum in
                let metin: String
                switch durum {
                case .ready: metin = "hazır"
                case .failed(let hata): metin = "hata: \(hata)"
                case .waiting(let hata): metin = "bekliyor: \(hata)"
                default: metin = "başlıyor"
                }
                DispatchQueue.main.async { self?.dinleyiciDurumu = metin }
                if self?.kuru == true { print("dinleyici: \(metin)") }
            }
            yeni.newConnectionHandler = { [weak self] baglanti in
                DispatchQueue.main.async { self?.yeniBaglanti(baglanti) }
            }
            yeni.start(queue: .main)
            dinleyici = yeni
        } catch {
            dinleyiciDurumu = "hata: \(error)"
        }
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.arayuzuYenile() }
        }
    }

    private func yeniBaglanti(_ baglanti: NWConnection) {
        // Telefon her yeniden bağlanışta yeni bir UDP "bağlantısı" açar; eskileri biriktirme
        baglantilar.append(baglanti)
        while baglantilar.count > 4 { baglantilar.removeFirst().cancel() }
        baglanti.start(queue: .main)
        dinle(baglanti)
    }

    private func dinle(_ baglanti: NWConnection) {
        baglanti.receiveMessage { [weak self] veri, _, _, hata in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let veri, let p = try? JSONDecoder().decode(FarePaketi.self, from: veri) {
                    self.isle(p, baglanti)
                }
                if hata == nil { self.dinle(baglanti) }
            }
        }
    }

    private func cevapla(_ baglanti: NWConnection) {
        guard Date().timeIntervalSince(sonCevap) > 0.3 else { return }
        sonCevap = Date()
        let cevap = FareCevabi(ad: ad, acik: acik, izin: izin, vurmaEsigi: vurmaEsigi)
        if let veri = try? JSONEncoder().encode(cevap) {
            baglanti.send(content: veri, completion: .idempotent)
        }
    }

    // Tanı kaydı: telefonun durumu (izleme iyi / havada / tavanda iz az), nokta sayısı ve konumu. Durum değişince ya da
    // yarım saniyede bir satır. ~/Library/Logs/iPhoneFare/<gün>.csv — "ne zaman havada sanıyor" gibi aralıklı sorunlar için.
    private var kayitDosyasi: FileHandle?
    private var sonKayit = Date.distantPast
    private var sonKayitDurum = ""
    private func kaydet(_ p: FarePaketi) {
        guard p.oturum != 0 else { return }
        let simdi = Date()
        guard p.durum != sonKayitDurum || simdi.timeIntervalSince(sonKayit) >= 0.5 else { return }
        sonKayit = simdi; sonKayitDurum = p.durum
        if kayitDosyasi == nil {
            let klasor = URL(fileURLWithPath: NSString(string: "~/Library/Logs/iPhoneFare").expandingTildeInPath)
            try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
            let gun = ISO8601DateFormatter.string(from: simdi, timeZone: .current, formatOptions: [.withFullDate])
            let yol = klasor.appendingPathComponent("\(gun).csv")
            if !FileManager.default.fileExists(atPath: yol.path) {
                try? "saat;oturum;mod;durum;nokta;x_mm;y_mm;tik;sagTik\n".write(to: yol, atomically: true, encoding: .utf8)
            }
            kayitDosyasi = try? FileHandle(forWritingTo: yol)
            kayitDosyasi?.seekToEndOfFile()
        }
        let saat = ISO8601DateFormatter.string(from: simdi, timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime, .withFractionalSeconds])
        let satir = String(format: "%@;%u;%@;%@;%d;%.1f;%.1f;%u;%u\n", saat, p.oturum, p.mod, p.durum, p.nokta, p.x * 1000, p.y * 1000, p.tik, p.sagTik ?? 0)
        kayitDosyasi?.write(satir.data(using: .utf8)!)
    }

    private func isle(_ p: FarePaketi, _ baglanti: NWConnection) {
        sonPaketZamani = Date()
        cevapla(baglanti)
        paket = p
        kaydet(p)
        guard p.oturum != 0 else { return }   // telefon henüz başlatmadı, sadece selam

        if p.oturum != oturum {
            oturum = p.oturum
            sira = p.sira
            sonKonum = SIMD2(p.x, p.y)
            sonHareketT = p.t
            sonKaydir = p.kaydir
            sonTik = p.tik
            sonSagTik = p.sagTik ?? 0
            artik = .zero
            tikSayisi = 0
            dugmeleriBirak()
            return
        }
        guard p.sira > sira else { return }   // geç gelen eski paket
        sira = p.sira

        let konum = SIMD2(p.x, p.y)
        let fark = konum - sonKonum
        sonKonum = konum
        let kaydirFark = p.kaydir - sonKaydir
        sonKaydir = p.kaydir
        let yeniTik = Int(p.tik &- sonTik)
        sonTik = p.tik
        let yeniSagTik = Int((p.sagTik ?? sonSagTik) &- sonSagTik)
        sonSagTik = p.sagTik ?? sonSagTik

        if simd_length(fark) > 0 {
            let dt = min(max(p.t - sonHareketT, 0.004), 0.05)
            sonHareketT = p.t
            let anlik = simd_length(fark) * 1000 / dt
            anlikHiz += (anlik - anlikHiz) * 0.3
            yolUcu.x += fark.x * 1000
            yolUcu.y += fark.y * 1000
            yolNoktalari.append((Date(), yolUcu))
            if acik { tasi(fark) }
        } else if p.t - sonHareketT > 0.1 {
            anlikHiz = 0
            sonHareketT = p.t
        }

        guard acik else { return }
        if kaydirFark != 0 { kaydir(kaydirFark) }
        if p.sol != solBasili { dugme(sol: true, basili: p.sol) }
        if p.sag != sagBasili { dugme(sol: false, basili: p.sag) }
        if yeniTik > 0 {
            for _ in 0..<min(yeniTik, 3) {
                dugme(sol: true, basili: true)
                dugme(sol: true, basili: false)
            }
            tikSayisi += yeniTik
        }
        if yeniSagTik > 0 {
            for _ in 0..<min(yeniSagTik, 3) {
                dugme(sol: false, basili: true)
                dugme(sol: false, basili: false)
            }
            tikSayisi += yeniSagTik
        }
    }

    // MARK: - İmleç

    // Telefonun mm cinsinden yer değişimi → ekran noktası. İvme açıksa hızlı itiş daha uzağa gider (Mac faresi gibi).
    private func tasi(_ fark: SIMD2<Double>) {
        let carpan = ivme ? min(max(0.5 + anlikHiz / 200, 0.5), 3.0) : 1
        let mm = fark * 1000
        artik.x += mm.x * hassasiyet * carpan * (tersX ? -1 : 1)
        artik.y += -mm.y * hassasiyet * carpan * (tersY ? -1 : 1)   // ileri = ekranda yukarı
        let adim = SIMD2(artik.x.rounded(.towardZero), artik.y.rounded(.towardZero))
        guard adim != .zero else { return }
        artik -= adim
        if kuru {
            print(String(format: "imleç %+.0f %+.0f  (telefon %+.2f %+.2f mm, %.0f mm/sn)", adim.x, adim.y, mm.x, mm.y, anlikHiz))
            return
        }
        guard let simdi = CGEvent(source: nil)?.location else { return }
        let hedef = sinirla(CGPoint(x: simdi.x + adim.x, y: simdi.y + adim.y), eski: simdi)
        if izin {
            let tur: CGEventType = solBasili ? .leftMouseDragged : (sagBasili ? .rightMouseDragged : .mouseMoved)
            let olay = CGEvent(mouseEventSource: kaynak, mouseType: tur, mouseCursorPosition: hedef,
                               mouseButton: sagBasili && !solBasili ? .right : .left)
            olay?.setIntegerValueField(.mouseEventDeltaX, value: Int64(adim.x))
            olay?.setIntegerValueField(.mouseEventDeltaY, value: Int64(adim.y))
            olay?.post(tap: .cghidEventTap)
        } else {
            CGWarpMouseCursorPosition(hedef)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    // İmleç ekranların dışına çıkmasın: hedef hiçbir ekranda değilse imlecin olduğu ekranın kenarında durur
    private func sinirla(_ p: CGPoint, eski: CGPoint) -> CGPoint {
        if let r = ekranAlani(ekran) {   // çekim ekranı seçiliyse imleç oradan çıkmaz
            return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
        }
        var sayi: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &sayi)
        var ekranlar = [CGDirectDisplayID](repeating: 0, count: Int(sayi))
        CGGetActiveDisplayList(sayi, &ekranlar, &sayi)
        let alanlar = ekranlar.map { CGDisplayBounds($0) }
        if alanlar.contains(where: { $0.contains(p) }) { return p }
        guard let r = alanlar.first(where: { $0.contains(eski) }) ?? alanlar.first else { return eski }
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }

    private func dugme(sol: Bool, basili: Bool) {
        if sol { solBasili = basili } else { sagBasili = basili }
        if basili { halka.tik(sag: !sol) }
        halka.basili(solBasili || sagBasili)
        if kuru { print("\(sol ? "sol" : "sağ") düğme \(basili ? "basıldı" : "bırakıldı")"); return }
        guard izin, let yer = CGEvent(source: nil)?.location else { return }
        if basili {
            // Çift tık: macOS ikinci basışın "2. tık" olduğunu olaydaki sayıdan anlar
            let simdi = ProcessInfo.processInfo.systemUptime
            let yakin = hypot(yer.x - sonBasma.yer.x, yer.y - sonBasma.yer.y) < 6
            let sayi: Int64 = (simdi - sonBasma.zaman < NSEvent.doubleClickInterval && yakin) ? sonBasma.sayi + 1 : 1
            sonBasma = (simdi, yer, sayi)
        }
        let tur: CGEventType = sol ? (basili ? .leftMouseDown : .leftMouseUp) : (basili ? .rightMouseDown : .rightMouseUp)
        let olay = CGEvent(mouseEventSource: kaynak, mouseType: tur, mouseCursorPosition: yer, mouseButton: sol ? .left : .right)
        olay?.setIntegerValueField(.mouseEventClickState, value: sonBasma.sayi)
        olay?.post(tap: .cghidEventTap)
    }

    private func dugmeleriBirak() {
        if solBasili { dugme(sol: true, basili: false) }
        if sagBasili { dugme(sol: false, basili: false) }
    }

    // Telefondaki şeritte parmak aşağı → sayfa aşağı gelir (doğal kaydırma)
    private func kaydir(_ miktar: Double) {
        kaydirArtik += miktar * 2 * (tersKaydir ? -1 : 1)
        let adim = kaydirArtik.rounded(.towardZero)
        guard adim != 0 else { return }
        kaydirArtik -= adim
        if kuru { print("kaydır \(Int(adim))"); return }
        guard izin else { return }
        CGEvent(scrollWheelEvent2Source: kaynak, units: .pixel, wheelCount: 1, wheel1: Int32(adim), wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    // MARK: - Ekran

    private func arayuzuYenile() {
        izinSayac += 1
        if izinSayac % 10 == 0 {
            let yeni = AXIsProcessTrusted()
            if yeni != izin { izin = yeni }
        }
        let yeniBagli = Date().timeIntervalSince(sonPaketZamani) < 1.5
        if yeniBagli != bagli {
            bagli = yeniBagli
            if !bagli { dugmeleriBirak() }   // telefon gitti: basılı düğme kalmasın
        }
        halkayiGuncelle()
        if let p = paket, bagli {
            let calisiyor = p.oturum != 0
            // Ham anahtar ("kamera", "sensor-ters"…; "" = telefonda başlatılmadı), ekranda Metin.mod çevirir
            let yeniMod = calisiyor ? p.mod : ""
            if yeniMod != mod { mod = yeniMod }
            let yeniDurum = calisiyor ? p.durum : ""
            if yeniDurum != durum { durum = yeniDurum }
            if p.nokta != nokta { nokta = p.nokta }
            if p.vurmaTepe != vurmaTepe { vurmaTepe = p.vurmaTepe }
        }
        let yeniHiz = (anlikHiz / 5).rounded() * 5
        if yeniHiz != hizMm { hizMm = yeniHiz }
        let sinir = Date().addingTimeInterval(-4)
        yolNoktalari.removeAll { $0.0 < sinir }
        let yeniYol = yolNoktalari.map(\.1)
        if yeniYol != yol { yol = yeniYol }
    }
}

struct AnaGorunum: View {
    @ObservedObject var alici: FareAlici
    @AppStorage(Metin.anahtar) private var dil = ""
    private var en: Bool { Metin.ingilizce(dil) }

    private var modVeDurum: String {
        let mod = alici.mod.isEmpty ? (en ? "Not started on the phone" : "Telefonda başlatılmadı") : Metin.mod(alici.mod, en: en)
        return [mod, Metin.durum(alici.durum, en: en)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(alici.bagli ? (en ? "Phone connected" : "Telefon bağlı") : (en ? "Waiting for the phone…" : "Telefon bekleniyor…"),
                          systemImage: alici.bagli ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .font(.title2.bold())
                        .foregroundStyle(alici.bagli ? Color.green : Color.primary)
                    Text(alici.bagli ? modVeDurum
                                     : (en ? "Open the iPhone Mouse app on the phone. Both must be on the same Wi-Fi."
                                           : "Telefonda iPhone Fare uygulamasını aç. İkisi aynı Wi-Fi'da olsun."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(en ? "Mouse on" : "Fare açık", isOn: $alici.acik).toggleStyle(.switch)
            }

            if !alici.izin {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(en ? "Clicking and dragging need Accessibility permission. Without it only the cursor moves." : "Tıklama ve sürükleme için Erişilebilirlik izni gerekli. İzin yokken sadece imleç oynar.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(en ? "Allow" : "İzin ver") { alici.izinIste() }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            YolCizimi(yol: alici.yol)
                .frame(height: 170)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    Text(en ? "Phone path (last 4 s)" : "Telefonun yolu (son 4 sn)").font(.caption).foregroundStyle(.secondary).padding(8)
                }

            HStack {
                Text(en ? "Speed: \(Int(alici.hizMm)) mm/s" : "Hız: \(Int(alici.hizMm)) mm/sn")
                Spacer()
                if alici.mod == "kamera" { Text(en ? "\(alici.nokta) ceiling points" : "Tavanda \(alici.nokta) nokta") }
                Spacer()
                Text(en ? "Clicks: \(alici.tikSayisi)" : "Tık: \(alici.tikSayisi)")
            }
            .monospacedDigit()

            VStack(alignment: .leading, spacing: 4) {
                Text(en ? "Sensitivity: 1 mm = \(Int(alici.hassasiyet)) points" : "Hassasiyet: 1 mm = \(Int(alici.hassasiyet)) nokta")
                Slider(value: $alici.hassasiyet, in: 2...40, step: 1)
                Toggle(en ? "Go further on fast pushes (acceleration)" : "Hızlı itince daha uzağa git (ivme)", isOn: $alici.ivme)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: en ? "Tap threshold: %.2f g · last tap %.2f g" : "Vurma eşiği: %.2f g · son vuruş %.2f g", alici.vurmaEsigi, alici.vurmaTepe))
                    .monospacedDigit()
                Slider(value: $alici.vurmaEsigi, in: 0.04...0.6)
                Text(en ? "Face-down click: tap the back of the phone with a finger. A tap above the threshold counts as a click." : "Ters modda tık: telefonun sırtına parmakla vur. Vuruş değeri eşiği geçince tık sayılır.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Picker(en ? "Keep the cursor on" : "İmleç şu ekranda kalsın", selection: $alici.ekran) {
                    Text(en ? "All displays" : "Bütün ekranlar").tag("")
                    ForEach(alici.ekranAdlari, id: \.self) { Text($0).tag($0) }
                }
                Toggle(en ? "Ring around the cursor (visible on video, flashes on clicks)" : "İmlecin etrafında halka (çekimde görünsün, tıklayınca parlar)", isOn: $alici.halkaAcik)
            }

            DisclosureGroup(en ? "Directions" : "Yönler") {
                VStack(alignment: .leading) {
                    Toggle(en ? "Flip left-right" : "Sağ-sol ters", isOn: $alici.tersX)
                    Toggle(en ? "Flip forward-back" : "İleri-geri ters", isOn: $alici.tersY)
                    Toggle(en ? "Flip scrolling" : "Kaydırma ters", isOn: $alici.tersKaydir)
                }
                .padding(.top, 4)
            }

            Picker(selection: Binding(get: { Dil(rawValue: dil) ?? .sistem }, set: { dil = $0.rawValue })) {
                ForEach(Dil.allCases) { Text($0.ad).tag($0) }
            } label: {
                Label(en ? "Language" : "Dil", systemImage: "globe")
            }
            .pickerStyle(.segmented)

            if alici.dinleyiciDurumu != "hazır" {
                Text((en ? "Network: " : "Ağ: ") + Metin.durum(alici.dinleyiciDurumu, en: en)).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(22)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { alici.pencereyiYerlestir() } }
    }
}

// Çekim için imlecin etrafında halka: tıklamaları kamerada görünür kılar. Tıklanmaz pencere, imleci izler.
// Sol tık sarı, sağ tık mavi parlar; düğme basılı tutulurken (sürükleme) içi dolu kalır.
@MainActor
final class ImlecHalkasi {
    private let boyut: CGFloat = 84
    private let pencere: NSPanel
    private let cember = CAShapeLayer()
    private let dolgu = CAShapeLayer()
    private var zamanlayici: Timer?
    private var gorunur = false

    init() {
        pencere = NSPanel(contentRect: NSRect(x: 0, y: 0, width: boyut, height: boyut),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pencere.isOpaque = false
        pencere.backgroundColor = .clear
        pencere.hasShadow = false
        pencere.ignoresMouseEvents = true
        pencere.level = .screenSaver
        pencere.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let gorunum = NSView(frame: NSRect(x: 0, y: 0, width: boyut, height: boyut))
        gorunum.wantsLayer = true
        let yol = CGPath(ellipseIn: CGRect(x: 10, y: 10, width: boyut - 20, height: boyut - 20), transform: nil)
        for katman in [dolgu, cember] {
            katman.frame = gorunum.bounds
            katman.path = yol
            gorunum.layer?.addSublayer(katman)
        }
        dolgu.fillColor = NSColor.clear.cgColor
        cember.fillColor = NSColor.clear.cgColor
        cember.strokeColor = NSColor.systemYellow.withAlphaComponent(0.95).cgColor
        cember.lineWidth = 5
        cember.shadowColor = NSColor.black.cgColor
        cember.shadowOpacity = 0.6
        cember.shadowRadius = 3
        cember.shadowOffset = .zero
        pencere.contentView = gorunum
    }

    func goster(_ acik: Bool) {
        guard acik != gorunur else { return }
        gorunur = acik
        if acik {
            tasi()
            pencere.orderFrontRegardless()
            let z = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tasi() }
            }
            RunLoop.main.add(z, forMode: .common)
            zamanlayici = z
        } else {
            zamanlayici?.invalidate()
            zamanlayici = nil
            pencere.orderOut(nil)
        }
    }

    func tik(sag: Bool) {
        let renk = (sag ? NSColor.systemCyan : NSColor.systemYellow)
        let parla = CABasicAnimation(keyPath: "fillColor")
        parla.fromValue = renk.withAlphaComponent(0.7).cgColor
        parla.toValue = NSColor.clear.cgColor
        parla.duration = 0.45
        dolgu.add(parla, forKey: "parla")
        let buyu = CABasicAnimation(keyPath: "transform.scale")
        buyu.fromValue = 0.7
        buyu.toValue = 1.0
        buyu.duration = 0.25
        cember.add(buyu, forKey: "buyu")
        cember.strokeColor = renk.withAlphaComponent(0.95).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.cember.strokeColor = NSColor.systemYellow.withAlphaComponent(0.95).cgColor
        }
    }

    func basili(_ basili: Bool) {
        dolgu.fillColor = basili ? NSColor.systemYellow.withAlphaComponent(0.4).cgColor : NSColor.clear.cgColor
    }

    private func tasi() {
        let p = NSEvent.mouseLocation
        pencere.setFrameOrigin(NSPoint(x: p.x - boyut / 2, y: p.y - boyut / 2))
    }
}

// Telefonun son birkaç saniyelik yolu: pencereye sığdırılmış çizgi, uçta nokta
private struct YolCizimi: View {
    let yol: [CGPoint]

    var body: some View {
        Canvas { ctx, boyut in
            guard let son = yol.last else { return }
            let xs = yol.map(\.x), ys = yol.map(\.y)
            let genislik = max((xs.max()! - xs.min()!), 20), yukseklik = max((ys.max()! - ys.min()!), 20)
            let olcek = min((boyut.width - 40) / genislik, (boyut.height - 40) / yukseklik, 4)
            let orta = CGPoint(x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
            func ekranda(_ p: CGPoint) -> CGPoint {
                CGPoint(x: boyut.width / 2 + (p.x - orta.x) * olcek, y: boyut.height / 2 - (p.y - orta.y) * olcek)
            }
            var cizgi = Path()
            cizgi.move(to: ekranda(yol[0]))
            for p in yol.dropFirst() { cizgi.addLine(to: ekranda(p)) }
            ctx.stroke(cizgi, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            let uc = ekranda(son)
            ctx.fill(Path(ellipseIn: CGRect(x: uc.x - 6, y: uc.y - 6, width: 12, height: 12)), with: .color(.accentColor))
        }
    }
}
