import Foundation

/// Fixed legal strings, in one place so the App Store description, the About screen
/// and the purchase screen never drift.
enum Legal {

    /// Nominative-use disclaimer. Brand names appear in LensBeacon only to say which
    /// products a Bluetooth signature resembles; there is no affiliation, no
    /// endorsement, and no use of any logo or trade dress.
    static let nonAffiliation = """
    LensBeacon is not affiliated with, authorised, sponsored, or endorsed by Meta \
    Platforms, EssilorLuxottica, Ray-Ban, Oakley, Snap Inc., or Even Realities. \
    Product names are used only to describe the Bluetooth signatures LensBeacon \
    looks for.
    """

    /// Apple's standard EULA — the default Terms of Use for an app that ships no
    /// custom agreement (App Review guideline 3.1.2 / EULA requirement).
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
