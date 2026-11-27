import CoreGraphics

/// Where Notification Center's host window goes back to after Gzyms parked it. NC sizes the host to one display and
/// moves it itself when the displays change (a lid, a monitor), so a saved place holds only while its size does.
public enum NCHome {
    /// nil = leave it: NC already put it somewhere. `screens` in Accessibility coordinates (top-left origin).
    public static func target(parked: Bool, size: CGSize?, home: CGPoint, homeSize: CGSize?, screens: [CGRect]) -> CGPoint? {
        guard parked else { return nil }
        guard let size, size != homeSize else { return home }
        return screens.first { $0.size == size }?.origin ?? home
    }
}
