import Foundation

/// CascableCore licence loader.
///
/// The licence bytes are intentionally not committed. Place the issued
/// `CascableCoreLicense.licence` file in the Runner bundle for a demo build.
/// Missing/empty data fails closed and is never logged.
enum CascableCoreLicense {
    static var data: Data {
        guard let url = Bundle.main.url(forResource: "CascableCoreLicense", withExtension: "licence") else {
            return Data()
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    static var isConfigured: Bool {
        !data.isEmpty
    }
}
