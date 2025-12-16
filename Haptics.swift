import Foundation
import UIKit

/// Global haptics utility for feedback across the app.
enum Haptics {
    /// Call when the user selects a wrong answer during the quiz.
    static func wrongAnswer() {
        if #available(iOS 16.0, *) {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.error)
        } else {
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.impactOccurred()
        }
    }

    /// Optional: call for correct answers if you want a subtle success tap.
    static func correctAnswer() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }
}
