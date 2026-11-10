import ARKit
import AVFoundation
import CoreMotion
import MediaPlayer
import Network
import UIKit

// iPhone fare (deneme): telefonu masada kaydırınca Mac'in imleci gider. İki yol:
// - Ters (kamera): ekran masada, arka kamera tavana bakar. ARKit tavana göre telefonun yerini bulur.
// - Düz (sensör): ekran yukarı. Yer değişimi sadece ivme sensöründen. Ekranın üstü sol/sağ düğme, ortası kaydırma.
// - Touchpad: telefon ekranı Mac trackpad'i gibi (TouchpadIzleyici). Hareket sensörü ve kamera kapalı.
// Üç modda da ses tuşları fare düğmesi: + sol tık, − sağ tık. Ters modda sırtına vurmak da sol tık.
// Hesap FareIzleyici.swift'te, paket FareProtokol.swift'te, Mac tarafı Mac/.
@MainActor
final class FareController: NSObject, ObservableObject {
    enum Mod: String, CaseIterable, Identifiable {
        case kamera, sensor, touchpad
        var id: String { rawValue }
        var ad: String {
            switch self {
            case .kamera: return "Ters (kamera)"
            case .sensor: return "Düz (sensör)"
            case .touchpad: return "Touchpad"
            }
        }
    }

    @Published var mod: Mod = .kamera
    @Published private(set) var calisiyor = false
    @Published private(set) var mac: FareCevabi?
    @Published private(set) var durum = ""
    @Published private(set) var nokta = 0
    @Published private(set) var dogruDuruyor = false   // ters modda ekran aşağı, düz modda yukarı; ikisinde de düz
    @Published private(set) var tikSayisi: UInt32 = 0
    @Published private(set) var sagTikSayisi: UInt32 = 0
    @Published private(set) var sol = false
    @Published private(set) var sag = false
    @Published private(set) var touchpadYonu: TouchpadYonu = .dikey
    // Sensör modunda telefon ters (ekran masada): kamera çıkıntısı yüzünden ekran yukarıyken düz durmuyor (8 Kasım)
    @Published var sensorTers = UserDefaults.standard.bool(forKey: "fareSensorTers") {
        didSet { UserDefaults.standard.set(sensorTers, forKey: "fareSensorTers") }
    }

    private let agi = FareAgi()
    private let motion = CMMotionManager()
    private var session: ARSession?
    private var kamera = KameraIzleyici()
    private var sensor = SensorIzleyici()
    private var vurma = VurmaAlgilayici()
    private var touchpad = TouchpadIzleyici()
    private var tikZamanlayici: DispatchWorkItem?
    // Parmağın 1 noktası kaç metre: iPhone ekranında 1 pt ≈ 0,165 mm. Trackpad'de parmak az yol gider,
    // o yüzden 2,5 kat büyütülür (Mac'teki hassasiyet ve ivme bunun üstüne gelir).
    private let noktaMetre = 0.000165 * 2.5

    private var oturum: UInt32 = 0
    private var sira: UInt64 = 0
    private var kaydirma = 0.0
    private var tik: UInt32 = 0
    private var sagTik: UInt32 = 0
    private var vurmaKapaliBitis: TimeInterval = 0
    private var sesGozlem: NSKeyValueObservation?
    private var oncekiSes: Float?
    private var sonSes: Float?
    private var ortalamaBitis: TimeInterval = 0
    private var sesOturumuBizde = false
    private let ortaSes: Float = 0.5
    // Ekrandaki gizli MPVolumeView'in kaydırıcısı (FareView koyar): sistem sesini ortaya almak için
    weak var sesKaydirici: UISlider? {
        didSet { if calisiyor { sesiOrtala() } }
    }
    private var sonOrnek: TimeInterval?
    private var dondurmaBitis: TimeInterval = 0
    private var inisBitis: TimeInterval = 0
    private var sakinSure = 0.0
    private var arIz = "başlıyor"
    private var arGecerli = false
    private var vurmaTepe = 0.0
    private var vurmaTepeZamani: TimeInterval = 0
    private var arayuzSayac = 0
    private var sonCevap = Date.distantPast
    private var bakim: Timer?

    override init() {
        super.init()
        agi.cevapGeldi = { [weak self] cevap in
            MainActor.assumeIsolated { self?.cevapGeldi(cevap) }
        }
    }

    // Ekran açılınca Mac aranır; başlatmadan önce de "Mac bulundu" görünsün diye yarım saniyede bir selam gider
    func agiBaslat() {
        agi.baslat()
        guard bakim == nil else { return }
        bakim = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.bakimZamani() }
        }
    }

    func agiDurdur() {
        bakim?.invalidate()
        bakim = nil
        agi.durdur()
        mac = nil
    }

    func baslat() {
        guard !calisiyor, motion.isDeviceMotionAvailable else { return }
        oturum = UInt32.random(in: 1...UInt32.max)
        sira = 0
        kamera = KameraIzleyici()
        sensor = SensorIzleyici()
        vurma = VurmaAlgilayici()
        vurma.esik = mac?.vurmaEsigi ?? 0.15
        touchpad = TouchpadIzleyici()
        tikZamanlayici?.cancel()
        sol = false
        sag = false
        kaydirma = 0
        tik = 0
        tikSayisi = 0
        sagTik = 0
        sagTikSayisi = 0
        sonOrnek = nil
        sakinSure = 0
        arIz = "başlıyor"
        arGecerli = false
        calisiyor = true
        UIApplication.shared.isIdleTimerDisabled = true   // ekran kararırsa sensör ve kamera durur

        if mod == .touchpad {
            dogruDuruyor = true   // nasıl tutulursa tutulsun çalışır
            durum = durumMetni
            // Dikey mi yatay mı tutuluyor: yerçekiminden (ekran kilidinden bağımsız). Parmak ekrandayken yön değişmez.
            motion.deviceMotionUpdateInterval = 1.0 / 10
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated { self?.yonGuncelle(data.gravity) }
            }
        } else {
            motion.deviceMotionUpdateInterval = 1.0 / 100
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated { self?.ornek(data) }
            }
        }
        if mod == .kamera { kameraBaslat() }
        sesTuslariniBaslat()
    }

    func durdur() {
        guard calisiyor else { return }
        motion.stopDeviceMotionUpdates()
        tikZamanlayici?.cancel()
        tikZamanlayici = nil
        session?.pause()
        session = nil
        sol = false
        sag = false
        gonder(ProcessInfo.processInfo.systemUptime)   // Mac'te basılı kalan düğme bırakılsın
        calisiyor = false
        sesTuslariniDurdur()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Ses tuşları
    // iOS uygulamaya ses tuşu olayı vermiyor; sistem sesinin değişmesini izliyoruz. Her basıştan sonra ses yine ortaya
    // (8/16) alınır, yoksa en üstte ya da en altta tuş olayı gelmez. Ekrandaki gizli MPVolumeView yüzünden iOS'un ses
    // göstergesi çıkmaz. Uygulama hiç ses çalmaz; durunca ses başlamadan önceki seviyesine döner.
    private func sesTuslariniBaslat() {
        let oturum = AVAudioSession.sharedInstance()
        if oturum.category != .playback {   // başka bir uygulama ses çalıyorsa onun ses ayarına dokunma
            try? oturum.setCategory(.ambient, options: [.mixWithOthers])
            try? oturum.setActive(true)
            sesOturumuBizde = true
        }
        oncekiSes = oturum.outputVolume
        sonSes = oturum.outputVolume
        sesGozlem = oturum.observe(\.outputVolume, options: [.new]) { [weak self] _, degisim in
            guard let yeni = degisim.newValue else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.sesDegisti(yeni) }
            }
        }
        sesiOrtala()
    }

    private func sesTuslariniDurdur() {
        sesGozlem = nil
        if let onceki = oncekiSes { sesiAyarla(onceki) }
        oncekiSes = nil
        if sesOturumuBizde {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sesOturumuBizde = false
        }
    }

    // Yön, basmadan önceki sese göre: + sesi artırır, − azaltır. (Eskiden ortaya, 0,5'e göre bakılıyordu; ortalama
    // tutmayınca ses yarının altında kalıyor ve iki tuş da sağ tık oluyordu.) Bizim ortalamamızın yarattığı değişim tuş sayılmaz.
    private func sesDegisti(_ yeni: Float) {
        let onceki = sonSes ?? ortaSes
        sonSes = yeni
        let ts = ProcessInfo.processInfo.systemUptime
        if ts < ortalamaBitis && abs(yeni - ortaSes) < 0.02 { return }   // ortaya alışımız
        guard calisiyor, abs(yeni - onceki) > 0.01 else { return }
        if yeni > onceki {
            tik &+= 1
            tikSayisi = tik
        } else {
            sagTik &+= 1
            sagTikSayisi = sagTik
        }
        // Tuşa basarken telefon kıpırdar: o anki hareket atılır, sarsıntı vuruş sayılmaz
        dondurmaBitis = ts + 0.15
        vurmaKapaliBitis = ts + 0.4
        kamera.sabitle()
        sensor.durdur()
        gonder(ts)
        sesiOrtala()
    }

    // Sesi ortaya al ki en üstte/en altta tuş olayı kaybolmasın. İlk deneme bazen tutmuyor: kısa süre sonra bir kez daha.
    private func sesiOrtala() {
        ortalamaBitis = ProcessInfo.processInfo.systemUptime + 0.6
        sesiAyarla(ortaSes)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.calisiyor, let son = self.sonSes, abs(son - self.ortaSes) > 0.02 else { return }
            self.ortalamaBitis = ProcessInfo.processInfo.systemUptime + 0.6
            self.sesiAyarla(self.ortaSes)
        }
    }

    private func sesiAyarla(_ deger: Float) {
        guard let kaydirici = sesKaydirici else { return }
        kaydirici.setValue(deger, animated: false)
        kaydirici.sendActions(for: .valueChanged)
    }

    // Düz modda ekrandaki düğmeler. Dokunurken telefon sarsılır: o anki hareket atılır.
    func dugme(sol solMu: Bool, basili: Bool) {
        if solMu { sol = basili } else { sag = basili }
        let simdi = ProcessInfo.processInfo.systemUptime
        sensor.durdur()
        dondurmaBitis = simdi + 0.12
        gonder(simdi)
    }

    func kaydir(_ miktar: Double) {
        kaydirma += miktar
        gonder(ProcessInfo.processInfo.systemUptime)
    }

    // MARK: - Touchpad
    // Ekrandaki dokunma yüzeyi her parmak olayını buraya verir. t: dokunmanın zamanı (systemUptime ile aynı saat).
    enum Dokunma { case basladi, kaydi, bitti }

    func dokunma(_ tur: Dokunma, id: Int, konum: CGPoint, t: TimeInterval) {
        guard calisiyor, mod == .touchpad else { return }
        let k = touchpadYonu.cevir(SIMD2(Double(konum.x), Double(konum.y)))
        let olaylar: [TouchpadIzleyici.Olay]
        switch tur {
        case .basladi: olaylar = touchpad.basla(id: id, konum: k, t: t)
        case .kaydi: olaylar = touchpad.kay(id: id, konum: k, t: t)
        case .bitti: olaylar = touchpad.bitti(id: id, t: t)
        }
        uygula(olaylar)
        if tur == .bitti && touchpad.tikBekliyor { tikBekle() }
        gonder(t)
    }

    private func yonGuncelle(_ g: CMAcceleration) {
        guard touchpad.parmakSayisi == 0, let yeni = TouchpadYonu.yercekiminden(x: g.x, y: g.y), yeni != touchpadYonu else { return }
        touchpadYonu = yeni
    }

    // Masada düz yatarken yön yerçekiminden anlaşılmaz: ekrandaki düğmeyle elle çevrilir
    func touchpadDondur() {
        guard touchpad.parmakSayisi == 0 else { return }
        touchpadYonu = touchpadYonu.sonraki
    }

    // Tek dokunuşun tıkı, ikinci dokunuş gelmezse kısa süre sonra gider
    private func tikBekle() {
        tikZamanlayici?.cancel()
        let gorev = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.calisiyor else { return }
                let t = ProcessInfo.processInfo.systemUptime
                let olaylar = self.touchpad.zaman(t)
                if !olaylar.isEmpty {
                    self.uygula(olaylar)
                    self.gonder(t)
                } else if self.touchpad.tikBekliyor {
                    self.tikBekle()   // parmak hâlâ ekranda: karar o kalkınca
                }
            }
        }
        tikZamanlayici = gorev
        DispatchQueue.main.asyncAfter(deadline: .now() + touchpad.ciftAraligi + 0.01, execute: gorev)
    }

    private func uygula(_ olaylar: [TouchpadIzleyici.Olay]) {
        for olay in olaylar {
            switch olay {
            case .tik: tik &+= 1
            case .ciftTik: tik &+= 2
            case .sagTik:
                sagTik &+= 1
                sagTikSayisi = sagTik
            case .surukleBasla: sol = true
            case .surukleBitir: sol = false
            }
        }
        if tik != tikSayisi { tikSayisi = tik }
        let yeni = durumMetni
        if yeni != durum { durum = yeni }
    }

    // MARK: - Kamera (ARKit)

    private func kameraBaslat() {
        guard ARWorldTrackingConfiguration.isSupported else {
            arIz = "bu telefonda ARKit yok"
            return
        }
        let yeni = ARSession()
        yeni.delegate = self
        let ayar = ARWorldTrackingConfiguration()
        ayar.worldAlignment = .gravity
        if let bicim = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: { $0.framesPerSecond == 60 }) {
            ayar.videoFormat = bicim
        }
        yeni.run(ayar, options: [.resetTracking, .removeExistingAnchors])
        session = yeni
    }

    fileprivate func kare(konum: SIMD3<Double>, kx: SIMD3<Double>, ky: SIMD3<Double>, iz: ARCamera.TrackingState, nokta n: Int) {
        let (metin, gecerli) = Self.izMetni(iz)
        arIz = metin
        arGecerli = gecerli
        if arayuzSayac % 10 == 0 { nokta = n }
        // ARKit kamera ekseni: x telefonun üst kenarından alt kenarına, y portrede sağa, z ekrandan dışarı.
        // Ters yatınca (ekran masada, üst kenar ileri) kullanıcının sağı -y, ilerisi -x oluyor.
        kamera.ekle(konum: konum, sag: -ky, ileri: -kx, gecerli: gecerli && dogruDuruyor, sakin: sakinSure > 0.4)
    }

    private static func izMetni(_ iz: ARCamera.TrackingState) -> (String, Bool) {
        switch iz {
        case .normal: return ("izleme iyi", true)
        case .notAvailable: return ("izleme yok", false)
        case .limited(let sebep):
            switch sebep {
            case .initializing: return ("başlıyor", false)
            case .relocalizing: return ("yerini arıyor", false)
            case .insufficientFeatures: return ("tavanda iz az", true)
            case .excessiveMotion: return ("çok hızlı", true)
            @unknown default: return ("izleme sınırlı", true)
            }
        }
    }

    // MARK: - Hareket sensörü (100 Hz)

    private func ornek(_ veri: CMDeviceMotion) {
        let ts = veri.timestamp
        let dt = sonOrnek.map { min(max(ts - $0, 0.001), 0.05) } ?? 0.01
        sonOrnek = ts

        let g = veri.gravity
        let ua = veri.userAcceleration   // g, yerçekimi çıkmış, telefonun ekseninde
        let r = veri.rotationRate
        let donus = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        let yatay = (ua.x * ua.x + ua.y * ua.y).squareRoot()

        let ekranAsagi = mod == .kamera || (mod == .sensor && sensorTers)
        let duz = ekranAsagi ? g.z > 0.93 : g.z < -0.93
        if duz != dogruDuruyor { dogruDuruyor = duz }
        sakinSure = (yatay < 0.01 && abs(ua.z) < 0.02 && donus < 0.05) ? sakinSure + dt : 0

        switch mod {
        case .kamera:
            if kamera.havada || !duz { inisBitis = ts + 0.35 }   // yere konarken çıkan sıçrama tık sayılmasın
            if vurma.ekle(z: ua.z, yatay: yatay, dt: dt), ts > inisBitis, ts > vurmaKapaliBitis {
                tik &+= 1
                tikSayisi = tik
                dondurmaBitis = ts + 0.15
            }
            if ts < dondurmaBitis { kamera.sabitle() }
        case .sensor:
            if duz && ts >= dondurmaBitis {
                // Düz yatınca (ekran yukarı, üst kenar ileri) kullanıcının sağı +x, ilerisi +y.
                // İşaret: iOS ham ivmeyi ters verir (masada dururken z = -1 g, sensörün ölçtüğü kuvvet ise yukarı),
                // userAcceleration = ham - yerçekimi olduğu için gerçek ivmenin tersi çıkıyor. Telefonda denenecek;
                // yanlışsa Mac'teki "ters çevir" düğmeleri düzeltir.
                // Ters yatınca (ekran masada, üst kenar yine ileri) telefon uzun ekseni etrafında dönmüş olur:
                // kullanıcının sağı cihazın -x'i, ilerisi yine +y.
                let ivme = sensorTers ? SIMD2(ua.x, -ua.y) : -SIMD2(ua.x, ua.y)
                sensor.ekle(ivme: ivme * 9.81, donus: donus, dt: dt)
            } else {
                sensor.durdur()
            }
        case .touchpad:
            return   // bu modda hareket sensörü açılmıyor
        }

        if ts - vurmaTepeZamani > 0.5 {
            vurmaTepe = vurma.tepeyiOku()
            vurmaTepeZamani = ts
        }
        gonder(ts)

        arayuzSayac += 1
        if arayuzSayac % 10 == 0 {
            let yeni = durumMetni
            if yeni != durum { durum = yeni }
        }
    }

    private var durumMetni: String {
        switch mod {
        case .kamera:
            if !dogruDuruyor { return "telefonu ters çevir" }
            if kamera.havada { return "havada" }
            return arIz
        case .sensor:
            if !dogruDuruyor { return sensorTers ? "telefonu ters çevir" : "telefonu düz koy" }
            return sensor.hareketli ? "hareket" : "duruyor"
        case .touchpad:
            return touchpad.surukluyor ? "sürüklüyor" : "hazır"
        }
    }

    // MARK: - Ağ

    private func gonder(_ ts: TimeInterval) {
        let konum: SIMD2<Double>
        switch mod {
        case .kamera: konum = kamera.cikis
        case .sensor: konum = sensor.konum
        case .touchpad: konum = touchpad.hareket * noktaMetre
        }
        let kaydirma = mod == .touchpad ? self.kaydirma + touchpad.kaydirma : self.kaydirma
        sira += 1
        agi.gonder(FarePaketi(
            oturum: calisiyor ? oturum : 0, sira: sira, t: ts, mod: mod == .sensor && sensorTers ? "sensor-ters" : mod.rawValue, durum: durumMetni,
            x: konum.x, y: konum.y, sol: sol, sag: sag, kaydir: kaydirma, tik: tik, sagTik: sagTik,
            vurmaTepe: vurmaTepe, nokta: nokta))
    }

    private func bakimZamani() {
        // Selam (oturum 0: Mac imleci oynatmaz). Touchpad'de parmak durunca paket kesilir; Mac telefonu kaybetmesin
        // (kaybedince basılı düğmeyi bırakır) diye o modda da gider.
        if !calisiyor || mod == .touchpad { gonder(ProcessInfo.processInfo.systemUptime) }
        if mac != nil, Date().timeIntervalSince(sonCevap) > 3 {
            mac = nil
            agi.yenidenBaglan()   // Mac uygulaması kapanıp açıldıysa yeni portuna bağlan
        }
    }

    private func cevapGeldi(_ cevap: FareCevabi) {
        sonCevap = Date()
        if cevap.ad != mac?.ad || cevap.acik != mac?.acik || cevap.izin != mac?.izin || cevap.vurmaEsigi != mac?.vurmaEsigi {
            mac = cevap
        }
        vurma.esik = cevap.vurmaEsigi
    }
}

extension FareController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // ARFrame'i tutmadan değerleri al (ARKit kare havuzu tükenmesin)
        let t = frame.camera.transform
        let konum = SIMD3<Double>(Double(t.columns.3.x), Double(t.columns.3.y), Double(t.columns.3.z))
        let kx = SIMD3<Double>(Double(t.columns.0.x), Double(t.columns.0.y), Double(t.columns.0.z))
        let ky = SIMD3<Double>(Double(t.columns.1.x), Double(t.columns.1.y), Double(t.columns.1.z))
        let iz = frame.camera.trackingState
        let n = frame.rawFeaturePoints?.points.count ?? 0
        MainActor.assumeIsolated {
            self.kare(konum: konum, kx: kx, ky: ky, iz: iz, nokta: n)
        }
    }
}

// Bonjour ile Mac'i bulur, UDP ile paket yollar. Kendi kuyruğunda çalışır.
final class FareAgi: @unchecked Sendable {
    var cevapGeldi: ((FareCevabi) -> Void)?

    private let kuyruk = DispatchQueue(label: "fare.ag")
    private var tarayici: NWBrowser?
    private var baglanti: NWConnection?
    private var hedef: NWEndpoint?
    private let kodlayici = JSONEncoder()

    func baslat() {
        kuyruk.async {
            guard self.tarayici == nil else { return }
            let tarayici = NWBrowser(for: .bonjour(type: FareAg.servis, domain: nil), using: .udp)
            tarayici.browseResultsChangedHandler = { sonuclar, _ in
                let yeni = sonuclar.first?.endpoint
                if yeni != self.hedef {
                    self.hedef = yeni
                    self.baglan()
                }
            }
            tarayici.start(queue: self.kuyruk)
            self.tarayici = tarayici
        }
    }

    func yenidenBaglan() {
        kuyruk.async { self.baglan() }
    }

    func durdur() {
        kuyruk.async {
            self.tarayici?.cancel()
            self.tarayici = nil
            self.baglanti?.cancel()
            self.baglanti = nil
            self.hedef = nil
        }
    }

    func gonder(_ paket: FarePaketi) {
        kuyruk.async {
            guard let baglanti = self.baglanti, let veri = try? self.kodlayici.encode(paket) else { return }
            baglanti.send(content: veri, completion: .idempotent)
        }
    }

    private func baglan() {
        baglanti?.cancel()
        baglanti = nil
        guard let hedef else { return }
        let yeni = NWConnection(to: hedef, using: .udp)
        yeni.start(queue: kuyruk)
        baglanti = yeni
        dinle(yeni)
    }

    private func dinle(_ c: NWConnection) {
        c.receiveMessage { [weak self] veri, _, _, hata in
            guard let self, c === self.baglanti else { return }
            if let veri, let cevap = try? JSONDecoder().decode(FareCevabi.self, from: veri) {
                let geri = self.cevapGeldi
                DispatchQueue.main.async { geri?(cevap) }
            }
            if hata == nil { self.dinle(c) }
        }
    }
}
