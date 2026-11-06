import SwiftUI
import UIKit

/// Jetons du design system Growtin'.
///
/// Principes :
/// - le contenu reste sur des surfaces opaques et lisibles ;
/// - Liquid Glass est réservé à la couche de navigation et aux contrôles flottants (barre d'onglets,
///   barres d'outils, boutons d'action principaux), conformément aux Human Interface Guidelines ;
/// - toutes les tailles de texte suivent Dynamic Type.
enum GT {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let card: CGFloat = 24
        static let control: CGFloat = 18
        static let small: CGFloat = 12
    }

    enum Motion {
        static let standard = Animation.smooth(duration: 0.35)
        static let snappy = Animation.snappy(duration: 0.25)

        /// Animation désactivée lorsque l'utilisateur a activé « Réduire les animations ».
        static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }
}

extension Color {
    /// Encre principale : noir en mode clair, blanc en mode sombre (identité héritée de la web app).
    static let gtInk = Color(uiColor: .label)
    /// Vert « croissance », réservé aux bénéfices et aux éléments positifs.
    static let gtGrowth = Color(light: 0x14864F, dark: 0x3DD68C)
    /// Ambre de l'anneau de régularité.
    static let gtRegularity = Color(light: 0xD97706, dark: 0xFBBF24)
    /// Rouge doux des alertes de santé.
    static let gtAlert = Color(light: 0xC2410C, dark: 0xFB923C)
    static let gtBackground = Color(uiColor: .systemGroupedBackground)
    static let gtSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let gtSurfaceRaised = Color(uiColor: .tertiarySystemGroupedBackground)
    static let gtSeparator = Color(uiColor: .separator)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Font {
    /// Sur-titre en petites capitales espacées (« MA JOURNÉE », « GROWTIN' »).
    static let gtEyebrow = Font.caption.weight(.semibold)
}

extension View {
    func gtEyebrowStyle() -> some View {
        font(.gtEyebrow)
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}
