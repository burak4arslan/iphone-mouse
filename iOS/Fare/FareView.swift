import MediaPlayer
import SwiftUI

// iPhone fare ekranı: ayarlar → başlat. Ters modda ekran masaya bakar (siyah durum ekranı),
// düz modda ekran farenin üstü olur: üstte sol/sağ düğme ve kaydırma şeridi, altı avuç yeri (dokunma sayılmaz).
// Touchpad modunda bütün ekran Mac trackpad'i gibi dokunma yüzeyi.
struct FareView: View {
    @ObservedObject var fare: FareController

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
        .navigationTitle("iPhone fare")
        .navigationBarTitleDisplayMode(.inline)
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
            return "Ekran masaya gelecek şekilde ters koy, üst kenar ileri baksın. Arka kamera tavanı görür, telefonun yerini oradan bulur. Sol tık: ses açma tuşu ya da telefonun sırtına parmakla vur. Sağ tık: ses kısma tuşu. Kamerayı elinle kapatma, telefonu alt yarısından tut. Işık açık olsun."
        case .sensor:
            return "Ekran yukarı, düz koy. Yer değişimini sadece ivme sensörü hesaplar. Ekranın üstü sol ve sağ düğme, ortadaki şerit kaydırma. Ses tuşları da sol ve sağ tık. Avucun ekranın alt yarısında durabilir."
        case .touchpad:
            return "Ekran Mac'in trackpad'i olur. Tek parmakla kaydır: imleç gider. Dokun: sol tık, iki kere dokun: çift tık. İki parmakla dokun: sağ tık. İki parmakla kaydır: sayfa kayar. Dokun, hemen tekrar dokunup sürükle: tutup taşır. Ses tuşları da sol ve sağ tık. Dikey de yatay da tutabilirsin, elinde eğik tutunca kendisi anlar; masada düz yatıyorsa Döndür'e bas."
        }
    }

    private var ayarlar: some View {
        Form {
            Section {
                Picker("Nasıl", selection: $fare.mod) {
                    ForEach(FareController.Mod.allCases) { Text($0.ad).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(modAciklamasi)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if fare.mod == .sensor {
                    Toggle("Ters koy (ekran masada)", isOn: $fare.sensorTers)
                    Text("Kameralar yüzünden telefon ekran yukarıyken düz durmuyorsa: ters koy, ekranı masaya dümdüz yatsın. Tık ses tuşlarıyla.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Mac") {
                if let mac = fare.mac {
                    Label(mac.ad, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if !mac.acik { Text("Mac'te fare kapalı. iPhone Fare penceresinden aç.").foregroundStyle(.orange) }
                    if !mac.izin {
                        Text("Mac'te Erişilebilirlik izni yok: imleç oynar ama tıklama olmaz. iPhone Fare penceresinden izin ver.")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label("Mac aranıyor…", systemImage: "magnifyingglass")
                    Text("Mac'te iPhone Fare uygulamasını aç. İkisi aynı Wi-Fi'da olsun.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    fare.baslat()
                } label: {
                    Label("Başlat", systemImage: "computermouse.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text("Telefonu kaldırınca ya da çevirince imleç durur. Durdurmak için telefonu eline al, ekrandaki Durdur'a bas.")
            }
        }
    }
}

// Ters mod: ekran masada, kimse görmüyor. Telefonu eline alıp çevirince Durdur görünür.
private struct TersEkran: View {
    @ObservedObject var fare: FareController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "computermouse.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.8))
                Text(fare.durum).font(.title2.bold()).foregroundStyle(.white)
                Text(fare.mod == .kamera ? "Tavanda \(fare.nokta) iz noktası · \(fare.tikSayisi) sol, \(fare.sagTikSayisi) sağ tık"
                     : "Sensör, ters · \(fare.tikSayisi) sol, \(fare.sagTikSayisi) sağ tık")
                    .font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Text(fare.mac.map { "Mac: \($0.ad)" } ?? "Mac aranıyor…")
                    .font(.callout).foregroundStyle(fare.mac == nil ? .orange : .green)
                if !fare.dogruDuruyor {
                    Button("Durdur") { fare.durdur() }
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

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    FareDugmesi(ad: "Sol", basili: fare.sol) { fare.dugme(sol: true, basili: $0) }
                    KaydirmaSeridi { fare.kaydir($0) }
                        .frame(width: 70)
                    FareDugmesi(ad: "Sağ", basili: fare.sag) { fare.dugme(sol: false, basili: $0) }
                }
                .frame(height: geo.size.height * 0.42)

                // Avuç yeri: dokunmalar boşa gider
                VStack(spacing: 10) {
                    Spacer()
                    Text(fare.durum).font(.title3.bold()).foregroundStyle(.white.opacity(0.7))
                    Text(fare.mac.map { "Mac: \($0.ad)" } ?? "Mac aranıyor…")
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
                        Text("Düz koyunca devam eder").font(.title3).foregroundStyle(.white)
                        Button("Durdur") { fare.durdur() }
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
                Text("yukarı").font(.caption.bold())
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
                        Text(fare.mac.map { "Mac: \($0.ad)" } ?? "Mac aranıyor…")
                            .font(.callout).foregroundStyle(fare.mac == nil ? .orange : .green.opacity(0.8))
                        Text("\(fare.durum) · \(fare.tikSayisi) sol, \(fare.sagTikSayisi) sağ tık")
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    }
                    .allowsHitTesting(false)
                    Spacer()
                    Button {
                        fare.touchpadDondur()
                    } label: {
                        Label(fare.touchpadYonu.ad, systemImage: "rotate.right")
                    }
                    .buttonStyle(.bordered).tint(.white)
                    Button("Durdur") { fare.durdur() }
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
