import CoreImage
import Foundation

/// A 3D LUT from a .cube file, ready for Core Image: red changes fastest, then green, then blue.
struct CubeLUT {
    let size: Int
    let data: Data

    /// Reads a .cube file's 3D table. Returns nil for 1D tables or anything it can't read.
    static func parse(_ text: String) -> CubeLUT? {
        var size = 0
        var values: [Float] = []
        var minimum: [Float] = [0, 0, 0]
        var maximum: [Float] = [1, 1, 1]
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = parts.first else { continue }
            switch first.uppercased() {
            case "LUT_3D_SIZE":
                size = parts.count > 1 ? Int(String(parts[1])) ?? 0 : 0
            case "LUT_1D_SIZE":
                return nil
            case "DOMAIN_MIN":
                minimum = parts.dropFirst().compactMap { Float(String($0)) }
            case "DOMAIN_MAX":
                maximum = parts.dropFirst().compactMap { Float(String($0)) }
            case "TITLE", "LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE":
                continue
            default:
                let numbers = parts.compactMap { Float(String($0)) }
                if numbers.count == 3 {
                    values.append(contentsOf: numbers)
                }
            }
        }
        guard size >= 2, size <= 128, values.count == size * size * size * 3 else { return nil }
        if minimum.count == 3, maximum.count == 3, minimum != [0, 0, 0] || maximum != [1, 1, 1] {
            // Rare: outputs given in another range. Bring them back to 0...1.
            for i in 0..<values.count {
                let c = i % 3
                values[i] = (values[i] - minimum[c]) / max(maximum[c] - minimum[c], 0.0001)
            }
        }
        var rgba = [Float](repeating: 1, count: size * size * size * 4)
        for i in 0..<(size * size * size) {
            rgba[i * 4] = values[i * 3]
            rgba[i * 4 + 1] = values[i * 3 + 1]
            rgba[i * 4 + 2] = values[i * 3 + 2]
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return CubeLUT(size: size, data: data)
    }

    /// Applies the table to an image whose pixels are the camera's raw values (no colour management).
    func apply(to image: CIImage) -> CIImage {
        image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": size,
            "inputCubeData": data
        ])
    }

    /// The look that comes with the app: Apple Log to a normal-looking picture.
    static let standard: CubeLUT? = {
        guard let url = Bundle.main.url(forResource: "Standard", withExtension: "cube"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }()
}

/// A look to view Apple Log clips through: the Standard one, no look at all, or a .cube file you've added.
struct Look: Identifiable, Hashable {
    /// nil for the Standard look, `Look.asRecordedFile` for no look.
    let fileName: String?

    /// The choice saved for no look: the picture as it's recorded, flat Apple Log (1.24.2). It isn't a file name (no
    /// .cube on the end), so it can't clash with a look you add.
    static let asRecordedFile = "apple-log"
    static let standard = Look(fileName: nil)
    static let asRecorded = Look(fileName: asRecordedFile)

    var isAsRecorded: Bool { fileName == Look.asRecordedFile }
    /// Standard and no look come with the app, so they can't be deleted.
    var isBuiltIn: Bool { fileName == nil || isAsRecorded }

    var id: String { fileName ?? "standard" }
    var name: String {
        if isAsRecorded {
            return "Apple Log (no look)"
        }
        return fileName.map { ($0 as NSString).deletingPathExtension } ?? "Standard"
    }
}

/// The looks you can see Apple Log footage through, kept in On My iPhone › Shot Guide › Looks. Clips are
/// never changed by a look: it's what the camera and review screens show, and what graded copies use.
final class LookLibrary: ObservableObject {
    @Published private(set) var looks: [Look] = [.standard, .asRecorded]
    @Published var selectedFile: String? {
        didSet {
            UserDefaults.standard.set(selectedFile, forKey: Self.selectedKey)
            LookRenderer.shared.setCube(cube(for: selected))
        }
    }

    static let selectedKey = "look.file"
    let folder: URL
    private var cache: [String: CubeLUT] = [:]

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Looks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        selectedFile = UserDefaults.standard.string(forKey: Self.selectedKey)
        reload()
        LookRenderer.shared.setCube(cube(for: selected))
    }

    var selected: Look {
        looks.first { $0.fileName == selectedFile } ?? .standard
    }

    /// The table for a look; the Standard one when a file can't be read. None for no look: the picture as recorded.
    func cube(for look: Look) -> CubeLUT? {
        if look.isAsRecorded {
            return nil
        }
        guard let fileName = look.fileName else { return CubeLUT.standard }
        if let cached = cache[fileName] { return cached }
        let url = folder.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8), let cube = CubeLUT.parse(text) else {
            return CubeLUT.standard
        }
        cache[fileName] = cube
        return cube
    }

    var currentCube: CubeLUT? { cube(for: selected) }

    /// The look graded copies use: the one you've picked, or Standard while you've picked no look, as a copy in flat
    /// Log would look washed out for posting.
    var gradingLook: Look { selected.isAsRecorded ? .standard : selected }

    var gradingCube: CubeLUT? { cube(for: gradingLook) }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let custom = files
            .filter { ($0 as NSString).pathExtension.lowercased() == "cube" }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { Look(fileName: $0) }
        looks = [.standard, .asRecorded] + custom
        if let selectedFile, selectedFile != Look.asRecordedFile, !custom.contains(where: { $0.fileName == selectedFile }) {
            self.selectedFile = nil
        }
    }

    enum AddError: LocalizedError {
        case notACube
        var errorDescription: String? { "That isn't a 3D .cube LUT the app can read." }
    }

    /// Copies a .cube file in and picks it.
    func add(from source: URL) throws {
        let text = try String(contentsOf: source, encoding: .utf8)
        guard CubeLUT.parse(text) != nil else { throw AddError.notACube }
        let base = SongLibrary.cleanName(source.deletingPathExtension().lastPathComponent)
        let fileName = TripStore.freeName(base + ".cube", in: folder)
        try text.write(to: folder.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        cache[fileName] = nil
        reload()
        selectedFile = fileName
    }

    func delete(_ look: Look) {
        guard !look.isBuiltIn, let fileName = look.fileName else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
        cache[fileName] = nil
        reload()
    }
}
