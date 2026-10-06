import Foundation

/// Fixtures the whole test target shares.
///
/// Named once here so that a suite does not each decide for itself what "a
/// calendar" or "the corpus" means — two suites that disagree about either are
/// testing different things under the same words.

/// The calendar test dates are built with.
///
/// Gregorian, with the time zone stated. `Calendar.current` takes its calendar
/// system and zone from the machine, and `Calendar(identifier:)` fixes the system
/// and still inherits the zone — so a date built from either is a different
/// instant on a different machine.
enum TestCalendar {
    static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Noon UTC on the given day.
    ///
    /// Noon rather than midnight because the code under test reads dates back
    /// through its own calendar, in the machine's zone. Noon UTC falls on the same
    /// calendar day everywhere from UTC−12 to UTC+11, so the day a test names is
    /// the day the library sees; midnight UTC is the previous day anywhere west of
    /// Greenwich.
    static func noon(year: Int, month: Int, day: Int) -> Date? {
        gregorianUTC.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

/// The private corpus of workbooks, configured through `BUSINESSMATHEXCEL_CORPUS`.
///
/// The workbooks are teaching material and employer files, so none is checked in.
/// Suites that measure against them are enabled only when the corpus is there —
/// see ``isAvailable`` — and report as skipped otherwise.
enum Corpus {
    /// The configured root directories; empty when the variable is unset.
    static var roots: [String] {
        guard let configured = ProcessInfo.processInfo.environment["BUSINESSMATHEXCEL_CORPUS"],
              !configured.isEmpty
        else { return [] }
        return configured.split(separator: ":").map(String.init)
    }

    /// A workbook's root and its path beneath that root.
    ///
    /// Kept apart because a name is matched against the part beneath the root: a
    /// root that happened to contain the fragment would otherwise match every file.
    struct Entry {
        let root: String
        let relativePath: String
        var path: String { root + "/" + relativePath }
    }

    /// Every `.xlsx` under the configured roots, sorted by path. Lock files are left out.
    static var entries: [Entry] {
        var entries: [Entry] = []
        for root in roots {
            guard let walk = FileManager.default.enumerator(atPath: root) else { continue }
            for case let entry as String in walk
            where entry.lowercased().hasSuffix(".xlsx") && !entry.contains("~$") {
                entries.append(Entry(root: root, relativePath: entry))
            }
        }
        return entries.sorted { $0.path < $1.path }
    }

    /// The full path of every workbook in the corpus, sorted.
    static var files: [String] { entries.map(\.path) }

    /// Whether there is anything to measure.
    static var isAvailable: Bool { !entries.isEmpty }

    /// The workbooks whose path beneath the root contains `fragment`, case-insensitively.
    static func entries(named fragment: String) -> [Entry] {
        entries.filter { $0.relativePath.lowercased().contains(fragment.lowercased()) }
    }
}

/// The third-party reference workbook. See `Tests/Fixtures/README.md` for where to
/// fetch it and why it is not checked in.
enum WhartonFixture {
    static let name = "Wharton-LBO-Practice-Model.xlsx"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    static var isPresent: Bool { (try? url.checkResourceIsReachable()) == true }
}

/// A fixture a test was enabled for turned out not to be loadable.
///
/// Distinct from a skip: the enabling condition said the file was there.
struct FixtureUnavailable: Error, CustomStringConvertible {
    let description: String
}
