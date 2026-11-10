import SwiftUI

// iPhone Fare: telefonu Mac'in faresine çevirir. Üç yol: Ters (kamera), Touchpad, Düz (sensör). Mac tarafı Mac/.
@main
struct IPhoneFareApp: App {
    @StateObject private var fare = FareController()

    var body: some Scene {
        WindowGroup {
            NavigationStack { FareView(fare: fare) }
        }
    }
}
