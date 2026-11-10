import MediaPlayer
import SwiftUI

// iPhone fare ekranı: ayarlar → başlat. Ters modda ekran masaya bakar (siyah durum ekranı),
// düz modda ekran farenin üstü olur: üstte sol/sağ düğme ve kaydırma şeridi, altı avuç yeri (dokunma sayılmaz).
// Touchpad modunda bütün ekran Mac trackpad'i gibi dokunma yüzeyi.
struct FareView: View {
    @ObservedObject var fare: FareController
    @AppStorage(Metin.anahtar) private var dil = ""
    private var en: Bool { Metin.ingilizce(dil) }

    var body: some View {
        ZStack {
            // Gizli ses kaydırıcısı: ses tuşları fare düğmesi olunca iOS'un ses göstergesi çıkmasın
            GizliSesKaydirici { fare.sesKaydirici = $0 }
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            if fare.calisiyor {
                switch fare.mod {
                case .kamera: TersEkran(fare: fare)
                case .sensor: if fare.sensorTers { TersEkran(fare: fare) } else { FareYuzeyi(fare: fare) }
                case .touchpad: TouchpadEkrani(fare: fare)
                }
            } else {
                ayarlar
            }
        }
        .navigationTitle(en ? Metin.uygulamaAdi.en : Metin.uygulamaAdi.tr)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AyarlarEkrani()
                } label: {
                    Image(systemName: "gearshape").accessibilityLabel(en ? "Settings" : "Ayarlar")
                }
            }
        }
        .toolbar(fare.calisiyor ? .hidden : .visible, for: .navigationBar)
        .navigationBarBackButtonHidden(fare.calisiyor)
        .statusBarHidden(fare.calisiyor)
        .persistentSystemOverlays(fare.calisiyor ? .hidden : .automatic)
        .onAppear { fare.agiBaslat() }
        .onDisappear {
            fare.durdur()
            fare.agiDurdur()
        }
    }

    private var modAciklamasi: String {
        switch fare.mod {
        case .kamera:
            return en
                ? "Lay it face-down, top edge pointing forward. The back camera sees the ceiling and works out where the phone is. Left click: volume up or tap the back of the phone. Right click: volume down. Don't cover the camera, hold the lower half. Keep the lights on."
                : "Ekran masaya gelecek şekilde ters koy, üst kenar ileri baksın. Arka kamera tavanı görür, telefonun yerini oradan bulur. Sol tık: ses açma tuşu ya da telefonun sırtına parmakla vur. Sağ tık: ses kısma tuşu. Kamerayı elinle kapatma, telefonu alt yarısından tut. Işık açık olsun."
        case .sensor:
            return en
                ? "Lay it flat, screen up. Only the accelerometer tracks the movement. The top of the screen is the left and right button, the middle strip scrolls. The volume buttons click too. Your palm can rest on the lower half."
                : "Ekran yukarı, düz koy. Yer değişimini sadece ivme sensörü hesaplar. Ekranın üstü sol ve sağ düğme, ortadaki şerit kaydırma. Ses tuşları da sol ve sağ tık. Avucun ekranın alt yarısında durabilir."
        case .touchpad:
            return en
                ? "The screen becomes the Mac's trackpad. Slide one finger: the cursor moves. Tap: left click, tap twice: double click. Two-finger tap: right click. Two-finger slide: scroll. Tap, then tap again and drag: drag and drop. The volume buttons click too. Portrait or landscape both work; held at an angle it turns by itself, lying flat press Rotate."
                : "Ekran Mac'in trackpad'i olur. Tek parmakla kaydır: imleç gider. Dokun: sol tık, iki kere dokun: çift tık. İki parmakla dokun: sağ tık. İki parmakla kaydır: sayfa kayar. Dokun, hemen tekrar dokunup sürükle: tutup taşır. Ses tuşları da sol ve sağ tık. Dikey de yatay da tutabilirsin, elinde eğik tutunca kendisi anlar; masada düz yatıyorsa Döndür'e bas."
        }
    }

    private var ayarlar: some View {
        Form {
            Section {
                Picker(en ? "Mode" : "Nasıl", selection: $fare.mod) {
                    ForEach(FareController.Mod.allCases) { Text($0.ad(en: en)).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(modAciklamasi)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if fare.mod == .sensor {
                    Toggle(en ? "Face-down (screen on the desk)" : "Ters koy (ekran masada)", isOn: $fare.sensorTers)
                    Text(en ? "If the camera bump stops the phone lying flat screen-up: turn it over so the screen lies flat on the desk. Click with the volume buttons." : "Kameralar yüzünden telefon ekran yukarıyken düz durmuyorsa: ters koy, ekranı masaya dümdüz yatsın. Tık ses tuşlarıyla.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Mac") {
                if let mac = fare.mac {
                    Label(mac.ad, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if !mac.acik { Text(en ? "The mouse is switched off on the Mac. Turn it on in the iPhone Mouse window." : "Mac'te fare kapalı. iPhone Fare penceresinden aç.").foregroundStyle(.orange) }
                    if !mac.izin {
                        Text(en ? "No Accessibility permission on the Mac: the cursor moves but clicks don't work. Allow it in the iPhone Mouse window." : "Mac'te Erişilebilirlik izni yok: imleç oynar ama tıklama olmaz. iPhone Fare penceresinden izin ver.")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label(en ? "Looking for the Mac…" : "Mac aranıyor…", systemImage: "magnifyingglass")
                    Text(en ? "Open the iPhone Mouse app on the Mac. Both must be on the same Wi-Fi." : "Mac'te iPhone Fare uygulamasını aç. İkisi aynı Wi-Fi'da olsun.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    fare.baslat()
                } label: {
                    Label(en ? "Start" : "Başlat", systemImage: "computermouse.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text(en ? "Lifting or turning the phone stops the cursor. To stop, pick the phone up and press Stop on the screen." : "Telefonu kaldırınca ya da çevirince imleç durur. Durdurmak için telefonu eline al, ekrandaki Durdur'a bas.")
            }
        }
    }
}

// Ters mod: ekran masada, kimse görmüyor. Telefonu eline alıp çevirince Durdur görünür.
private struct TersEkran: View {
    @ObservedObject var fare: FareController
    @AppStorage(Metin.anahtar) private var dil = ""
    private var en: Bool { Metin.ingilizce(dil) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "computermouse.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.8))
                Text(Metin.durum(fare.durum, en: en)).font(.title2.bold()).foregroundStyle(.white)
                Text(fare.mod == .kamera
                     ? (en ? "\(fare.nokta) ceiling points · \(fare.tikSayisi) left, \(fare.sagTikSayisi) right clicks"
                           : "Tavanda \(fare.nokta) iz noktası · \(fare.tikSayisi) sol, \(fare.sagTikSayisi) sağ tık")
                     : (en ? "Sensor, face-down · \(fare.tikSayisi) left, \(fare.sagTikSayisi) right clicks"
                           : "Sensör, ters · \(fare.tikSayisi) sol, \(fare.sagTikSayisi) sağ tık"))
                    .font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Text(fare.mac.map { "Mac: \($0.ad)" } ?? (en ? "Looking for the Mac…" : "Mac aranıyor…"))
                    .font(.callout).foregroundStyle(fare.mac == nil ? .orange : .green)
                if !fare.dogruDuruyor {
                    Button(en ? "Stop" : "Durdur") { fare.durdur() }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                        .padding(.top, 20)
                }
            }
            .padding(30)
        }
    }
}

// Düz mod: farenin üstü
private struct FareYuzeyi: View {
    @ObservedObject var fare: FareController
    @AppStorage(Metin.anahtar) private var dil = ""
    private var en: Bool { Metin.ingilizce(dil) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    FareDugmesi(ad: en ? "Left" : "Sol", basili: fare.sol) { fare.dugme(sol: true, basili: $0) }
                    KaydirmaSeridi { fare.kaydir($0) }
                        .frame(width: 70)
                    FareDugmesi(ad: en ? "Right" : "Sağ", basili: fare.sag) { fare.dugme(sol: false, basili: $0) }
                }
                .frame(height: geo.size.height * 0.42)

                // Avuç yeri: dokunmalar boşa gider
                VStack(spacing: 10) {
                    Spacer()
                    Text(Metin.durum(fare.durum, en: en)).font(.title3.bold()).foregroundStyle(.white.opacity(0.7))
                    Text(fare.mac.map { "Mac: \($0.ad)" } ?? (en ? "Looking for the Mac…" : "Mac aranıyor…"))
                        .font(.callout).foregroundStyle(fare.mac == nil ? .orange : .green.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
            }
            .padding(6)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .defersSystemGestures(on: .all)   // avuç alt kenara değince ana ekrana atmasın
        .overlay {
            if !fare.dogruDuruyor {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text(en ? "Lay it flat to continue" : "Düz koyunca devam eder").font(.title3).foregroundStyle(.white)
                        Button(en ? "Stop" : "Durdur") { fare.durdur() }
                            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                    }
                }
            }
        }
    }
}

private struct FareDugmesi: View {
    let ad: String
    let basili: Bool
    let degisti: (Bool) -> Void
    @State private var dokunuyor = false

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(basili ? 0.42 : 0.12))
            .overlay(Text(ad).font(.title2.bold()).foregroundStyle(.white.opacity(0.6)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !dokunuyor {
                            dokunuyor = true
                            degisti(true)
                        }
                    }
                    .onEnded { _ in
                        dokunuyor = false
                        degisti(false)
                    }
            )
    }
}

// Tekerlek yerine şerit: parmağı aşağı çekince sayfa aşağı gelir (iPhone'daki gibi)
private struct KaydirmaSeridi: View {
    let kaydir: (Double) -> Void
    @State private var son: CGFloat = 0

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.08))
            .overlay(
                VStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { _ in
                        Capsule().fill(Color.white.opacity(0.25)).frame(width: 30, height: 4)
                    }
                }
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { deger in
                        let fark = deger.translation.height - son
                        son = deger.translation.height
                        if fark != 0 { kaydir(Double(fark)) }
                    }
                    .onEnded { _ in son = 0 }
            )
    }
}

// Touchpad: bütün ekran dokunma yüzeyi. Üstte durum ve Durdur, parmakların altında halka (çekimde görünsün).
private struct TouchpadEkrani: View {
    @ObservedObject var fare: FareController
    @AppStorage(Metin.anahtar) private var dil = ""
    private var en: Bool { Metin.ingilizce(dil) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Canvas { c, boyut in   // hafif nokta ızgarası: yüzey olduğu belli olsun
                let adim: CGFloat = 28
                var y = adim / 2
                while y < boyut.height {
                    var x = adim / 2
                    while x < boyut.width {
                        c.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(.white.opacity(0.09)))
                        x += adim
                    }
                    y += adim
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // Kullanıcının "yukarısı": telefon yatay tutulunca ok döner
            VStack(spacing: 6) {
                Image(systemName: "arrow.up").font(.system(size: 54, weight: .bold))
                Text(en ? "up" : "yukarı").font(.caption.bold())
            }
            .foregroundStyle(.white.opacity(0.12))
            .rotationEffect(.degrees(fare.touchpadYonu == .dikey ? 0 : (fare.touchpadYonu == .yatayUstSolda ? 90 : -90)))
            .animation(.easeInOut(duration: 0.25), value: fare.touchpadYonu)
            .allowsHitTesting(false)
            DokunmaYuzeyi { tur, id, konum, t in fare.dokunma(tur, id: id, konum: konum, t: t) }
                .ignoresSafeArea()
            VStack {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fare.mac.map { "Mac: \($0.ad)" } ?? (en ? "Looking for the Mac…" : "Mac aranıyor…"))
                            .font(.callout).foregroundStyle(fare.mac == nil ? .orange : .green.opacity(0.8))
                        Text(en ? "\(Metin.durum(fare.durum, en: true)) · \(fare.tikSayisi) left, \(fare.sagTikSayisi) right clicks"
                             : "\(fare.durum) · \(fare.tikSayisi) sol, \(fare.sagTikSayisi) sağ tık")
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    }
                    .allowsHitTesting(false)
                    Spacer()
                    Button {
                        fare.touchpadDondur()
                    } label: {
                        Label(en ? (fare.touchpadYonu == .dikey ? "portrait" : "landscape") : fare.touchpadYonu.ad, systemImage: "rotate.right")
                    }
                    .buttonStyle(.bordered).tint(.white)
                    Button(en ? "Stop" : "Durdur") { fare.durdur() }
                        .buttonStyle(.bordered).tint(.red)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                Spacer()
            }
        }
        .defersSystemGestures(on: .all)   // kenardan kaydırınca ana ekrana ya da bildirimlere gitmesin
    }
}

// Çoklu dokunmayı SwiftUI hareketleriyle ayırmak zor; parmakları UIKit'ten tek tek alıyoruz
private struct DokunmaYuzeyi: UIViewRepresentable {
    let olay: (FareController.Dokunma, Int, CGPoint, TimeInterval) -> Void

    func makeUIView(context: Context) -> DokunmaGorunumu {
        let g = DokunmaGorunumu()
        g.olay = olay
        return g
    }

    func updateUIView(_ g: DokunmaGorunumu, context: Context) { g.olay = olay }
}

final class DokunmaGorunumu: UIView {
    var olay: ((FareController.Dokunma, Int, CGPoint, TimeInterval) -> Void)?
    private var halkalar: [ObjectIdentifier: CAShapeLayer] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            let halka = CAShapeLayer()
            halka.path = UIBezierPath(ovalIn: CGRect(x: -36, y: -36, width: 72, height: 72)).cgPath
            halka.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
            halka.strokeColor = UIColor.white.withAlphaComponent(0.55).cgColor
            halka.lineWidth = 2
            yerlestir(halka, t.location(in: self))
            layer.addSublayer(halka)
            halkalar[id] = halka
            olay?(.basladi, id.hashValue, t.location(in: self), t.timestamp)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            if let halka = halkalar[id] { yerlestir(halka, t.location(in: self)) }
            olay?(.kaydi, id.hashValue, t.location(in: self), t.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { bitir(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { bitir(touches) }

    private func bitir(_ touches: Set<UITouch>) {
        for t in touches {
            let id = ObjectIdentifier(t)
            halkalar.removeValue(forKey: id)?.removeFromSuperlayer()
            olay?(.bitti, id.hashValue, t.location(in: self), t.timestamp)
        }
    }

    private func yerlestir(_ halka: CALayer, _ p: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halka.position = p
        CATransaction.commit()
    }
}

// MPVolumeView ekranda durdukça iOS ses göstergesini göstermez; içindeki kaydırıcı sistem sesini değiştirebilir
private struct GizliSesKaydirici: UIViewRepresentable {
    let hazir: (UISlider) -> Void

    func makeUIView(context: Context) -> MPVolumeView {
        let gorunum = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        bul(gorunum, deneme: 0)
        return gorunum
    }

    // Kaydırıcı MPVolumeView'in içine geç ve bazen daha derine konuyor: bulunana kadar birkaç kez, iç içe ara
    private func bul(_ gorunum: MPVolumeView, deneme: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (deneme == 0 ? 0 : 0.25)) {
            func ara(_ v: UIView) -> UISlider? {
                if let s = v as? UISlider { return s }
                for alt in v.subviews { if let s = ara(alt) { return s } }
                return nil
            }
            if let kaydirici = ara(gorunum) { hazir(kaydirici) } else if deneme < 8 { bul(gorunum, deneme: deneme + 1) }
        }
    }

    func updateUIView(_ gorunum: MPVolumeView, context: Context) {}
}
