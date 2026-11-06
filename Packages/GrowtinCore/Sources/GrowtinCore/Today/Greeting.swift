import Foundation

public enum Greeting {
    /// Salutation selon l'heure, avec le prénom s'il a été donné.
    public static func text(name: String?, date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let base: String
        switch hour {
        case 5..<12: base = "Bonjour"
        case 12..<18: base = "Bon après-midi"
        default: base = "Bonsoir"
        }
        guard let name, !name.isEmpty else { return base }
        return "\(base), \(name)"
    }
}
